#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/highlight-selection-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/highlight-selection-rehydrate}"
STATE_DIR="$QA_HOME/Library/Application Support/MacWiki"
STATE_FILE="$STATE_DIR/state.json"
STORE_PATH="$QA_HOME/Library/Application Support/default.store"
ARTICLE_TITLE="${ARTICLE_TITLE:-Ada Lovelace}"
HIGHLIGHT_TEXT="${HIGHLIGHT_TEXT:-Augusta Ada King}"
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
[[ "$HIGHLIGHT_TEXT" != *"'"* ]] || { echo "Highlight text may not contain a SQL quote" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR" "$STATE_DIR"
APP_LOG="$OUTPUT_DIR/create-app.log"
RELAUNCH_LOG="$OUTPUT_DIR/rehydrate-app.log"
CREATE_RESULT="$OUTPUT_DIR/create-ax.json"
REHYDRATE_RESULT="$OUTPUT_DIR/rehydrate-ax.json"
CREATE_DRIVER_LOG="$OUTPUT_DIR/create-driver.log"
REHYDRATE_DRIVER_LOG="$OUTPUT_DIR/rehydrate-driver.log"
DATABASE_SNAPSHOT="$OUTPUT_DIR/highlight-record.json"
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

qa_launch_candidate "$APP_LOG"
APP_PID="$QA_APP_PID" qa_run_command_with_timeout 90 swift \
  "$SCRIPT_DIR/ax_highlight_selection_rehydrate.swift" create "$QA_APP_PID" "$HIGHLIGHT_TEXT" \
  >"$CREATE_RESULT" 2>"$CREATE_DRIVER_LOG"
kill -0 "$QA_APP_PID"
qa_stop_exact

for _ in $(seq 1 60); do
  [[ -f "$STORE_PATH" ]] && break
  sleep 0.1
done
[[ -f "$STORE_PATH" ]] || { echo "Highlight creation did not produce an isolated SwiftData store" >&2; exit 1; }

sqlite3 -json "$STORE_PATH" \
  "SELECT ZTEXT AS text, ZARTICLETITLE AS articleTitle, ZELEMENTPATH AS elementPath,
          ZSTARTOFFSET AS startOffset, ZLENGTH AS length,
          ZCONTEXTBEFORE AS contextBefore, ZCONTEXTAFTER AS contextAfter,
          ZSECTIONTITLE AS sectionTitle, ZCOLORRAW AS color,
          ZISSTALERAW AS isStale, ZISARCHIVEDRAW AS isArchived
     FROM ZHIGHLIGHT WHERE ZTEXT='$HIGHLIGHT_TEXT';" >"$DATABASE_SNAPSHOT"

RECORD_COUNT="$(jq 'length' "$DATABASE_SNAPSHOT")"
[[ "$RECORD_COUNT" == "1" ]] || { echo "Expected exactly one persisted highlight, found $RECORD_COUNT" >&2; exit 1; }
jq -e \
  --arg article "$ARTICLE_TITLE" \
  --argjson length "${#HIGHLIGHT_TEXT}" \
  '.[0]
   | .articleTitle == $article
   and (.elementPath | length > 0)
   and .startOffset == 0
   and .length == $length
   and (.contextBefore | length > 0)
   and (.contextAfter | length > 0)
   and .color == "Yellow"
   and .isStale == 0
   and .isArchived == 0' "$DATABASE_SNAPSHOT" >/dev/null || {
  echo "Persisted highlight omitted its real DOM anchor, context, color, or live-state metadata" >&2
  exit 1
}

qa_assert_no_conflicting_processes
qa_launch_candidate "$RELAUNCH_LOG"
APP_PID="$QA_APP_PID" qa_run_command_with_timeout 90 swift \
  "$SCRIPT_DIR/ax_highlight_selection_rehydrate.swift" rehydrate "$QA_APP_PID" "$HIGHLIGHT_TEXT" \
  >"$REHYDRATE_RESULT" 2>"$REHYDRATE_DRIVER_LOG"
kill -0 "$QA_APP_PID"

PERSISTED_COUNT="$(sqlite3 "$STORE_PATH" "SELECT count(*) FROM ZHIGHLIGHT WHERE ZTEXT='$HIGHLIGHT_TEXT' AND ZISSTALERAW=0 AND ZISARCHIVEDRAW=0;")"
[[ "$PERSISTED_COUNT" == "1" ]] || {
  echo "Relaunch did not preserve exactly one live, non-stale highlight" >&2
  exit 1
}

if rg -ni 'fatal error|precondition failed|assertion failed' "$APP_LOG" "$RELAUNCH_LOG" >"$OUTPUT_DIR/runtime-failures.txt"; then
  echo "Runtime diagnostics contained a fatal, assertion, or precondition failure." >&2
  exit 1
fi
: >"$OUTPUT_DIR/runtime-failures.txt"
rg -n 'AttributeGraph: cycle detected' "$APP_LOG" "$RELAUNCH_LOG" >"$OUTPUT_DIR/attributegraph-cycles.txt" || true
ATTRIBUTEGRAPH_CYCLE_COUNT="$(wc -l <"$OUTPUT_DIR/attributegraph-cycles.txt" | tr -d '[:space:]')"
[[ "$ATTRIBUTEGRAPH_CYCLE_COUNT" == "0" ]] || {
  echo "Rendered highlight journey emitted $ATTRIBUTEGRAPH_CYCLE_COUNT AttributeGraph cycles" >&2
  exit 1
}

qa_stop_exact
if qa_exact_binary_pids | grep -q .; then
  echo "Exact candidate process remained after highlight rehydration QA" >&2
  exit 1
fi

{
  printf '# Rendered Highlight Creation and Rehydration QA\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Public article: `%s`\n' "$ARTICLE_TITLE"
  printf -- '- Pointer-selected rendered text: `%s`\n' "$HIGHLIGHT_TEXT"
  printf -- '- Creation path: WebKit AX range bounds → real pointer drag → native Highlight → Yellow\n'
  printf -- '- Persisted metadata: exact text/article, real DOM path and offsets, before/after context, Yellow, live, non-stale\n'
  printf -- '- Relaunch path: persisted CSS highlight exposed native Highlight Color/Delete Highlight menu and populated Notes row\n'
  printf -- '- AttributeGraph cycles: `%s`\n' "$ATTRIBUTEGRAPH_CYCLE_COUNT"
  printf -- '- Exact process cleanup: `PASS`\n'
  printf -- '- Creation AX evidence: `%s`\n' "$CREATE_RESULT"
  printf -- '- Rehydration AX evidence: `%s`\n' "$REHYDRATE_RESULT"
  printf -- '- SwiftData evidence: `%s`\n' "$DATABASE_SNAPSHOT"
  printf -- '- Production preferences/data touched: **No** — state, defaults, persistence, caches, and the defaults suite were isolated and removed.\n'
} >"$REPORT_PATH"

echo "Rendered highlight selection and rehydration QA passed: $REPORT_PATH"
