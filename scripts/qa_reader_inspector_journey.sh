#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/reader-inspector-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/reader-inspector}"
STATE_DIR="$QA_HOME/Library/Application Support/MacWiki"
STATE_FILE="$STATE_DIR/state.json"
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"
BUILD_INFO_PLIST="$APP_BUNDLE_PATH/Contents/Resources/BuildInfo.plist"
ARTICLE_TITLE="${ARTICLE_TITLE:-Ada Lovelace}"

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

mkdir -p "$OUTPUT_DIR"
APP_LOG="$OUTPUT_DIR/app.log"
AX_RESULT="$OUTPUT_DIR/reader-inspector-ax.json"
REPORT_PATH="$OUTPUT_DIR/report.md"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_no_conflicting_processes
mkdir -p "$STATE_DIR"

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
if ! qa_run_command_with_timeout 70 swift "$SCRIPT_DIR/ax_reader_inspector_journey.swift" \
  "$QA_APP_PID" "$ARTICLE_TITLE" >"$AX_RESULT"; then
  echo "Reader/inspector AX journey failed." >&2
  exit 1
fi
kill -0 "$QA_APP_PID"

{
  printf '# Reader and Inspector Accessibility Journey\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Exact candidate PID: `%s`\n' "$QA_APP_PID"
  printf -- '- Seeded public article: `%s`\n' "$ARTICLE_TITLE"
  printf -- '- Reader assertions: all twelve toolbar controls, native Find field/actions, dismissal\n'
  printf -- '- Inspector assertions: Info/Notes/References selected values and content, hide/restore command cycle\n'
  printf -- '- AX evidence: `%s`\n' "$AX_RESULT"
  printf -- '- Production preferences/data touched: **No** — state, defaults, persistence, and caches were isolated.\n'
} >"$REPORT_PATH"

echo "Reader/inspector journey passed: $REPORT_PATH"
