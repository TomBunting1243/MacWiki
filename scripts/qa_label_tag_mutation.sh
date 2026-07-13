#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/label-tag-mutation-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/label-tag-mutation}"
STORE_PATH="$QA_HOME/Library/Application Support/default.store"
LABEL_NAME="${LABEL_NAME:-QA Label Mutation}"
RENAMED_LABEL_NAME="${RENAMED_LABEL_NAME:-QA Label Renamed}"
TAG_NAME="${TAG_NAME:-QA Tag Mutation}"
RENAMED_TAG_NAME="${RENAMED_TAG_NAME:-QA Tag Renamed}"
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
AX_RESULT="$OUTPUT_DIR/label-tag-mutation-ax.json"
DRIVER_LOG="$OUTPUT_DIR/driver-errors.log"
REPORT_PATH="$OUTPUT_DIR/report.md"

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

APP_PID="$QA_APP_PID" LABEL_NAME="$LABEL_NAME" RENAMED_LABEL_NAME="$RENAMED_LABEL_NAME" \
TAG_NAME="$TAG_NAME" RENAMED_TAG_NAME="$RENAMED_TAG_NAME" \
  qa_run_command_with_timeout 300 osascript -l JavaScript >"$AX_RESULT" 2>"$DRIVER_LOG" <<'JXA' || qa_status=$?
ObjC.import('stdlib')

const pid = Number(ObjC.unwrap($.getenv('APP_PID')))
const labelName = String(ObjC.unwrap($.getenv('LABEL_NAME')))
const renamedLabelName = String(ObjC.unwrap($.getenv('RENAMED_LABEL_NAME')))
const tagName = String(ObjC.unwrap($.getenv('TAG_NAME')))
const renamedTagName = String(ObjC.unwrap($.getenv('RENAMED_TAG_NAME')))
const systemEvents = Application('System Events')

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function trace(message) {
  console.log(`${new Date().toISOString()} ${message}`)
}

