#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/article-row-secondary-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/article-row-secondary-window}"
SEARCH_QUERY="${SEARCH_QUERY:-Albert Einstein}"
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

mkdir -p "$OUTPUT_DIR"
APP_LOG="$OUTPUT_DIR/app.log"
AX_RESULT="$OUTPUT_DIR/article-row-secondary-window-ax.json"
REPORT_PATH="$OUTPUT_DIR/report.md"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_no_conflicting_processes
/usr/bin/defaults write "${QA_DEFAULTS_SUITE:?}" qa.sidebarSearch.openOnLaunch -bool true
/usr/bin/defaults write "${QA_DEFAULTS_SUITE:?}" qa.sidebarSearch.queryOnLaunch -string "$SEARCH_QUERY"

qa_launch_candidate "$APP_LOG"
if ! qa_run_command_with_timeout 90 swift "$SCRIPT_DIR/ax_article_row_secondary_window.swift" \
  "$QA_APP_PID" "$SEARCH_QUERY" "$APP_LOG" >"$AX_RESULT"; then
  echo "Article-row/secondary-window AX verification failed." >&2
  exit 1
fi
kill -0 "$QA_APP_PID"
sleep 1

if rg -ni 'fatal error|precondition failed|assertion failed' "$APP_LOG" >"$OUTPUT_DIR/runtime-failures.txt"; then
  echo "Runtime diagnostics contained a fatal, assertion, or precondition failure." >&2
  exit 1
fi
: >"$OUTPUT_DIR/runtime-failures.txt"
ATTRIBUTEGRAPH_CYCLE_COUNT="$(rg -c 'AttributeGraph: cycle detected' "$APP_LOG" || true)"
rg -n 'AttributeGraph: cycle detected' "$APP_LOG" >"$OUTPUT_DIR/attributegraph-cycles.txt" || true

{
  printf '# Article Row and Secondary Window Accessibility\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Exact candidate PID: `%s`\n' "$QA_APP_PID"
  printf -- '- Search query: `%s`\n' "$SEARCH_QUERY"
  printf -- '- Row assertions: ten title-bearing semantic buttons with press and native context-menu actions\n'
  printf -- '- Mutation assertion: unread to read to unread through an independent native row button, with the inverse action exposed after each change\n'
  printf -- '- Secondary-window assertions: selected article, Metadata and Contents, inspector Info/Notes/References, main-window preservation\n'
  printf -- '- Runtime failures: no fatal, assertion, or precondition messages\n'
  printf -- '- AttributeGraph cycle advisories: `%s` (captured separately; the complete AX journey remained functional)\n' "$ATTRIBUTEGRAPH_CYCLE_COUNT"
  printf -- '- AX evidence: `%s`\n' "$AX_RESULT"
  printf -- '- Production preferences/data touched: **No** — defaults, persistence, caches, and article read state were isolated and restored.\n'
} >"$REPORT_PATH"

echo "Article-row/secondary-window verification passed: $REPORT_PATH"
