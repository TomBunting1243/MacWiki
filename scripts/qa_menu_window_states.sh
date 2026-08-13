#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/menu-window-states-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/menu-window-states}"
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
SNAPSHOT_PATH="$OUTPUT_DIR/menu-window-ax.json"
REPORT_PATH="$OUTPUT_DIR/report.md"
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

APP_PID="$QA_APP_PID" qa_run_command_with_timeout 60 osascript -l JavaScript >"$SNAPSHOT_PATH" <<'JXA'
ObjC.import('stdlib')

const pid = Number(ObjC.unwrap($.getenv('APP_PID')))
const systemEvents = Application('System Events')
const deadline = Date.now() + 20000
let process = null

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function waitUntil(predicate, message, timeoutMilliseconds = 12000) {
  const stop = Date.now() + timeoutMilliseconds
  while (Date.now() < stop) {
    try {
      if (predicate()) return
    } catch (_) {}
    delay(0.1)
  }
  throw new Error(message)
}

while (Date.now() < deadline) {
  const matches = systemEvents.processes.whose({ unixId: pid })()
  if (matches.length === 1 && matches[0].menuBars().length > 0 && matches[0].windows().length > 0) {
    process = matches[0]
    break
  }
  delay(0.2)
}
assert(process !== null, `PID ${pid} did not expose a menu bar and window`)

process.frontmost = true

function currentProcess() {
  const matches = systemEvents.processes.whose({ unixId: pid })()
  assert(matches.length === 1, `PID ${pid} is no longer uniquely reachable`)
  return matches[0]
}

function currentWindow() {
  const windows = currentProcess().windows()
  assert(windows.length > 0, `PID ${pid} has no reachable window`)
  return windows[0]
}

function menuItem(menuName, itemName) {
  const stop = Date.now() + 5000
  while (Date.now() < stop) {
    const item = menuItemIfPresent(menuName, itemName)
    if (item !== null) return item
    delay(0.1)
  }
  throw new Error(`menu item unavailable: ${menuName} → ${itemName}`)
}

function menuItemIfPresent(menuName, itemName) {
  try {
    const menuBars = currentProcess().menuBars()
    if (menuBars.length === 0) return null
    const menuBarItems = menuBars[0].menuBarItems.whose({ name: menuName })()
    if (menuBarItems.length !== 1) return null
    const menus = menuBarItems[0].menus()
    if (menus.length === 0) return null
    const items = menus[0].menuItems.whose({ name: itemName })()
    // SwiftUI exposes both native shortcut variants for Next/Previous Tab
    // with the same visible title. Either item represents the same action.
    return items.length > 0 ? items[0] : null
  } catch (_) {
    return null
  }
}

function enabled(menuName, itemName) {
  return Boolean(menuItem(menuName, itemName).enabled())
}

function assertDocumentReaderCommandsDisabled(context) {
  for (const [menuName, itemName] of [
    ['Article', 'Back'],
    ['Article', 'Forward'],
    ['Article', 'Mark as Read'],
    ['Article', 'Reader Style…'],
    ['Article', 'Page Views…'],
    ['Article', 'Open in Browser'],
    ['Article', 'Share…'],
    ['View', 'Increase Reader Font Size'],
    ['View', 'Decrease Reader Font Size'],
    ['View', 'Reset Reader Font Size']
  ]) {
    assert(!enabled(menuName, itemName), `${menuName} → ${itemName} must be disabled ${context}`)
  }
}

function commandCharacter(menuName, itemName) {
  const item = menuItem(menuName, itemName)
  return String(item.attributes.byName('AXMenuItemCmdChar').value() || '')
}

function fullScreenValue() {
  const window = currentWindow()
  try { return Boolean(window.attributes.byName('AXFullScreen').value()) } catch (_) { return false }
}

function windowSnapshot(label) {
  const current = currentProcess()
  const window = currentWindow()
  return {
    label,
    name: String(window.name() || ''),
    position: window.position(),
    size: window.size(),
    fullScreen: fullScreenValue(),
    processFrontmost: Boolean(current.frontmost())
  }
}

const observations = { pid, states: [], commands: {} }
observations.states.push(windowSnapshot('initial'))

for (const [menuName, itemName, expectedCharacter] of [
  ['MacWiki', 'Settings…', ','],
  ['Tabs', 'New Tab', 'T'],
  ['Edit', 'Search Wikipedia', 'K'],
  ['Edit', 'Find in Page', 'F'],
  ['View', 'Toggle Inspector', 'I'],
  ['Article', 'Back', '['],
  ['Article', 'Forward', ']'],
  ['Article', 'Open in Browser', 'O'],
  ['View', 'Increase Reader Font Size', '='],
  ['View', 'Decrease Reader Font Size', '-'],
  ['View', 'Reset Reader Font Size', '0']
]) {
  const actualCharacter = commandCharacter(menuName, itemName)
  assert(actualCharacter === expectedCharacter, `${menuName} → ${itemName} shortcut was ${actualCharacter}`)
  observations.commands[`${menuName} → ${itemName}`] = actualCharacter
}

