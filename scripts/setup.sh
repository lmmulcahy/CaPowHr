#!/usr/bin/env bash
# setup.sh — run once per clone or worktree. Points git at the committed
# .githooks/ directory and makes the workflow scripts executable.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

git config core.hooksPath .githooks
chmod +x .githooks/* scripts/*.sh .claude/hooks/*.sh

for tool in jq xcodebuild xcrun; do
    command -v "$tool" >/dev/null || echo "warning: $tool not found (needed by verify and hooks)"
done

echo "Git hooks: core.hooksPath = $(git config core.hooksPath)"
echo "Next: scripts/verify.sh"
