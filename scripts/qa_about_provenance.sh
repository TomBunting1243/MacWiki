#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/about-provenance-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/about-provenance}"
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"
BUILD_INFO_PLIST="$APP_BUNDLE_PATH/Contents/Resources/BuildInfo.plist"

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

mkdir -p "$OUTPUT_DIR"
REPORT_PATH="$OUTPUT_DIR/report.md"
SNAPSHOT_PATH="$OUTPUT_DIR/about-ax.json"
APP_LOG="$OUTPUT_DIR/app.log"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_no_conflicting_processes
qa_launch_candidate "$APP_LOG"

APP_PID="$QA_APP_PID" \
  qa_run_command_with_timeout 30 osascript -l JavaScript >"$SNAPSHOT_PATH" <<'JXA'
ObjC.import('stdlib')
const appPid = Number(ObjC.unwrap($.getenv('APP_PID')))
const se = Application('System Events')
const deadline = Date.now() + 20000
let process = null

while (Date.now() < deadline) {
  const matches = se.processes.whose({ unixId: appPid })()
  if (matches.length === 1 && matches[0].menuBars().length > 0) {
    process = matches[0]
    break
  }
  delay(0.2)
}
if (process === null) throw new Error(`PID ${appPid} did not expose a menu bar`)

const appMenu = process.menuBars[0].menuBarItems.byName('MacWiki')
appMenu.menus[0].menuItems.byName('About MacWiki').click()

let aboutWindow = null
while (Date.now() < deadline) {
  const windows = process.windows()
  for (const window of windows) {
    const name = String(window.name() || '')
    if (name.includes('About') || windows.length > 1) {
      aboutWindow = window
      break
    }
  }
  if (aboutWindow !== null) break
  delay(0.2)
}
if (aboutWindow === null) throw new Error('About MacWiki did not present a window')
console.log(JSON.stringify({ pid: appPid, windowName: String(aboutWindow.name() || '') }))
JXA

qa_run_command_with_timeout 30 swift "$SCRIPT_DIR/ax_about_snapshot.swift" \
  "$QA_APP_PID" "$VERSION" "$BUILD" >"$SNAPSHOT_PATH"

cat >"$REPORT_PATH" <<REPORT
# About and Provenance QA

- Result: **PASS**
- Candidate binary: \`$APP_BIN\`
- Version/build: \`$VERSION ($BUILD)\`
- BuildInfo commit: \`$TRACE_COMMIT\`
- BuildInfo dirty: \`$TRACE_DIRTY\`
- Exact candidate PID: \`$QA_APP_PID\`
- Native route: App menu → About MacWiki
- Rendered assertions: app name, version, build, product description, GitHub repository, Apache-2.0 license, and trademark link labels
- AX snapshot: \`$SNAPSHOT_PATH\`
- Production preferences/data touched: **No** — launch and persistence were isolated.
REPORT

echo "About/provenance QA passed: $REPORT_PATH"
