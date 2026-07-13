#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN_DEFAULT="$REPO_ROOT/.build/arm64-apple-macosx/debug/MacWiki"
APP_BIN_FALLBACK="$REPO_ROOT/.build/debug/MacWiki"
APP_BIN="${APP_BIN:-$APP_BIN_DEFAULT}"
OUTPUT_DIR="${1:-/tmp/macwiki-qa/tab-navigation-$(date +%Y%m%d_%H%M%S)}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/tab-navigation-home-$(date +%Y%m%d_%H%M%S)-$RANDOM}"

if [[ ! -x "$APP_BIN" && -x "$APP_BIN_FALLBACK" ]]; then
  APP_BIN="$APP_BIN_FALLBACK"
fi
if [[ ! -x "$APP_BIN" ]]; then
  echo "ERROR: App binary not found: $APP_BIN" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
qa_prepare_isolated_home
cleanup() {
  qa_stop_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM
qa_launch_candidate "$OUTPUT_DIR/launch.log"

result_json="$(qa_run_command_with_timeout 30 swift "$SCRIPT_DIR/ax_tab_navigation.swift" "$QA_APP_PID" \
  2>"$OUTPUT_DIR/automation-errors.log")"

printf '%s\n' "$result_json" >"$OUTPUT_DIR/result.json"
{
  echo "kind,duration_ms,detail"
  jq -r '.durations[] | "tabSwitch,\(.),\"native next/previous shortcut to AX active-state publication\""' \
    "$OUTPUT_DIR/result.json"
} >"$OUTPUT_DIR/performance-metrics.csv"

initial_count="$(jq -r '.initialCount' "$OUTPUT_DIR/result.json")"
created_count="$(jq -r '.createdCount' "$OUTPUT_DIR/result.json")"
closed_count="$(jq -r '.closedCount' "$OUTPUT_DIR/result.json")"
reopened_count="$(jq -r '.reopenedCount' "$OUTPUT_DIR/result.json")"
{
  echo "# Tab Navigation Performance QA"
  echo
  echo "- Exact app binary: \`$APP_BIN\`"
  echo "- Initial tabs: \`$initial_count\`"
  echo "- After three Command-T actions: \`$created_count\`"
  echo "- After Command-W: \`$closed_count\`"
  echo "- After Command-Shift-T: \`$reopened_count\`"
  echo "- Measured next/previous switches: \`$(jq '.durations | length' "$OUTPUT_DIR/result.json")\`"
  echo "- Metrics: \`$OUTPUT_DIR/performance-metrics.csv\`"
} >"$OUTPUT_DIR/report.md"

echo "PASS: native tab create/switch/close/reopen journey verified."
echo "Report: $OUTPUT_DIR/report.md"
