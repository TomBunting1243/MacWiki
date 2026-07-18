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
ARTICLE_CACHE_DIR="$QA_HOME/Library/Caches/MacWiki/ArticleBodyCache"
ARTICLE_CACHE_FILE="$ARTICLE_CACHE_DIR/ada-lovelace-qa.json"
ARTICLE_CACHE_INDEX="$ARTICLE_CACHE_DIR/index.json"
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"
BUILD_INFO_PLIST="$APP_BUNDLE_PATH/Contents/Resources/BuildInfo.plist"
ARTICLE_TITLE="${ARTICLE_TITLE:-Ada Lovelace}"
ARTICLE_HTML='<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Ada Lovelace</title></head><body><main><h1>Ada Lovelace</h1><p>A deterministic public-domain QA fixture for MacWiki reader and inspector checks.</p><h2 id="legacy">Legacy</h2><p>Ada Lovelace wrote notes on the Analytical Engine.</p></main></body></html>'

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
POPOVER_RESULT="$OUTPUT_DIR/page-views-popover-ax.json"
REPORT_PATH="$OUTPUT_DIR/report.md"
rm -f "$APP_LOG" "$AX_RESULT" "$POPOVER_RESULT" "$REPORT_PATH"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_isolated_path "$QA_HOME/Library/Caches/MacWiki" "$QA_HOME"
mkdir -p "$STATE_DIR" "$QA_HOME/Library/Caches/MacWiki"
qa_assert_isolated_path "$ARTICLE_CACHE_DIR" "$QA_HOME"
qa_assert_no_conflicting_processes
mkdir -p "$ARTICLE_CACHE_DIR"
AX_DRIVER_BIN="$QA_HOME/ax-reader-inspector-journey"
POPOVER_DRIVER_BIN="$QA_HOME/ax-verify-toolbar-popover"
swiftc "$SCRIPT_DIR/ax_reader_inspector_journey.swift" -o "$AX_DRIVER_BIN"
swiftc "$SCRIPT_DIR/ax_verify_toolbar_popover.swift" -o "$POPOVER_DRIVER_BIN"

# Article session persistence intentionally excludes HTML. Seed the app's
# production disk-cache format inside the disposable QA home, then force the
# trusted harness offline so this Reader proof cannot silently depend on the
# network or a developer's normal cache.
jq -n \
  --arg title "$ARTICLE_TITLE" \
  --arg html "$ARTICLE_HTML" \
  '{title: $title, html: $html, pageId: 307, metadata: [], wordCount: 43}' \
  >"$ARTICLE_CACHE_FILE"
ARTICLE_CACHE_BYTES="$(stat -f %z "$ARTICLE_CACHE_FILE")"
ARTICLE_CACHE_NOW="$(date +%s)"
jq -n \
  --arg fileName "$(basename "$ARTICLE_CACHE_FILE")" \
  --argjson byteCount "$ARTICLE_CACHE_BYTES" \
  --argjson lastAccessedAt "$ARTICLE_CACHE_NOW" \
  '{version: 1, entries: {Ada_Lovelace: {fileName: $fileName, byteCount: $byteCount, lastAccessedAt: $lastAccessedAt, isPinned: false}}}' \
  >"$ARTICLE_CACHE_INDEX"
jq -e '.title == "Ada Lovelace" and (.html | contains("<title>Ada Lovelace</title>"))' \
  "$ARTICLE_CACHE_FILE" >/dev/null
jq -e '.version == 1 and .entries.Ada_Lovelace.byteCount > 0' \
  "$ARTICLE_CACHE_INDEX" >/dev/null

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
if (( MACWIKI_QA_VISUAL_HOLD_SECONDS > 0 )); then
  echo "Visual inspection hold: PID $QA_APP_PID for ${MACWIKI_QA_VISUAL_HOLD_SECONDS}s" >&2
  sleep "$MACWIKI_QA_VISUAL_HOLD_SECONDS"
fi
if ! qa_run_command_with_timeout 20 "$POPOVER_DRIVER_BIN" \
  "$QA_APP_PID" "Page Views" "Views" >"$POPOVER_RESULT"; then
  echo "Page Views toolbar popover did not present visible content." >&2
  exit 1
fi
if ! jq -e '
  .toolbarLabel == "Page Views"
  and .expectedContent == "Views"
  and (.observedContent | index("Views") != null)
' "$POPOVER_RESULT" >/dev/null; then
  echo "Page Views popover evidence omitted its visible content." >&2
  exit 1
fi
kill -0 "$QA_APP_PID"
if ! MACWIKI_QA_APP_LOG="$APP_LOG" qa_run_command_with_timeout 180 "$AX_DRIVER_BIN" \
  "$QA_APP_PID" "$ARTICLE_TITLE" >"$AX_RESULT"; then
  echo "Reader/inspector AX journey failed." >&2
  exit 1
fi
kill -0 "$QA_APP_PID"
if ! jq -e '
  (.toolbarPlaneContainment | contains("Reader controls"))
  and (.toolbarModeSwitchStability | contains("live samples"))
  and (.toolbarModeSwitchSampleCount >= 195)
  and (.inspectorAccessoryAlignment | contains("Inspector plane"))
  and (.readStateControlCycle | contains("Mark as Unread"))
' "$AX_RESULT" >/dev/null; then
  echo "Reader/inspector AX evidence omitted native toolbar geometry or stability proof." >&2
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
  printf -- '- Reader fixture source: isolated production `ArticleBodyCache`; network: forced offline\n'
  printf -- '- Reader assertions: native pane-tracking toolbar command reachability; every Reader control stays between dividers 1 and 2; Inspector toggle stays right-aligned inside the Reader; Read/Unread changes in place and restores; Page Views presents visible popover content; exactly one native Find UI\n'
  printf -- '- Workspace assertions: four visible AppKit pane regions, Inspector spanning the full Reader pane height, all eight auxiliary visibility states, 20 independent Lists/List Contents cycles, and stable Reader Web-area identity\n'
  printf -- '- Inspector assertions: native tab group aligned in the Inspector toolbar plane with stable identity/frame and exactly one selected tab; Info/Notes/References content; live toolbar sampling during 12 rapid mode cycles; six hide/restore cycles plus one interrupted transition; no collapsed ghost chrome\n'
  printf -- '- Narrow-window assertion: with Lists intentionally hidden, restoring List Contents and Inspector preserves the 900-point window, a usable Reader, and tab-group containment inside the Inspector\n'
  printf -- '- Visual-only follow-up: materials, hover/pressed treatment, animation quality, and perceived jank still require fresh Computer Use evidence; placement and transition stability are independently asserted through AX geometry.\n'
  printf -- '- AX evidence: `%s`\n' "$AX_RESULT"
  printf -- '- Page Views popover evidence: `%s`\n' "$POPOVER_RESULT"
  printf -- '- Production preferences/data touched: **No** — state, defaults, persistence, and caches were isolated.\n'
} >"$REPORT_PATH"

echo "Reader/inspector journey passed: $REPORT_PATH"
