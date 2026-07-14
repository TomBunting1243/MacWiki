#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-}"
if [[ -z "$APP_BIN" ]]; then
  echo "ERROR: Set APP_BIN to an exact packaged MacWiki candidate binary." >&2
  exit 1
fi
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
OUTPUT_DIR="${1:-/tmp/macwiki-qa/tab-reorder-$(date +%Y%m%d_%H%M%S)}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/tab-reorder-home-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
STATE_DIR="$QA_HOME/Library/Application Support/MacWiki"
LEGACY_STATE="$STATE_DIR/state.json"
TAB_SNAPSHOT="$STATE_DIR/tab-session.json"
FIRST_LOG="$OUTPUT_DIR/first-run.log"
RELAUNCH_LOG="$OUTPUT_DIR/relaunch.log"
RESULT_JSON="$OUTPUT_DIR/first-result.json"
RELAUNCH_RESULT_JSON="$OUTPUT_DIR/relaunch-result.json"
DRIVER_LOG="$OUTPUT_DIR/driver.log"
TAB_COUNT=16
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"
BUILD_INFO_PLIST="$APP_BUNDLE_PATH/Contents/Resources/BuildInfo.plist"

if [[ ! -x "$APP_BIN" ]]; then
  echo "ERROR: App binary not found: $APP_BIN" >&2
  exit 1
