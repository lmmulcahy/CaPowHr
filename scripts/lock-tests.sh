#!/usr/bin/env bash
# lock-tests.sh <glob>... — HUMAN ONLY. Adds globs to .claude/test-lock so
# Claude can no longer edit matching test files. Run after approving the
# tests /build wrote, e.g.:
#   scripts/lock-tests.sh "CaPowHr Watch AppTests/PauseReminderTests.swift"
# Also ends the "red phase" so the Stop hook enforces verify again.
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "usage: scripts/lock-tests.sh <glob> [<glob>...]" >&2
    exit 64
fi

ROOT="$(git rev-parse --show-toplevel)"
LOCK="$ROOT/.claude/test-lock"
touch "$LOCK"

for glob in "$@"; do
    if grep -qxF -- "$glob" "$LOCK"; then
        echo "already locked: $glob"
    else
        echo "$glob" >> "$LOCK"
        echo "locked: $glob"
    fi
    # compgen -G takes the pattern as one word, so paths with spaces work.
    matches=$(cd "$ROOT" && { compgen -G "$glob" || true; } | wc -l | tr -d ' ')
    [[ "$matches" == "0" ]] && echo "  warning: '$glob' matches no existing file"
done

rm -f "$ROOT/.claude/.verify-state/red-phase"
echo "Commit .claude/test-lock so the lock travels with the branch."
