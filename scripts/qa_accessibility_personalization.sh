#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/accessibility-personalization-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/accessibility-personalization}"
STATE_DIR="$QA_HOME/Library/Application Support/MacWiki"
ARTICLE_CACHE_DIR="$QA_HOME/Library/Caches/MacWiki/ArticleBodyCache"
ARTICLE_CACHE_FILE="$ARTICLE_CACHE_DIR/ada-lovelace-accessibility-qa.json"
ARTICLE_CACHE_INDEX="$ARTICLE_CACHE_DIR/index.json"
ARTICLE_TITLE="Ada Lovelace"
ARTICLE_HTML='<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Ada Lovelace</title></head><body><main><h1>Ada Lovelace</h1><p>A deterministic public-domain fixture for glass and accessibility personalization checks.</p><h2 id="legacy">Legacy</h2><p>Ada Lovelace wrote notes on the Analytical Engine.</p></main></body></html>'

# shellcheck source=scripts/lib/qa_process_safety.sh
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

[[ -x "$APP_BIN" ]] || { echo "Candidate binary is not executable: $APP_BIN" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_no_conflicting_processes
mkdir -p "$STATE_DIR" "$ARTICLE_CACHE_DIR"
qa_assert_isolated_path "$STATE_DIR" "$QA_HOME"
qa_assert_isolated_path "$ARTICLE_CACHE_DIR" "$QA_HOME"

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
          description: "English mathematician (1815–1852)",
          extract: null,
          thumbnailURL: null,
          lastOpened: null,
          isRead: false,
          wordCount: 43
        },
        scrollPosition: 0
      }],
      currentIndex: 0,
      isNewTab: false
    }],
    activeTabId: $tabID,
    recentArticles: [],
    wikiHopSession: null
  }' >"$STATE_DIR/state.json"
export MACWIKI_QA_NETWORK_MODE=offline

APP_LOG="$OUTPUT_DIR/app.log"
REPORT_PATH="$OUTPUT_DIR/report.md"
PROFILES=(
  reduce-motion
  reduce-transparency
  increase-contrast
  differentiate-without-color
  all
)

for profile in "${PROFILES[@]}"; do
  export MACWIKI_QA_ACCESSIBILITY_PROFILE="$profile"
  qa_launch_candidate "$APP_LOG"
  qa_run_command_with_timeout 45 swift "$SCRIPT_DIR/ax_accessibility_personalization.swift" \
    "$QA_APP_PID" "$profile" >"$OUTPUT_DIR/$profile.json"

  if [[ "$profile" == "all" ]]; then
    sleep 1.5
    APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" APP_PID="$QA_APP_PID" \
      "$SCRIPT_DIR/capture_macwiki_window.sh" "$OUTPUT_DIR/all.png" >/dev/null
  fi

  qa_stop_exact
  sleep 0.35
done

unset MACWIKI_QA_ACCESSIBILITY_PROFILE
qa_launch_candidate "$APP_LOG"
sleep 1.5
APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" APP_PID="$QA_APP_PID" \
  "$SCRIPT_DIR/capture_macwiki_window.sh" "$OUTPUT_DIR/system.png" >/dev/null
qa_stop_exact
unset MACWIKI_QA_NETWORK_MODE

swift "$SCRIPT_DIR/compare_images.swift" \
  "$OUTPUT_DIR/system.png" "$OUTPUT_DIR/all.png" >"$OUTPUT_DIR/visual-diff.json"

if rg -ni 'fatal error|precondition failed|assertion failed' "$APP_LOG" >"$OUTPUT_DIR/runtime-failures.txt"; then
  echo "Runtime diagnostics contained a fatal, assertion, or precondition failure." >&2
  exit 1
fi
: >"$OUTPUT_DIR/runtime-failures.txt"

{
  printf '# Accessibility Personalization QA\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Profiles: `%s`\n' "${PROFILES[*]}"
  printf -- '- Native policy: production reads SwiftUI accessibility environment values; trusted QA profiles adapt the app-owned policy without changing macOS settings.\n'
  printf -- '- Visual fixture: isolated offline `%s` Reader tab with custom native glass chrome.\n' "$ARTICLE_TITLE"
  printf -- '- AX proof: every requested profile exposed its resolved values through the isolated diagnostic probe.\n'
  printf -- '- Visual proof: decoded RGBA comparison in `visual-diff.json` confirms rendered pixel changes between `system.png` and `all.png`.\n'
  printf -- '- Runtime failures: no fatal, assertion, or precondition messages.\n'
  printf -- '- Production preferences/data or global accessibility settings touched: **No**.\n'
} >"$REPORT_PATH"

echo "Accessibility personalization QA passed: $REPORT_PATH"
