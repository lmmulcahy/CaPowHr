# Shared helpers for the guard hooks. Sourced, not executed.

# Files Claude may never modify: the lock list, the scripts that change it,
# and the guardrails that enforce it. The human edits these by hand.
PROTECTED_GLOBS=(
    ".claude/test-lock"
    ".claude/settings.json"
    ".claude/hooks/*"
    ".githooks/*"
    "scripts/lock-tests.sh"
    "scripts/unlock-tests.sh"
)

# repo_root_for <path> — git toplevel containing <path> (works for files that
# don't exist yet and for worktrees).
repo_root_for() {
    local dir="$1"
    [[ -d "$dir" ]] || dir="$(dirname "$dir")"
    while [[ ! -d "$dir" && "$dir" != "/" ]]; do dir="$(dirname "$dir")"; done
    git -C "$dir" rev-parse --show-toplevel 2>/dev/null
}

# rel_path <root> <abs path> — path relative to root, or the input unchanged.
rel_path() {
    local root="$1" path="$2"
    case "$path" in
        "$root"/*) echo "${path#"$root"/}" ;;
        *) echo "$path" ;;
    esac
}

# locked_globs <root> — non-empty, non-comment lines of .claude/test-lock.
locked_globs() {
    local lockfile="$1/.claude/test-lock"
    [[ -f "$lockfile" ]] || return 0
    grep -v -E '^[[:space:]]*(#|$)' "$lockfile" | sed -e 's/[[:space:]]*$//'
}

# matches_any <rel path> <glob>... — succeeds if the path matches any glob.
matches_any() {
    local rel="$1"; shift
    local g
    for g in "$@"; do
        # shellcheck disable=SC2053  # unquoted RHS = glob match on purpose
        [[ "$rel" == $g ]] && return 0
    done
    return 1
}

# matching_glob <rel path> <root> — prints the test-lock glob that matches.
matching_lock_glob() {
    local rel="$1" root="$2" g
    while IFS= read -r g; do
        # shellcheck disable=SC2053
        [[ "$rel" == $g ]] && { echo "$g"; return 0; }
    done < <(locked_globs "$root")
    return 1
}

deny_pretooluse() {
    jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
}
