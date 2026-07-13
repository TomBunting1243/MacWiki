#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/corrupt-session-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/corrupt-session-recovery}"
APP_SUPPORT="$QA_HOME/Library/Application Support/MacWiki"
APP_STATE="$APP_SUPPORT/app-state.json"
TAB_STATE="$APP_SUPPORT/tab-session.json"
APP_BACKUP="$APP_SUPPORT/app-state.corrupted.json"
TAB_BACKUP="$APP_SUPPORT/tab-session.corrupted.json"
APP_SENTINEL='{"corrupt-app-state":'
TAB_SENTINEL='{"corrupt-tab-state":'

# shellcheck source=scripts/lib/qa_process_safety.sh
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

mkdir -p "$OUTPUT_DIR"
REPORT_PATH="$OUTPUT_DIR/report.md"
FIRST_LOG="$OUTPUT_DIR/first-launch.log"
SECOND_LOG="$OUTPUT_DIR/second-launch.log"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_no_conflicting_processes
mkdir -p "$APP_SUPPORT"
printf '%s' "$APP_SENTINEL" >"$APP_STATE"
printf '%s' "$TAB_SENTINEL" >"$TAB_STATE"

wait_for_usable_window() {
  APP_PID="${QA_APP_PID:?}" qa_run_command_with_timeout 20 osascript -l JavaScript <<'JXA'
ObjC.import('stdlib')
const appPid = Number(ObjC.unwrap($.getenv('APP_PID')))
const se = Application('System Events')
const deadline = Date.now() + 15000
let result = null

while (Date.now() < deadline) {
  const matches = se.processes.whose({ unixId: appPid })()
  if (matches.length === 1) {
    const windows = matches[0].windows()
    if (windows.length > 0) {
      const size = windows[0].size()
      if (size.length === 2 && size[0] >= 600 && size[1] >= 400) {
        result = { pid: appPid, windowCount: windows.length, size }
        break
      }
    }
  }
  delay(0.2)
}
if (result === null) {
  throw new Error(`PID ${appPid} did not expose a usable MacWiki window`)
}
console.log(JSON.stringify(result))
JXA
}

qa_launch_candidate "$FIRST_LOG"
FIRST_WINDOW_JSON="$(wait_for_usable_window)"

[[ -f "$APP_BACKUP" ]] || { echo "Missing quarantined app-state backup" >&2; exit 1; }
[[ -f "$TAB_BACKUP" ]] || { echo "Missing quarantined tab-session backup" >&2; exit 1; }
[[ "$(<"$APP_BACKUP")" == "$APP_SENTINEL" ]] || { echo "App-state quarantine changed the corrupt payload" >&2; exit 1; }
[[ "$(<"$TAB_BACKUP")" == "$TAB_SENTINEL" ]] || { echo "Tab-session quarantine changed the corrupt payload" >&2; exit 1; }

FIRST_PID="$QA_APP_PID"
qa_stop_exact
sleep 0.5

qa_launch_candidate "$SECOND_LOG"
SECOND_WINDOW_JSON="$(wait_for_usable_window)"
SECOND_PID="$QA_APP_PID"

[[ "$FIRST_PID" != "$SECOND_PID" ]] || { echo "Relaunch reused the original process" >&2; exit 1; }
[[ -f "$APP_BACKUP" && -f "$TAB_BACKUP" ]] || { echo "Recovery backups disappeared after relaunch" >&2; exit 1; }

cat >"$REPORT_PATH" <<REPORT
# Corrupt Session Recovery QA

- Result: **PASS**
- Candidate binary: \`$APP_BIN\`
- Candidate bundle: \`$APP_BUNDLE_PATH\`
- Isolated defaults suite: \`$QA_DEFAULTS_SUITE\`
- First launch: \`$FIRST_WINDOW_JSON\`
- Second launch: \`$SECOND_WINDOW_JSON\`
- App-state quarantine: \`$APP_BACKUP\`
- Tab-session quarantine: \`$TAB_BACKUP\`
- Production preferences/data touched: **No** — HOME, CFFIXED_USER_HOME, defaults, and persistence paths were isolated.
- Recovery contract: malformed snapshots were preserved byte-for-byte as \`*.corrupted.json\`; the first launch reached a usable window; a new exact candidate process relaunched successfully from the recovered state.
REPORT

echo "Corrupt session recovery QA passed: $REPORT_PATH"
