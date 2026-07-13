#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/organization-accessibility-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/organization-accessibility}"
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
SNAPSHOT_PATH="$OUTPUT_DIR/organization-accessibility.json"
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

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function waitUntil(predicate, message, timeoutMilliseconds = 12000) {
  const stop = Date.now() + timeoutMilliseconds
  while (Date.now() < stop) {
    try {
      const value = predicate()
      if (value) return value
    } catch (_) {}
    delay(0.1)
  }
  throw new Error(message)
}

function currentProcess() {
  const matches = systemEvents.processes.whose({ unixId: pid })()
  assert(matches.length === 1, `PID ${pid} is not uniquely reachable`)
  return matches[0]
}

function allElements() {
  const elements = []
  for (const window of currentProcess().windows()) {
    elements.push(window)
    try { elements.push(...window.entireContents().slice(0, 2200)) } catch (_) {}
  }
  return elements
}

function nameOf(element) {
  try { return String(element.name() || '') } catch (_) { return '' }
}

function valueOf(element) {
  try { return String(element.value() || '') } catch (_) { return '' }
}

function elementsNamed(name) {
  return allElements().filter(element => nameOf(element) === name)
}

function waitForNamed(name) {
  return waitUntil(
    () => elementsNamed(name)[0] || null,
    `Accessibility element did not appear: ${name}`
  )
}

function press(element) {
  try {
    const actions = element.actions.whose({ name: 'AXPress' })()
    if (actions.length > 0) {
      actions[0].perform()
      return
    }
  } catch (_) {}
  element.click()
}

function menuItem(menuName, itemName) {
  return waitUntil(() => {
    const menuBars = currentProcess().menuBars()
    if (menuBars.length === 0) return null
    const menuBarItems = menuBars[0].menuBarItems.whose({ name: menuName })()
    if (menuBarItems.length !== 1) return null
    const menus = menuBarItems[0].menus()
    if (menus.length === 0) return null
    const items = menus[0].menuItems.whose({ name: itemName })()
    return items[0] || null
  }, `Menu item did not appear: ${menuName} → ${itemName}`)
}

function cancelPresentedSheet(title) {
  const cancel = waitUntil(
    () => elementsNamed('Cancel').find(element => {
      try { return Boolean(element.enabled()) } catch (_) { return true }
    }) || null,
    `Cancel action did not appear for ${title}`
  )
  press(cancel)
  waitUntil(() => elementsNamed(title).length === 0, `${title} did not dismiss`)
}

waitUntil(
  () => currentProcess().windows().length > 0 && currentProcess().menuBars().length > 0,
  'MacWiki did not expose its initial native window and menu bar'
)
currentProcess().frontmost = true

const observations = {
  pid,
  sidebarActions: {},
  listIcon: {},
  folderIcon: {},
  labelColor: {}
}

for (const name of ['New List or Folder', 'New Label', 'New Tag']) {
  const element = waitForNamed(name)
  observations.sidebarActions[name] = {
    role: (() => { try { return String(element.role()) } catch (_) { return '' } })(),
    enabled: (() => { try { return Boolean(element.enabled()) } catch (_) { return true } })()
  }
}

press(menuItem('File', 'New Reading List'))
const listIcon = waitForNamed('Choose list icon')
observations.listIcon = { name: nameOf(listIcon), value: valueOf(listIcon) }
assert(observations.listIcon.value === 'bookmark.fill', `List icon value was ${observations.listIcon.value}`)
cancelPresentedSheet('Choose list icon')

press(menuItem('File', 'New Folder'))
const folderIcon = waitForNamed('Choose folder icon')
observations.folderIcon = { name: nameOf(folderIcon), value: valueOf(folderIcon) }
assert(observations.folderIcon.value === 'folder.fill', `Folder icon value was ${observations.folderIcon.value}`)
cancelPresentedSheet('Choose folder icon')

press(waitForNamed('New Label'))
const labelColor = waitForNamed('Choose label color')
observations.labelColor = { name: nameOf(labelColor), value: valueOf(labelColor) }
assert(observations.labelColor.value.length > 0, 'Label color chooser exposed no selected color value')
cancelPresentedSheet('Choose label color')

JSON.stringify(observations, null, 2)
JXA

{
  printf '# Organization Accessibility QA\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Exact candidate PID: `%s`\n' "$QA_APP_PID"
  printf -- '- Sidebar actions: New List or Folder, New Label, and New Tag expose explicit accessibility names.\n'
  printf -- '- Creation sheets: list icon, folder icon, and label color choosers expose names plus current values.\n'
  printf -- '- Mutation policy: every sheet was cancelled; no list, folder, label, or tag was created.\n'
  printf -- '- AX snapshot: `%s`\n' "$SNAPSHOT_PATH"
  printf -- '- Production preferences/data touched: **No** — launch, defaults, persistence, and caches were isolated.\n'
} >"$REPORT_PATH"

echo "Organization accessibility QA passed: $REPORT_PATH"
