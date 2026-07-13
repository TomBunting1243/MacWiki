#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/context-menu-accessibility-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/context-menu-accessibility}"
STORE_PATH="$QA_HOME/Library/Application Support/default.store"
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"
BUILD_INFO_PLIST="$APP_BUNDLE_PATH/Contents/Resources/BuildInfo.plist"
STAMP="$(date +%Y%m%d_%H%M%S)-$RANDOM"
FOLDER_NAME="QA Context Folder $STAMP"
LIST_NAME="QA Context List $STAMP"

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
SNAPSHOT_PATH="$OUTPUT_DIR/context-menu-ax.json"
REPORT_PATH="$OUTPUT_DIR/report.md"
APP_LOG="$OUTPUT_DIR/app.log"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_isolated_path "$STORE_PATH" "$QA_HOME"
qa_assert_no_conflicting_processes
qa_launch_candidate "$APP_LOG"

APP_PID="$QA_APP_PID" FOLDER_NAME="$FOLDER_NAME" LIST_NAME="$LIST_NAME" \
  qa_run_command_with_timeout 40 osascript -l JavaScript >/dev/null <<'JXA'
ObjC.import('stdlib')

const pid = Number(ObjC.unwrap($.getenv('APP_PID')))
const folderName = String(ObjC.unwrap($.getenv('FOLDER_NAME')))
const listName = String(ObjC.unwrap($.getenv('LIST_NAME')))
const systemEvents = Application('System Events')
const deadline = Date.now() + 20000
let process = null

function descendants(element, maximumDepth, depth = 0) {
  if (depth >= maximumDepth) return []
  let children = []
  try { children = element.uiElements() } catch (_) {}
  return children.flatMap(child => [child, ...descendants(child, maximumDepth, depth + 1)])
}

function firstTextField(container) {
  return [container, ...descendants(container, 7)].find(element => {
    try { return element.role() === 'AXTextField' } catch (_) { return false }
  }) || null
}

function waitForSheet() {
  const stop = Date.now() + 8000
  while (Date.now() < stop) {
    for (const window of process.windows()) {
      const sheets = window.sheets()
      if (sheets.length > 0) return sheets[0]
    }
    delay(0.05)
  }
  throw new Error('Creation sheet did not appear')
}

function create(menuTitle, name) {
  process.menuBars[0].menuBarItems.byName('File').menus[0].menuItems.byName(menuTitle).click()
  const sheet = waitForSheet()
  const field = firstTextField(sheet)
  if (!field) throw new Error(`${menuTitle} sheet did not expose a text field`)
  field.value = name
  systemEvents.keyCode(36)
  delay(0.25)
}

while (Date.now() < deadline) {
  const matches = systemEvents.processes.whose({ unixId: pid })()
  if (matches.length === 1 && matches[0].menuBars().length > 0 && matches[0].windows().length > 0) {
    process = matches[0]
    break
  }
  delay(0.2)
}
if (!process) throw new Error(`PID ${pid} did not expose a usable app surface`)
process.frontmost = true
create('New Folder', folderName)
create('New Reading List', listName)
'created isolated folder and list'
JXA

uuid_from_hex() {
  local hex="$1"
  [[ "$hex" =~ ^[0-9a-f]{32}$ ]] || return 1
  printf '%s-%s-%s-%s-%s\n' \
    "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}" \
    | tr '[:lower:]' '[:upper:]'
}

FOLDER_HEX=""
LIST_HEX=""
for _ in $(seq 1 80); do
  if [[ -f "$STORE_PATH" ]]; then
    FOLDER_HEX="$(sqlite3 "$STORE_PATH" "SELECT lower(hex(ZID)) FROM ZAREA WHERE ZNAME='$FOLDER_NAME' LIMIT 1;" 2>/dev/null || true)"
    LIST_HEX="$(sqlite3 "$STORE_PATH" "SELECT lower(hex(ZID)) FROM ZREADINGLIST WHERE ZNAME='$LIST_NAME' LIMIT 1;" 2>/dev/null || true)"
    if [[ "$FOLDER_HEX" =~ ^[0-9a-f]{32}$ && "$LIST_HEX" =~ ^[0-9a-f]{32}$ ]]; then
      break
    fi
  fi
  sleep 0.1
done

FOLDER_ID="$(uuid_from_hex "$FOLDER_HEX")" || { echo "Could not resolve isolated folder ID" >&2; exit 1; }
LIST_ID="$(uuid_from_hex "$LIST_HEX")" || { echo "Could not resolve isolated list ID" >&2; exit 1; }
FOLDER_ROW_ID="sidebar-row-area-$FOLDER_ID"
LIST_ROW_ID="sidebar-row-list-$LIST_ID"

