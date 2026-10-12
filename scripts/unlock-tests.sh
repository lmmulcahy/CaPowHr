#!/usr/bin/env bash
# unlock-tests.sh <glob>... — HUMAN ONLY. Removes exact glob lines from
# .claude/test-lock so Claude may edit those test files again. Use when you
# agree a locked test is wrong. With no arguments, lists current locks.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
LOCK="$ROOT/.claude/test-lock"

if [[ $# -eq 0 ]]; then
    echo "Current locks (.claude/test-lock):"
    grep -v -E '^[[:space:]]*(#|$)' "$LOCK" 2>/dev/null | sed 's/^/  /' || echo "  (none)"
    echo "usage: scripts/unlock-tests.sh <glob> [<glob>...]"
    exit 0
fi

for glob in "$@"; do
    if grep -qxF -- "$glob" "$LOCK"; then
        tmp="$(mktemp)"
        grep -vxF -- "$glob" "$LOCK" > "$tmp" || true
        mv "$tmp" "$LOCK"
        echo "unlocked: $glob"
    else
        echo "not locked (no exact line): $glob" >&2
    fi
done
echo "Commit .claude/test-lock when you're done, and re-lock after the fix."
