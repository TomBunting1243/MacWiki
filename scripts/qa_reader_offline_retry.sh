#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/reader-offline-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/reader-offline-retry}"
STATE_DIR="$QA_HOME/Library/Application Support/MacWiki"
STATE_FILE="$STATE_DIR/state.json"
APP_LOG="$OUTPUT_DIR/app.log"
AX_RESULT="$OUTPUT_DIR/reader-offline-ax.json"
REPORT_PATH="$OUTPUT_DIR/report.md"
ARTICLE_TITLE="${ARTICLE_TITLE:-Ada Lovelace}"
ARTICLE_ID="$(uuidgen)"
TAB_ID="$(uuidgen)"
HISTORY_ID="$(uuidgen)"

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
mkdir -p "$STATE_DIR"

jq -n \
  --arg tabID "$TAB_ID" \
  --arg historyID "$HISTORY_ID" \
  --arg articleID "$ARTICLE_ID" \
  --arg title "$ARTICLE_TITLE" \
  '{
    openTabs: [{
      id: $tabID,
      history: [{
        id: $historyID,
        article: {
          id: $articleID,
          title: $title,
          description: null,
          extract: null,
          thumbnailURL: null,
          htmlContent: null,
          lastOpened: null,
          isRead: false,
          wordCount: null
        },
        scrollPosition: 0
      }],
      currentIndex: 0,
      isNewTab: false
    }],
    activeTabId: $tabID,
    recentArticles: [],
    wikiHopSession: null
  }' >"$STATE_FILE"

export MACWIKI_QA_NETWORK_MODE=offline
qa_launch_candidate "$APP_LOG"
qa_run_command_with_timeout 40 swift "$SCRIPT_DIR/ax_reader_offline_retry.swift" \
  "$QA_APP_PID" >"$AX_RESULT"
kill -0 "$QA_APP_PID"

cat >"$REPORT_PATH" <<REPORT
# Reader Offline and Retry QA

- Result: **PASS**
- Candidate binary: \`$APP_BIN\`
- Exact candidate PID: \`$QA_APP_PID\`
- Isolated defaults suite: \`$QA_DEFAULTS_SUITE\`
- Seeded article: \`$ARTICLE_TITLE\`
- Injected mode: \`offline\` (accepted only with a trusted QA defaults suite)
- Initial state: native reader failure surface exposed “Failed to Load Article,” an offline explanation, and “Try Again.”
- Retry: the exact button accepted native \`AXPress\`; the reader returned to the recoverable offline state without crashing or showing stale content.
- AX evidence: \`$AX_RESULT\`
- Production preferences/data/network touched: **No** — HOME, defaults, persistence, caches, and transport injection were isolated to this exact QA process.
REPORT

echo "Reader offline/retry QA passed: $REPORT_PATH"