assert(enabled('MacWiki', 'About MacWiki'), 'About MacWiki must be enabled')
assert(enabled('MacWiki', 'Settings…'), 'Settings must be enabled')
assert(enabled('Library', 'New Reading List'), 'New Reading List must be enabled')
assert(enabled('Library', 'New Folder'), 'New Folder must be enabled')
assert(enabled('Tabs', 'New Tab'), 'New Tab must be enabled')
assert(enabled('File', 'Close'), 'Close must remain available as native window close without a tab')
assert(!enabled('Tabs', 'Reopen Closed Tab'), 'Reopen Closed Tab must be disabled before a tab closes')
assert(!enabled('Article', 'Save Article…'), 'Save Article must be disabled without an article')
assert(!enabled('Article', 'Add to List…'), 'Add to List must be disabled without an active tab')
assert(menuItemIfPresent('File', 'Close Window') === null, 'Tabbed workspace must not expose a competing Close Window command')
assert(enabled('Edit', 'Search Wikipedia'), 'Search Wikipedia must be enabled')
assert(!enabled('Edit', 'Find in Page'), 'Find in Page must be disabled without an article')
assert(enabled('View', 'Toggle Inspector'), 'Toggle Inspector must be enabled')
assertDocumentReaderCommandsDisabled('with an empty workspace')

menuItem('Tabs', 'New Tab').click()
waitUntil(() => enabled('File', 'Close'), 'Close did not enable after New Tab')
assert(commandCharacter('File', 'Close') === 'W', 'Enabled Close did not publish Command-W')
assert(!enabled('Article', 'Add to List…'), 'Add to List must stay disabled for a placeholder tab')
assert(enabled('Tabs', 'Next Tab'), 'Next Tab did not enable for an open tab')
assert(enabled('Tabs', 'Previous Tab'), 'Previous Tab did not enable for an open tab')
assertDocumentReaderCommandsDisabled('with a tab but no article')
observations.states.push(windowSnapshot('tab-open'))

menuItem('File', 'Close').click()
waitUntil(() => enabled('Tabs', 'Reopen Closed Tab'), 'Reopen Closed Tab did not enable after Close Tab')
assert(commandCharacter('Tabs', 'Reopen Closed Tab') === 'T', 'Enabled Reopen Closed Tab did not publish Command-Shift-T')
assert(enabled('File', 'Close'), 'Close must return to native window-close behavior after the final tab closes')
observations.states.push(windowSnapshot('tab-closed'))

menuItem('Tabs', 'Reopen Closed Tab').click()
waitUntil(() => enabled('File', 'Close'), 'Close did not re-enable after Reopen Closed Tab')
observations.states.push(windowSnapshot('tab-reopened'))

menuItem('View', 'Enter Full Screen').click()
waitUntil(() => fullScreenValue(), 'Window did not enter native full screen')
observations.states.push(windowSnapshot('full-screen'))

menuItem('View', 'Exit Full Screen').click()
waitUntil(() => !fullScreenValue(), 'Window did not leave native full screen')
observations.states.push(windowSnapshot('restored-from-full-screen'))

Application('Finder').activate()
waitUntil(() => !Boolean(currentProcess().frontmost()), 'MacWiki did not enter an inactive application state')
observations.states.push(windowSnapshot('inactive'))

currentProcess().frontmost = true
waitUntil(() => Boolean(currentProcess().frontmost()), 'MacWiki did not reactivate')
observations.states.push(windowSnapshot('reactivated'))

JSON.stringify(observations, null, 2)
JXA

{
  printf '# Menu and Window-State QA\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Exact candidate PID: `%s`\n' "$QA_APP_PID"
  printf -- '- Menu assertions: native app/File/Edit/View/Article/Tabs/Window actions, shortcuts, and context-sensitive enabled states\n'
  printf -- '- Functional command cycle: New Tab → Close Tab → Reopen Closed Tab\n'
  printf -- '- Window states: ordinary → native full screen → restored → inactive → reactivated\n'
  printf -- '- AX snapshot: `%s`\n' "$SNAPSHOT_PATH"
  printf -- '- Production preferences/data touched: **No** — launch and persistence were isolated.\n'
} >"$REPORT_PATH"

echo "Menu/window-state QA passed: $REPORT_PATH"