function safe(getter, fallback = null) {
  try {
    const value = getter()
    return value === undefined ? fallback : value
  } catch (_) {
    return fallback
  }
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

function descendants(element, maximumDepth, depth = 0) {
  if (depth >= maximumDepth) return []
  const children = safe(() => element.uiElements(), [])
  return children.flatMap(child => [child, ...descendants(child, maximumDepth, depth + 1)])
}

function allElements() {
  const elements = []
  const process = currentProcess()
  for (const window of process.windows()) {
    elements.push(window, ...safe(() => window.entireContents(), []))
  }
  for (const menuBar of process.menuBars()) {
    elements.push(menuBar, ...safe(() => menuBar.entireContents(), []))
  }
  return elements
}

function stringValues(element) {
  const values = []
  for (const getter of [
    () => element.name(),
    () => element.title(),
    () => element.description(),
    () => element.value()
  ]) {
    const value = safe(getter, '')
    if (value !== null && String(value).length > 0) values.push(String(value))
  }
  return values
}

function actionNames(element) {
  return safe(() => element.actions().map(action => String(action.name())), [])
}

function elementsNamed(name) {
  return allElements().filter(element => stringValues(element).some(value => value === name || value.endsWith(`, ${name}`)))
}

function waitForNamed(name) {
  return waitUntil(() => elementsNamed(name)[0] || null, `Element did not appear: ${name}`)
}

function elementsContaining(text) {
  return allElements().filter(element => stringValues(element).some(value => value.includes(text)))
}

function waitForText(text) {
  return waitUntil(() => elementsContaining(text)[0] || null, `Text did not appear: ${text}`)
}

function press(element) {
  if (actionNames(element).includes('AXPress')) {
    element.actions.byName('AXPress').perform()
    return
  }
  element.click()
}

function waitForSheet() {
  return waitUntil(() => {
    for (const window of currentProcess().windows()) {
      const sheets = safe(() => window.sheets(), [])
      if (sheets.length > 0) return sheets[0]
    }
    return null
  }, 'Creation/edit sheet did not appear')
}

function firstTextField(container) {
  return [container, ...descendants(container, 8)].find(element => safe(() => element.role(), '') === 'AXTextField') || null
}

function submitSheet(actionName, value) {
  const sheet = waitForSheet()
  const field = firstTextField(sheet)
  assert(field, `${actionName} sheet did not expose a text field`)
  field.click()
  systemEvents.keystroke('a', { using: 'command down' })
  systemEvents.keystroke(value)
  const action = waitUntil(
    () => elementsNamed(actionName).find(element => safe(() => Boolean(element.enabled()), false)) || null,
    `${actionName} did not enable after typing a valid name`
  )
  press(action)
  waitUntil(
    () => currentProcess().windows().every(window => safe(() => window.sheets(), []).length === 0),
    `${actionName} sheet did not dismiss after submission`
  )
}

function showContextMenuForName(name) {
  const target = waitUntil(() => {
    const matches = allElements().filter(element => stringValues(element).some(value => value.includes(name)))
    return matches.find(element => actionNames(element).includes('AXShowMenu')) || null
  }, `No context-menu target exposed ${name}`)
  target.actions.byName('AXShowMenu').perform()
}

function createRenameDelete(createAction, originalName, renamedName) {
  trace(`begin ${originalName}`)
  press(waitForNamed(createAction))
  submitSheet('Create', originalName)
  waitForText(originalName)
  trace(`created ${originalName}`)

  showContextMenuForName(originalName)
  trace(`opened initial menu for ${originalName}`)
  press(waitForNamed('Rename'))
  submitSheet('Save', renamedName)
  waitForText(renamedName)
  waitUntil(() => elementsContaining(originalName).length === 0, `${originalName} remained after rename`)
  trace(`renamed ${originalName} to ${renamedName}`)

  showContextMenuForName(renamedName)
  trace(`opened renamed menu for ${renamedName}`)
  press(waitForNamed('Delete'))
  waitUntil(() => elementsContaining(renamedName).length === 0, `${renamedName} remained after delete`)
  trace(`deleted ${renamedName}`)
}

waitUntil(() => currentProcess().windows().length > 0, 'MacWiki did not expose its main window')
currentProcess().frontmost = true

createRenameDelete('New Label', labelName, renamedLabelName)
createRenameDelete('New Tag', tagName, renamedTagName)

JSON.stringify({
  pid,
  label: { created: labelName, renamed: renamedLabelName, deleted: true },
  tag: { created: tagName, renamed: renamedTagName, deleted: true }
}, null, 2)
JXA

if [[ "${qa_status:-0}" != "0" ]]; then
  if [[ -f "$STORE_PATH" ]]; then
    sqlite3 -header -tabs "$STORE_PATH" \
      "SELECT 'label' AS kind, ZNAME AS name FROM ZLABEL UNION ALL SELECT 'tag', ZNAME FROM ZTAG;" \
      >"$OUTPUT_DIR/failed-store-collections.tsv" 2>/dev/null || true
  fi
  APP_PID="$QA_APP_PID" osascript -l JavaScript >"$OUTPUT_DIR/failed-sidebar-elements.tsv" <<'JXA_DIAGNOSTIC' || true
ObjC.import('stdlib')
const pid = Number(ObjC.unwrap($.getenv('APP_PID')))
const se = Application('System Events')
const matches = se.processes.whose({ unixId: pid })()
if (matches.length !== 1) throw new Error('Exact process missing')
function safe(getter, fallback = '') { try { return getter() } catch (_) { return fallback } }
function descendants(element, depth = 0) {
  if (depth >= 14) return []
  const children = safe(() => element.uiElements(), [])
  return children.flatMap(child => [child, ...descendants(child, depth + 1)])
}
const rows = []
for (const window of matches[0].windows()) {
  for (const element of [window, ...descendants(window)]) {
    const identifier = String(safe(() => element.attributes.byName('AXIdentifier').value()))
    const name = String(safe(() => element.name()))
    const role = String(safe(() => element.role()))
    if (identifier.includes('sidebar-row-label') || identifier.includes('sidebar-row-tag') || name.includes('QA ')) {
      rows.push([role, identifier, name].join('\t'))
    }
  }
}
rows.join('\n')
JXA_DIAGNOSTIC
  echo "Label/tag mutation accessibility driver failed; diagnostic store inventory preserved." >&2
  exit "${qa_status:-1}"
fi

for _ in $(seq 1 60); do
  if [[ -f "$STORE_PATH" ]]; then
    label_count="$(sqlite3 "$STORE_PATH" "SELECT count(*) FROM ZLABEL WHERE ZNAME IN ('$LABEL_NAME', '$RENAMED_LABEL_NAME');" 2>/dev/null || true)"
    tag_count="$(sqlite3 "$STORE_PATH" "SELECT count(*) FROM ZTAG WHERE ZNAME IN ('$TAG_NAME', '$RENAMED_TAG_NAME');" 2>/dev/null || true)"
    [[ "$label_count" == "0" && "$tag_count" == "0" ]] && break
  fi
  sleep 0.1
done
[[ "${label_count:-}" == "0" && "${tag_count:-}" == "0" ]] || {
  echo "Deleted label or tag remained in isolated SwiftData store" >&2
  exit 1
}

if rg -ni 'fatal error|precondition failed|assertion failed' "$APP_LOG" >"$OUTPUT_DIR/runtime-failures.txt"; then
  echo "Runtime diagnostics contained a fatal, assertion, or precondition failure." >&2
  exit 1
fi
: >"$OUTPUT_DIR/runtime-failures.txt"

{
  printf '# Label and Tag Mutation QA\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Exact candidate PID: `%s`\n' "$QA_APP_PID"
  printf -- '- Label assertions: create, populated sidebar row, native Rename/Save, native Delete, persisted removal\n'
  printf -- '- Tag assertions: create, populated sidebar row, native Rename/Save, native Delete, persisted removal\n'
  printf -- '- AX evidence: `%s`\n' "$AX_RESULT"
  printf -- '- Runtime failures: no fatal, assertion, or precondition messages\n'
  printf -- '- Production preferences/data touched: **No** — defaults, persistence, caches, and all mutations were isolated and removed.\n'
} >"$REPORT_PATH"

echo "Label/tag mutation QA passed: $REPORT_PATH"