fi
[[ -f "$INFO_PLIST" ]] || { echo "Candidate Info.plist is missing: $INFO_PLIST" >&2; exit 1; }
[[ -f "$BUILD_INFO_PLIST" ]] || { echo "Candidate BuildInfo.plist is missing: $BUILD_INFO_PLIST" >&2; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
TRACE_COMMIT="$(plutil -extract GitCommit raw "$BUILD_INFO_PLIST")"
TRACE_DIRTY="$(plutil -extract GitDirty raw "$BUILD_INFO_PLIST")"

[[ "$VERSION" == 1.0* ]] || { echo "Candidate is not on the 1.0 line: $VERSION" >&2; exit 1; }
[[ "$TRACE_DIRTY" == "false" ]] || { echo "BuildInfo says candidate source was dirty" >&2; exit 1; }
[[ "$TRACE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "BuildInfo commit is invalid" >&2; exit 1; }
qa_assert_candidate_manifest_matches_executable "$BUILD_INFO_PLIST"

mkdir -p "$OUTPUT_DIR"
: >"$FIRST_LOG"
: >"$RELAUNCH_LOG"
: >"$DRIVER_LOG"
qa_prepare_isolated_home
qa_assert_isolated_path "$STATE_DIR" "$QA_HOME"
qa_assert_no_conflicting_processes
mkdir -p "$STATE_DIR"

cleanup() {
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

tabs_json='[]'
active_tab_id=''
for index in $(seq 1 "$TAB_COUNT"); do
  tab_id="$(uuidgen)"
  history_id="$(uuidgen)"
  article_id="qa-tab-reorder-$index"
  title="$(printf 'QA %02d — Reorder and Overflow Verification Article' "$index")"
  if [[ -z "$active_tab_id" ]]; then
    active_tab_id="$tab_id"
  fi
  tabs_json="$(jq -c \
    --arg tabID "$tab_id" \
    --arg historyID "$history_id" \
    --arg articleID "$article_id" \
    --arg title "$title" \
    '. + [{
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
    }]' <<<"$tabs_json")"
done

jq -n \
  --argjson openTabs "$tabs_json" \
  --arg activeTabId "$active_tab_id" \
  '{openTabs: $openTabs, activeTabId: $activeTabId}' >"$LEGACY_STATE"

qa_launch_candidate "$FIRST_LOG"
FIRST_PID="$QA_APP_PID"
qa_run_command_with_timeout 90 swift "$SCRIPT_DIR/ax_tab_reorder.swift" \
  "$QA_APP_PID" "$TAB_COUNT" >"$RESULT_JSON" 2>"$DRIVER_LOG"
kill -0 "$QA_APP_PID"

for _ in $(seq 1 50); do
  [[ -f "$TAB_SNAPSHOT" ]] && break
  sleep 0.1
done
if [[ ! -f "$TAB_SNAPSHOT" ]]; then
  echo "ERROR: Tab reorder did not persist tab-session.json." >&2
  exit 1
fi

after_titles="$(jq -c '[.after[].title]' "$RESULT_JSON")"
persisted_titles="$(jq -c '[.openTabs[] | ([.. | objects | .title? // empty][0])]' "$TAB_SNAPSHOT")"
if [[ "$persisted_titles" != "$after_titles" ]]; then
  echo "ERROR: Persisted tab order does not match rendered order." >&2
  printf 'Rendered:  %s\nPersisted: %s\n' "$after_titles" "$persisted_titles" >&2
  exit 1
fi

qa_stop_exact
if qa_exact_binary_pids | grep -q .; then
  echo "ERROR: Exact candidate process remained after the first tab reorder run." >&2
  exit 1
fi

qa_launch_candidate "$RELAUNCH_LOG"
RELAUNCH_PID="$QA_APP_PID"
qa_run_command_with_timeout 90 swift "$SCRIPT_DIR/ax_tab_reorder.swift" \
  "$QA_APP_PID" "$TAB_COUNT" verify-order "$RESULT_JSON" \
  >"$RELAUNCH_RESULT_JSON" 2>>"$DRIVER_LOG"
kill -0 "$QA_APP_PID"

relaunch_titles="$(jq -c '[.after[].title]' "$RELAUNCH_RESULT_JSON")"
relaunch_overflow_count="$(jq -r '.overflowMenuTitles | length' "$RELAUNCH_RESULT_JSON")"
if [[ "$relaunch_titles" != "$after_titles" ]]; then
  echo "ERROR: Relaunched rendered tab order does not match the committed first-run order." >&2
  printf 'First run: %s\nRelaunch:  %s\n' "$after_titles" "$relaunch_titles" >&2
  exit 1
fi
if [[ "$relaunch_overflow_count" != "$TAB_COUNT" ]]; then
  echo "ERROR: Relaunched All Tabs overflow omitted seeded titles." >&2
  exit 1
fi

qa_stop_exact
if qa_exact_binary_pids | grep -q .; then
  echo "ERROR: Exact candidate process remained after tab reorder relaunch QA." >&2
  exit 1
fi

if rg -ni 'fatal error|precondition failed|assertion failed' \
  "$FIRST_LOG" "$RELAUNCH_LOG" >"$OUTPUT_DIR/runtime-failures.txt"; then
  echo "ERROR: Runtime diagnostics contained a fatal, assertion, or precondition failure." >&2
  exit 1
fi
: >"$OUTPUT_DIR/runtime-failures.txt"
ATTRIBUTEGRAPH_CYCLE_COUNT="$(rg -c 'AttributeGraph: cycle detected' "$FIRST_LOG" "$RELAUNCH_LOG" \
  | awk -F: '{ total += $NF } END { print total + 0 }')"
rg -n 'AttributeGraph: cycle detected' "$FIRST_LOG" "$RELAUNCH_LOG" \
  >"$OUTPUT_DIR/attributegraph-cycles.txt" || true
if [[ "$ATTRIBUTEGRAPH_CYCLE_COUNT" != "0" ]]; then
  echo "ERROR: Tab reorder journey emitted $ATTRIBUTEGRAPH_CYCLE_COUNT AttributeGraph cycles." >&2
  exit 1
fi

before_first="$(jq -r '.before[0].title' "$RESULT_JSON")"
after_index="$(jq -r --arg title "$before_first" '[.after[].title] | index($title)' "$RESULT_JSON")"
overflow_count="$(jq -r '.overflowMenuTitles | length' "$RESULT_JSON")"

{
  printf '# Tab Reorder and Overflow QA\n\n'
  printf -- '- Exact app binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Package manifest: `%s`\n' "$QA_PACKAGE_MANIFEST_PATH"
  printf -- '- Packaged executable SHA-256: `%s`\n' "$QA_PACKAGED_EXECUTABLE_SHA256"
  printf -- '- App tree SHA-256: `%s`\n' "$QA_APP_TREE_SHA256"
  printf -- '- Toolchain: `%s`; Mach-O minOS/SDK: `%s / %s`\n' \
    "$QA_XCODE_VERSION" "$QA_BINARY_MIN_OS" "$QA_BINARY_SDK"
  printf -- '- First-run PID: `%s`; relaunch PID: `%s`\n' "$FIRST_PID" "$RELAUNCH_PID"
  printf -- '- Seeded unique long-title tabs: `%s`\n' "$TAB_COUNT"
  printf -- '- All Tabs overflow entries: `%s`\n' "$overflow_count"
  printf -- '- Dragged title: `%s`\n' "$before_first"
  printf -- '- Persisted destination index: `%s`\n' "$after_index"
  printf -- '- Rendered and persisted tab orders: `MATCH`\n'
  printf -- '- Relaunched rendered order and overflow membership: `MATCH`\n'
  printf -- '- Runtime failures: no fatal, assertion, or precondition messages\n'
  printf -- '- AttributeGraph cycles: `%s`\n' "$ATTRIBUTEGRAPH_CYCLE_COUNT"
  printf -- '- Exact process cleanup: `PASS`\n'
  printf -- '- AX evidence: `%s`\n' "$RESULT_JSON"
  printf -- '- Relaunch AX evidence: `%s`\n' "$RELAUNCH_RESULT_JSON"
} >"$OUTPUT_DIR/report.md"

echo "PASS: tab reorder, overflow, persistence, relaunch, and cleanup verified."
echo "Report: $OUTPUT_DIR/report.md"
