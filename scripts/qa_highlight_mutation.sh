#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/highlight-mutation-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/highlight-mutation}"
STATE_DIR="$QA_HOME/Library/Application Support/MacWiki"
STATE_FILE="$STATE_DIR/state.json"
STORE_PATH="$QA_HOME/Library/Application Support/default.store"
ARTICLE_TITLE="${ARTICLE_TITLE:-Ada Lovelace}"
HIGHLIGHT_TEXT="${HIGHLIGHT_TEXT:-QA highlight verifies native Notes actions}"
NOTE_TEXT="${NOTE_TEXT:-QA note persisted through the native editor}"
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"
BUILD_INFO_PLIST="$APP_BUNDLE_PATH/Contents/Resources/BuildInfo.plist"

# shellcheck source=scripts/lib/qa_process_safety.sh
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

[[ -x "$APP_BIN" ]] || { echo "Candidate binary is not executable: $APP_BIN" >&2; exit 1; }
[[ -f "$INFO_PLIST" ]] || { echo "Candidate Info.plist is missing: $INFO_PLIST" >&2; exit 1; }
[[ -f "$BUILD_INFO_PLIST" ]] || { echo "Candidate BuildInfo.plist is missing: $BUILD_INFO_PLIST" >&2; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
TRACE_COMMIT="$(plutil -extract GitCommit raw "$BUILD_INFO_PLIST")"
TRACE_DIRTY="$(plutil -extract GitDirty raw "$BUILD_INFO_PLIST")"

[[ "$VERSION" == 1.0* ]] || { echo "Candidate is not on the 1.0 line: $VERSION" >&2; exit 1; }
[[ "$TRACE_DIRTY" == "false" ]] || { echo "BuildInfo says candidate source was dirty" >&2; exit 1; }
[[ "$TRACE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "BuildInfo commit is invalid" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR" "$STATE_DIR"
APP_LOG="$OUTPUT_DIR/app.log"
AX_RESULT="$OUTPUT_DIR/highlight-mutation-ax.json"
DRIVER_LOG="$OUTPUT_DIR/driver-errors.log"
REPORT_PATH="$OUTPUT_DIR/report.md"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_isolated_path "$STORE_PATH" "$QA_HOME"
qa_assert_no_conflicting_processes

ARTICLE_ID="$(uuidgen)"
TAB_ID="$(uuidgen)"
HISTORY_ID="$(uuidgen)"
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

/usr/bin/defaults write "${QA_DEFAULTS_SUITE:?}" qa.fixture.highlight.articleTitle -string "$ARTICLE_TITLE"
/usr/bin/defaults write "${QA_DEFAULTS_SUITE:?}" qa.fixture.highlight.text -string "$HIGHLIGHT_TEXT"

qa_launch_candidate "$APP_LOG"

APP_PID="$QA_APP_PID" qa_run_command_with_timeout 120 swift "$SCRIPT_DIR/ax_highlight_mutation.swift" \
  "$QA_APP_PID" "$HIGHLIGHT_TEXT" "$NOTE_TEXT" >"$AX_RESULT" 2>"$DRIVER_LOG" || qa_status=$?

if [[ "${qa_status:-0}" != "0" ]]; then
  if [[ -f "$STORE_PATH" ]]; then
    sqlite3 -header -tabs "$STORE_PATH" \
      "SELECT ZTEXT AS text, ZNOTE AS note, ZCOLOR AS color FROM ZHIGHLIGHT;" \
      >"$OUTPUT_DIR/failed-store-highlights.tsv" 2>/dev/null || true
  fi
  echo "Highlight mutation accessibility driver failed; diagnostic store inventory preserved." >&2
  exit "${qa_status:-1}"
fi

for _ in $(seq 1 60); do
  if [[ -f "$STORE_PATH" ]]; then
    remaining_count="$(sqlite3 "$STORE_PATH" "SELECT count(*) FROM ZHIGHLIGHT WHERE ZTEXT='$HIGHLIGHT_TEXT';" 2>/dev/null || true)"
    [[ "$remaining_count" == "0" ]] && break
  fi
  sleep 0.1
done
[[ "${remaining_count:-}" == "0" ]] || {
  echo "Deleted highlight remained in isolated SwiftData store" >&2
  exit 1
}

if rg -ni 'fatal error|precondition failed|assertion failed' "$APP_LOG" >"$OUTPUT_DIR/runtime-failures.txt"; then
  echo "Runtime diagnostics contained a fatal, assertion, or precondition failure." >&2
  exit 1
fi
: >"$OUTPUT_DIR/runtime-failures.txt"

{
  printf '# Highlight Mutation QA\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Exact candidate PID: `%s`\n' "$QA_APP_PID"
  printf -- '- Seeded public article: `%s`\n' "$ARTICLE_TITLE"
  printf -- '- Mutation assertions: populated Notes row, native note editor save, native Change Color → Blue, native Delete Highlight, persisted deletion\n'
  printf -- '- AX evidence: `%s`\n' "$AX_RESULT"
  printf -- '- Runtime failures: no fatal, assertion, or precondition messages\n'
  printf -- '- Production preferences/data touched: **No** — trusted fixture keys, state, defaults, persistence, and caches were isolated and removed.\n'
} >"$REPORT_PATH"

echo "Highlight mutation QA passed: $REPORT_PATH"
