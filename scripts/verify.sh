#!/usr/bin/env bash
# verify.sh — the single source of truth for "does this tree work?"
#
# Steps: build (= typecheck), lint, unit tests, and optionally UI tests.
# Exits non-zero if any step fails. Full output, a timestamp and the commit
# hash go to .claude/last-verify.log; the summary block at the end of that
# log is the evidence pasted into PRs.
#
# Usage:
#   scripts/verify.sh                 build + lint + unit tests
#   VERIFY_UI=1 scripts/verify.sh     ...plus UI tests (used by /ship)
#   scripts/verify.sh --fingerprint   print the source fingerprint and exit
#
# Env:
#   VERIFY_DEST   xcodebuild -destination override, e.g. "id=<simulator udid>"
#   VERIFY_UI=1   also run the UI test target (slow: ~2 min)

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

LOG="$ROOT/.claude/last-verify.log"
STATE_DIR="$ROOT/.claude/.verify-state"
PROJECT="CaPowHr.xcodeproj"
SCHEME="CaPowHr Watch App"
UNIT_TARGET="CaPowHr Watch AppTests"
UI_TARGET="CaPowHr Watch AppUITests"
DERIVED="$ROOT/build/DerivedData-verify"

# Fingerprint of everything that affects the build. The Stop and pre-commit
# hooks compare it against the last passing run to skip redundant verifies.
# Sorted, because ls-files lists tracked files before untracked ones and
# staging a new file would otherwise change the fingerprint.
fingerprint() {
    {
        git ls-files -co --exclude-standard -z -- \
            '*.swift' '*.pbxproj' '*.plist' '*.xcconfig' '*.entitlements' '*.xcscheme' \
            | sort -z | xargs -0 shasum 2>/dev/null
    } | shasum | cut -d' ' -f1
}

if [[ "${1:-}" == "--fingerprint" ]]; then
    fingerprint
    exit 0
fi

# Pick a watchOS simulator by UDID. Selecting by name is ambiguous when two
# runtimes share a version number, so resolve the newest runtime's first
# "Apple Watch Series" device unless VERIFY_DEST is set.
resolve_destination() {
    if [[ -n "${VERIFY_DEST:-}" ]]; then
        echo "$VERIFY_DEST"
        return
    fi
    local udid
    udid="$(xcrun simctl list devices available -j | jq -r '
        .devices
        | to_entries
        | map(select(.key | test("watchOS")))
        | sort_by(.key | capture("watchOS-(?<maj>[0-9]+)-(?<min>[0-9]+)") | [(.maj|tonumber), (.min|tonumber)])
        | last.value
        | (map(select(.name | test("Series"))) + .)
        | first.udid // empty')"
    if [[ -z "$udid" ]]; then
        echo "ERROR: no available watchOS simulator; set VERIFY_DEST" >&2
        exit 2
    fi
    echo "id=$udid"
}

mkdir -p "$(dirname "$LOG")" "$STATE_DIR"
: > "$LOG"

log() { echo "$*" | tee -a "$LOG"; }

COMMIT="$(git rev-parse --short HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
DIRTY=""
[[ -n "$(git status --porcelain)" ]] && DIRTY=" + uncommitted changes"
DEST="$(resolve_destination)" || exit 2
FP="$(fingerprint)"

log "=== verify.sh started $(date '+%Y-%m-%d %H:%M:%S %Z') ==="
log "commit: $COMMIT ($BRANCH)$DIRTY"
log "destination: $DEST"
log ""

FAILED=0
declare -a SUMMARY

run_step() {
    local name="$1"; shift
    local start=$SECONDS
    log "--- $name: $* ---"
    "$@" >> "$LOG" 2>&1
    local rc=$?
    local secs=$((SECONDS - start))
    if [[ $rc -eq 0 ]]; then
        SUMMARY+=("$name: PASS (${secs}s)")
        echo "$name: PASS (${secs}s)"
    else
        SUMMARY+=("$name: FAIL exit $rc (${secs}s)")
        echo "$name: FAIL exit $rc (${secs}s)"
        FAILED=1
    fi
    return $rc
}

XCB=(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" -derivedDataPath "$DERIVED")

# 1. Build app + test bundles. The Swift compiler is the typechecker.
if run_step "build+typecheck" "${XCB[@]}" build-for-testing; then
    BUILD_OK=1
else
    BUILD_OK=0
fi
# Read by the Stop hook during the red phase, when only a broken build blocks.
echo "$([[ $BUILD_OK -eq 1 ]] && echo PASS || echo FAIL)" > "$STATE_DIR/last-build-status"

# 2. Lint. No linter is configured in this repo yet (SwiftLint is not installed).
if command -v swiftlint >/dev/null 2>&1 && [[ -f "$ROOT/.swiftlint.yml" ]]; then
    run_step "lint" swiftlint lint --strict --quiet
else
    SUMMARY+=("lint: SKIP (no linter configured)")
    echo "lint: SKIP (no linter configured)"
fi

count_tests() {
    # Prints "<passed> passed, <failed> failed" for the section of the log after marker $1.
    # Counts each parameterized case. Matches the "' passed on '" fragment
    # anywhere in a line, because xcodebuild's own log lines can interleave
    # with (and split) a "Test case '...'" line.
    local marker="$1"
    local section
    section="$(awk -v m="$marker" 'index($0, m) {found=1} found' "$LOG" | grep -v "^Test suite '")"
    local passed failed
    passed="$(grep -c "' passed on '" <<<"$section")"
    failed="$(grep -c "' failed on '" <<<"$section")"
    echo "$passed passed, $failed failed"
}

# 3. Unit tests.
if [[ $BUILD_OK -eq 1 ]]; then
    run_step "unit tests" "${XCB[@]}" test-without-building -only-testing:"$UNIT_TARGET"
    SUMMARY[${#SUMMARY[@]}-1]+=" — $(count_tests "--- unit tests:")"
else
    SUMMARY+=("unit tests: NOT RUN (build failed)")
fi

# 4. UI tests (opt-in).
if [[ "${VERIFY_UI:-0}" == "1" ]]; then
    if [[ $BUILD_OK -eq 1 ]]; then
        run_step "ui tests" "${XCB[@]}" test-without-building -only-testing:"$UI_TARGET"
        SUMMARY[${#SUMMARY[@]}-1]+=" — $(count_tests "--- ui tests:")"
    else
        SUMMARY+=("ui tests: NOT RUN (build failed)")
    fi
else
    SUMMARY+=("ui tests: SKIP (set VERIFY_UI=1)")
fi

RESULT="PASS"
[[ $FAILED -ne 0 ]] && RESULT="FAIL"

{
    echo ""
    echo "=== VERIFY SUMMARY ==="
    echo "finished: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "commit: $COMMIT ($BRANCH)$DIRTY"
    echo "fingerprint: $FP"
    for line in "${SUMMARY[@]}"; do echo "$line"; done
    echo "RESULT: $RESULT"
} | tee -a "$LOG"

if [[ $FAILED -eq 0 ]]; then
    echo "$FP" > "$STATE_DIR/last-pass-fingerprint"
    # A green suite ends /build's red phase (tests written, implementation pending).
    rm -f "$STATE_DIR/red-phase"
    exit 0
fi
rm -f "$STATE_DIR/last-pass-fingerprint"
echo "Full output: .claude/last-verify.log" >&2
exit 1
