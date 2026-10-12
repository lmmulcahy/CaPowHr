#!/usr/bin/env bash
# PreToolUse(Bash) hook for the reviewer subagent only. The reviewer is a
# critic: it may read git state, run verify, and read files — nothing else.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

cmd="$(jq -r '.tool_input.command // empty')"
[[ -z "$cmd" ]] && exit 0

# Reject command chaining/substitution/redirection so each part can't smuggle a write.
if grep -qE '[;&|`]|\$\(|>' <<<"$(sed -e 's/2>&1//g' -e 's/2>\/dev\/null//g' <<<"$cmd")"; then
    deny_pretooluse "Reviewer is read-only: run one simple command at a time (no ; && | > or \$( ))."
fi

ALLOW_RE='^[[:space:]]*(git[[:space:]]+(diff|log|show|status|rev-parse|merge-base|ls-files|blame|branch|grep|shortlog|cat-file)([[:space:]]|$)|(VERIFY_UI=1[[:space:]]+)?scripts/verify\.sh([[:space:]]|$)|gh[[:space:]]+pr[[:space:]]+(view|diff|list|checks)([[:space:]]|$)|(cat|head|tail|wc|ls|grep|rg|find|sed[[:space:]]+-n|awk|sort|uniq|diff)([[:space:]]|$))'
if ! grep -qE "$ALLOW_RE" <<<"$cmd"; then
    deny_pretooluse "Reviewer is read-only. Allowed: git diff/log/show/status/rev-parse/merge-base/ls-files/blame/branch/grep, scripts/verify.sh, gh pr view/diff/list/checks, and read-only text tools. Report what you would want changed as a finding instead."
fi
if grep -qE 'system[(]|find.*-(delete|exec|fprint)|git[[:space:]]+branch[[:space:]]+-[dDmM]|sed[[:space:]]+-n.*-i' <<<"$cmd"; then
    deny_pretooluse "Reviewer is read-only: that variant of the command can modify state."
fi
exit 0
