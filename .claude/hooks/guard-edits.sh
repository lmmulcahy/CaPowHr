#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|MultiEdit|NotebookEdit.
# Blocks edits to locked test files (.claude/test-lock) and to the guardrail
# files themselves.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

input="$(cat)"
path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
[[ -z "$path" ]] && exit 0

cwd="$(jq -r '.cwd // empty' <<<"$input")"
[[ "$path" != /* ]] && path="${cwd:-$PWD}/$path"

root="$(repo_root_for "$path")"
[[ -z "$root" ]] && exit 0
rel="$(rel_path "$root" "$path")"

if matches_any "$rel" "${PROTECTED_GLOBS[@]}"; then
    deny_pretooluse "BLOCKED: $rel is a workflow guardrail (test lock, hooks, or lock scripts) and only the human may change it. Stop and ask the human to make this change themselves; explain exactly what you want changed and why."
fi

if glob="$(matching_lock_glob "$rel" "$root")"; then
    deny_pretooluse "BLOCKED: tests are locked. $rel matches '$glob' in .claude/test-lock. Locked tests were approved by the human and must not be edited to make an implementation pass. If you believe this test is wrong, STOP and tell the human which assertion and why; they can run scripts/unlock-tests.sh '$glob'. Put new tests in a new file instead."
fi

exit 0
