#!/usr/bin/env bash
# Stop hook.
#  1. If build-relevant files have uncommitted changes that haven't passed
#     verify yet, run scripts/verify.sh. On failure, block the stop and feed
#     the errors back so Claude keeps working. stop_hook_active guards against
#     an endless loop: after MAX_RETRIES consecutive forced continuations the
#     stop is allowed and the human is told verify is still red.
#  2. If source changed on this branch (vs main) but nothing under docs/ did,
#     remind Claude once to update the spec. This never blocks.
set -uo pipefail

MAX_RETRIES=3

input="$(cat)"
active="$(jq -r '.stop_hook_active // false' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
root="$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

state="$root/.claude/.verify-state"
mkdir -p "$state"
[[ "$active" != "true" ]] && rm -f "$state/stop-retries"

SOURCE_PATHS=('*.swift' '*.pbxproj' '*.plist' '*.xcconfig' '*.entitlements' '*.xcscheme')

# ---- 1. verify ---------------------------------------------------------------
uncommitted_source="$(git status --porcelain -- "${SOURCE_PATHS[@]}")"
needs_verify=0
if [[ -n "$uncommitted_source" ]]; then
    fp="$(scripts/verify.sh --fingerprint)"
    last="$(cat "$state/last-pass-fingerprint" 2>/dev/null || true)"
    [[ "$fp" != "$last" ]] && needs_verify=1
fi

if [[ $needs_verify -eq 1 && -f "$state/red-phase" ]]; then
    # /build wrote failing tests and is waiting for the human to approve and
    # lock them. A red suite is expected; don't force Claude to "fix" it.
    feature="$(cat "$state/red-phase")"
    jq -n --arg f "$feature" '{systemMessage: ("verify skipped: red phase for \($f) — tests are written and expected to fail until you approve them and run scripts/lock-tests.sh")}'
    exit 0
fi

if [[ $needs_verify -eq 1 ]]; then
    if ! scripts/verify.sh > "$state/stop-verify.out" 2>&1; then
        retries="$(cat "$state/stop-retries" 2>/dev/null || echo 0)"
        if [[ "$active" == "true" && "$retries" -ge "$MAX_RETRIES" ]]; then
            rm -f "$state/stop-retries"
            jq -n --arg n "$MAX_RETRIES" '{systemMessage: ("scripts/verify.sh is still failing after \($n) automatic retries. Stopping so you can look; see .claude/last-verify.log")}'
            exit 0
        fi
        echo $((retries + 1)) > "$state/stop-retries"
        errors="$(grep -E '(error|failed|FAIL)' .claude/last-verify.log | grep -v -E '^(note|warning):' | sort -u | head -40)"
        summary="$(sed -n '/=== VERIFY SUMMARY ===/,$p' .claude/last-verify.log)"
        reason="scripts/verify.sh failed, so this work is not done. Fix the cause and let verify pass before stopping. Do not edit locked tests or weaken assertions; if a test looks wrong, say so to the human instead.

$summary

Errors (from .claude/last-verify.log):
$errors"
        jq -n --arg r "$reason" '{decision: "block", reason: $r}'
        exit 0
    fi
fi
rm -f "$state/stop-retries"

# ---- 2. docs reminder (warn only, once per state of the tree) -----------------
[[ "$active" == "true" ]] && exit 0

base="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)"
[[ -z "$base" ]] && exit 0

changed="$( { git diff --name-only "$base"; git ls-files -o --exclude-standard; } | sort -u)"
src_changed="$(grep -E '\.swift$|\.pbxproj$|\.plist$|\.entitlements$' <<<"$changed" || true)"
docs_changed="$(grep -E '^docs/' <<<"$changed" || true)"

if [[ -n "$src_changed" && -z "$docs_changed" ]]; then
    key="$(shasum <<<"$src_changed$(git diff "$base" -- "${SOURCE_PATHS[@]}" | shasum)" | cut -d' ' -f1)"
    if [[ "$(cat "$state/docs-warned" 2>/dev/null)" != "$key" ]]; then
        echo "$key" > "$state/docs-warned"
        msg="Reminder (not blocking): source files changed on this branch but nothing under docs/ did. If this is Full Path work, update docs/specs/<feature>.md (tick plan checkboxes, record deviations) and append to docs/decisions.md if a real decision was made. If it is a Quick Path change, no docs update is needed; just say so. Changed source: $(tr '\n' ' ' <<<"$src_changed")"
        jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $m}}'
    fi
fi
exit 0
