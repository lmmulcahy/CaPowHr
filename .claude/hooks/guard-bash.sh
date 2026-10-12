#!/usr/bin/env bash
# PreToolUse hook for Bash. Best-effort backstop for the edit guard: shell
# commands can write files too. It blocks
#   - skipping git hooks (--no-verify, or overriding core.hooksPath)
#   - running the lock/unlock scripts (human only)
#   - write-like commands that name a locked test file or a guardrail file
#     (including .claude/test-lock) in the same command segment
# Read-only use (cat, grep, git diff) and staging (git add) are allowed.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
[[ -z "$cmd" ]] && exit 0
cwd="$(jq -r '.cwd // empty' <<<"$input")"

if grep -qE -- '--no-verify|core\.hooksPath' <<<"$cmd"; then
    deny_pretooluse "BLOCKED: bypassing git hooks (--no-verify / core.hooksPath) is not allowed. If the pre-commit check fails, fix the cause; if you think the check itself is wrong, stop and ask the human."
fi

# Running the lock scripts is human-only. Mentioning them in read-only or
# staging git commands (git add/diff/log/show/status) is fine.
without_git_reads="$(sed -E 's/git[[:space:]]+(add|diff|log|show|status|ls-files|blame)[^;&|]*//g' <<<"$cmd")"
if grep -qE '(un)?lock-tests\.sh' <<<"$without_git_reads"; then
    deny_pretooluse "BLOCKED: the test lock is managed only by the human (scripts/lock-tests.sh, scripts/unlock-tests.sh). Use the Read tool to see .claude/test-lock. Ask the human to run the script if a lock change is needed."
fi

# Write-like operations: in-place editors, file moves/removal, and git
# commands that rewrite working-tree files. Redirection is checked per file
# below so that "2>&1" or ">/dev/null" next to a read doesn't trip it.
WRITE_RE='(sed|perl|ruby)[[:space:]].*-i|(^|[[:space:]])tee[[:space:]]|(^|[[:space:]])(mv|rm|cp|truncate|dd|install|ln)[[:space:]]|git[[:space:]]+(checkout|restore|rm|mv|stash|reset|apply|am|cherry-pick|revert)|patch[[:space:]]|swift-format|swiftformat'
grep -qE "$WRITE_RE" <<<"$cmd" || grep -qE '>[^&]' <<<"$cmd " || exit 0

root="$(repo_root_for "${cwd:-$PWD}")"
[[ -z "$root" ]] && exit 0

# Split into segments at ; & | (and newlines) so a write in one part of a
# chain isn't blamed on a file merely read in another part.
segments=()
while IFS= read -r seg; do
    [[ -n "${seg//[[:space:]]/}" ]] && segments+=("$seg")
done < <(awk '{ n = split($0, parts, /[;&|]+/); for (i = 1; i <= n; i++) print parts[i] }' <<<"$cmd")

# A segment writes <base> if it has a write op and names it, or redirects into it.
segment_writes() {
    local seg="$1" base="$2"
    grep -qF -- "$base" <<<"$seg" || return 1
    grep -qE "$WRITE_RE" <<<"$seg" && return 0
    awk -v b="$base" '{ i = index($0, ">"); if (i && index(substr($0, i + 1), b)) found = 1 } END { exit found ? 0 : 1 }' <<<"$seg"
}

declare -a candidates=()
while IFS= read -r -d '' f; do
    candidates+=("$f")
done < <(git -C "$root" ls-files -co --exclude-standard -z)

for f in "${candidates[@]}"; do
    reason=""
    if matches_any "$f" "${PROTECTED_GLOBS[@]}"; then
        reason="it is a workflow guardrail"
    elif glob="$(matching_lock_glob "$f" "$root")"; then
        reason="it is a locked test (matches '$glob' in .claude/test-lock)"
    else
        continue
    fi
    base="$(basename "$f")"
    grep -qF -- "$base" <<<"$cmd" || continue
    for seg in "${segments[@]}"; do
        if segment_writes "$seg" "$base"; then
            deny_pretooluse "BLOCKED: this command looks like it modifies $f, and $reason. Locked tests and guardrails may only be changed by the human. If you think this file is wrong, stop and explain why to the human."
        fi
    done
done

exit 0