APP_PID="$QA_APP_PID" FOLDER_ROW_ID="$FOLDER_ROW_ID" LIST_ROW_ID="$LIST_ROW_ID" \
  qa_run_command_with_timeout 40 osascript -l JavaScript >"$SNAPSHOT_PATH" <<'JXA'
ObjC.import('stdlib')

const pid = Number(ObjC.unwrap($.getenv('APP_PID')))
const folderRowID = String(ObjC.unwrap($.getenv('FOLDER_ROW_ID')))
const listRowID = String(ObjC.unwrap($.getenv('LIST_ROW_ID')))
const systemEvents = Application('System Events')

function safe(getter, fallback = null) {
  try {
    const value = getter()
    return value === undefined ? fallback : value
  } catch (_) {
    return fallback
  }
}

function descendants(element, maximumDepth, depth = 0) {
  if (depth >= maximumDepth) return []
  const children = safe(() => element.uiElements(), [])
  return children.flatMap(child => [child, ...descendants(child, maximumDepth, depth + 1)])
}

function identifier(element) {
  return String(safe(() => element.attributes.byName('AXIdentifier').value(), ''))
}

function role(element) {
  return String(safe(() => element.role(), ''))
}

function title(element) {
  return String(safe(() => element.title(), safe(() => element.name(), safe(() => element.description(), ''))))
}

function actionNames(element) {
  return safe(() => element.actions().map(action => String(action.name())), [])
}

const matches = systemEvents.processes.whose({ unixId: pid })()
if (matches.length !== 1) throw new Error(`Expected one exact process for PID ${pid}`)
const process = matches[0]
process.frontmost = true

function row(identifierValue) {
  const stop = Date.now() + 10000
  while (Date.now() < stop) {
    for (const window of process.windows()) {
      const candidate = [window, ...descendants(window, 10)].find(element => identifier(element) === identifierValue)
      if (candidate) return candidate
    }
    delay(0.1)
  }
  throw new Error(`Sidebar row was not visible: ${identifierValue}`)
}

function visibleMenuTitles() {
  const titles = []
  for (const window of process.windows()) {
    for (const element of [window, ...descendants(window, 12)]) {
      if (role(element) === 'AXMenuItem') {
        const value = title(element)
        if (value) titles.push(value)
      }
    }
  }
  for (const menuBar of process.menuBars()) {
    for (const element of descendants(menuBar, 8)) {
      if (role(element) === 'AXMenuItem') {
        const value = title(element)
        if (value) titles.push(value)
      }
    }
  }
  return [...new Set(titles)]
}

function inspectContextMenu(identifierValue, requiredTitles) {
  const targetRow = row(identifierValue)
  const target = [targetRow, ...descendants(targetRow, 5)].find(element => actionNames(element).includes('AXShowMenu'))
  if (!target) throw new Error(`${identifierValue} did not expose AXShowMenu`)
  target.actions.byName('AXShowMenu').perform()

  const stop = Date.now() + 5000
  let observed = []
  while (Date.now() < stop) {
    observed = visibleMenuTitles()
    if (requiredTitles.every(value => observed.includes(value))) break
    delay(0.05)
  }
  for (const required of requiredTitles) {
    if (!observed.includes(required)) {
      throw new Error(`${identifierValue} menu omitted ${required}; observed=${observed.join('|')}`)
    }
  }
  systemEvents.keyCode(53)
  delay(0.1)
  return observed.filter(value => requiredTitles.includes(value) || value === 'Move to Folder')
}

const result = {
  pid,
  folderRowID,
  listRowID,
  folderMenu: inspectContextMenu(folderRowID, ['Rename', 'Delete Folder']),
  listMenu: inspectContextMenu(listRowID, ['Rename', 'Change Icon', 'Move to Folder', 'Delete'])
}

JSON.stringify(result, null, 2)
JXA

{
  printf '# Sidebar Context-Menu Accessibility QA\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Exact candidate PID: `%s`\n' "$QA_APP_PID"
  printf -- '- Folder menu assertions: Rename, Delete Folder\n'
  printf -- '- Reading-list menu assertions: Rename, Change Icon, Move to Folder, Delete\n'
  printf -- '- AX snapshot: `%s`\n' "$SNAPSHOT_PATH"
  printf -- '- Production preferences/data touched: **No** — all entities and persistence were isolated.\n'
} >"$REPORT_PATH"

echo "Context-menu accessibility QA passed: $REPORT_PATH"
