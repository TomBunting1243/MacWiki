#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/search-offline-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/search-offline-retry}"
APP_LOG="$OUTPUT_DIR/app.log"
AX_RESULT="$OUTPUT_DIR/search-offline-ax.json"
REPORT_PATH="$OUTPUT_DIR/report.md"
QUERY="${QUERY:-Ada Lovelace}"

# shellcheck source=scripts/lib/qa_process_safety.sh
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

mkdir -p "$OUTPUT_DIR"
qa_prepare_isolated_home
qa_assert_no_conflicting_processes
/usr/bin/defaults write "$QA_DEFAULTS_SUITE" qa.sidebarSearch.openOnLaunch -bool true
/usr/bin/defaults write "$QA_DEFAULTS_SUITE" qa.sidebarSearch.queryOnLaunch -string "$QUERY"

export MACWIKI_QA_NETWORK_MODE=offline
qa_launch_candidate "$APP_LOG"
qa_run_command_with_timeout 40 swift "$SCRIPT_DIR/ax_reader_offline_retry.swift" \
  "$QA_APP_PID" "Search Unavailable" >"$AX_RESULT"
kill -0 "$QA_APP_PID"

cat >"$REPORT_PATH" <<REPORT
# Search Offline and Retry QA

- Result: **PASS**
- Candidate binary: \`$APP_BIN\`
- Exact candidate PID: \`$QA_APP_PID\`
- Isolated defaults suite: \`$QA_DEFAULTS_SUITE\`
- Seeded query: \`$QUERY\`
- Injected mode: \`offline\` (accepted only with a trusted QA defaults suite)
- Initial state: embedded Search exposed “Search Unavailable,” the actionable offline explanation, and a default-action “Try Again” button.
- Retry: the exact button accepted native \`AXPress\`; Search returned to the recoverable offline state without crashing.
- AX evidence: \`$AX_RESULT\`
- Production preferences/data/network touched: **No** — launch, defaults, persistence, caches, and transport injection were isolated.
REPORT

echo "Search offline/retry QA passed: $REPORT_PATH"
