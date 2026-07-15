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
ARTICLE_HTML='<main><h1>Ada Lovelace</h1><p>A deterministic public-domain QA fixture for MacWiki reader and inspector checks.</p><h2 id="legacy">Legacy</h2><p>Ada Lovelace wrote notes on the Analytical Engine.</p></main>'

# The shared launcher supports background activation for compatible harnesses,
# but SwiftUI does not publish this window scene to AX until first activation.
MACWIKI_QA_LAUNCH_BACKGROUND="${MACWIKI_QA_LAUNCH_BACKGROUND:-0}"
MACWIKI_QA_VISUAL_HOLD_SECONDS="${MACWIKI_QA_VISUAL_HOLD_SECONDS:-0}"
export MACWIKI_QA_LAUNCH_BACKGROUND

[[ "$MACWIKI_QA_VISUAL_HOLD_SECONDS" =~ ^[0-9]+$ ]] || {
  echo "Visual hold must be a non-negative whole number of seconds." >&2
  exit 1
}

# shellcheck source=scripts/lib/qa_process_safety.sh
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

[[ -x "$APP_BIN" ]] || { echo "Candidate binary is not executable: $APP_BIN" >&2; exit 1; }
[[ -f "$INFO_PLIST" ]] || { echo "Candidate Info.plist is missing: $INFO_PLIST" >&2; exit 1; }
[[ -f "$BUILD_INFO_PLIST" ]] || { echo "Candidate BuildInfo.plist is missing: $BUILD_INFO_PLIST" >&2; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
TRACE_VERSION="$(plutil -extract Version raw "$BUILD_INFO_PLIST")"
TRACE_BUILD="$(plutil -extract BuildNumber raw "$BUILD_INFO_PLIST")"
TRACE_COMMIT="$(plutil -extract GitCommit raw "$BUILD_INFO_PLIST")"
TRACE_DIRTY="$(plutil -extract GitDirty raw "$BUILD_INFO_PLIST")"

[[ "$VERSION" == 1.0* ]] || { echo "Candidate is not on the 1.0 line: $VERSION" >&2; exit 1; }
[[ "$TRACE_VERSION" == "$VERSION" ]] || { echo "BuildInfo version does not match Info.plist" >&2; exit 1; }
[[ "$TRACE_BUILD" == "$BUILD" ]] || { echo "BuildInfo build does not match Info.plist" >&2; exit 1; }
[[ "$TRACE_DIRTY" == "false" ]] || { echo "BuildInfo says candidate source was dirty" >&2; exit 1; }
[[ "$TRACE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "BuildInfo commit is invalid" >&2; exit 1; }
qa_assert_candidate_manifest_matches_executable "$BUILD_INFO_PLIST"

mkdir -p "$OUTPUT_DIR"
APP_LOG="$OUTPUT_DIR/app.log"
AX_RESULT="$OUTPUT_DIR/reader-inspector-ax.json"
REPORT_PATH="$OUTPUT_DIR/report.md"
rm -f "$APP_LOG" "$AX_RESULT" "$REPORT_PATH"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_no_conflicting_processes
mkdir -p "$STATE_DIR"
AX_DRIVER_BIN="$QA_HOME/ax-reader-inspector-journey"
swiftc "$SCRIPT_DIR/ax_reader_inspector_journey.swift" -o "$AX_DRIVER_BIN"

ARTICLE_ID="$(uuidgen)"
TAB_ID="$(uuidgen)"
HISTORY_ID="$(uuidgen)"
jq -n \
  --arg tabID "$TAB_ID" \
  --arg historyID "$HISTORY_ID" \
  --arg articleID "$ARTICLE_ID" \
  --arg title "$ARTICLE_TITLE" \
  --arg html "$ARTICLE_HTML" \
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
          htmlContent: $html,
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
if (( MACWIKI_QA_VISUAL_HOLD_SECONDS > 0 )); then
  echo "Visual inspection hold: PID $QA_APP_PID for ${MACWIKI_QA_VISUAL_HOLD_SECONDS}s" >&2
  sleep "$MACWIKI_QA_VISUAL_HOLD_SECONDS"
fi
if ! MACWIKI_QA_APP_LOG="$APP_LOG" qa_run_command_with_timeout 90 "$AX_DRIVER_BIN" \
  "$QA_APP_PID" "$ARTICLE_TITLE" >"$AX_RESULT"; then
  echo "Reader/inspector AX journey failed." >&2
  exit 1
fi
kill -0 "$QA_APP_PID"
READER_PID="$QA_APP_PID"
qa_stop_exact
if rg -n "fatal error|precondition failed|assertion failed|AttributeGraph: cycle detected" "$APP_LOG"; then
  echo "Reader/inspector journey emitted a fatal runtime diagnostic." >&2
  exit 1
fi

{
  printf '# Reader and Inspector Accessibility Journey\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Package manifest: `%s`\n' "$QA_PACKAGE_MANIFEST_PATH"
  printf -- '- Packaged executable SHA-256: `%s`\n' "$QA_PACKAGED_EXECUTABLE_SHA256"
  printf -- '- App tree SHA-256: `%s`\n' "$QA_APP_TREE_SHA256"
  printf -- '- Toolchain: `%s`; Mach-O minOS/SDK: `%s / %s`\n' \
    "$QA_XCODE_VERSION" "$QA_BINARY_MIN_OS" "$QA_BINARY_SDK"
  printf -- '- Exact candidate PID: `%s`\n' "$READER_PID"
  printf -- '- Isolated QA home: `%s`\n' "$QA_HOME"
  printf -- '- Seeded public article: `%s`\n' "$ARTICLE_TITLE"
  printf -- '- Reader assertions: full-width native toolbar command reachability, no retired custom More control, exactly one Find field, native Find actions, dismissal\n'
  printf -- '- Inspector assertions: native Info/Notes/References selection and content, 12 rapid mode cycles, six native hide/restore cycles\n'
  printf -- '- Narrow-window assertion: restoring native List Contents and Inspector preserves the 900-point window and a usable Reader\n'
  printf -- '- AX evidence: `%s`\n' "$AX_RESULT"
  printf -- '- Production preferences/data touched: **No** — state, defaults, persistence, and caches were isolated.\n'
} >"$REPORT_PATH"

echo "Reader/inspector journey passed: $REPORT_PATH"
