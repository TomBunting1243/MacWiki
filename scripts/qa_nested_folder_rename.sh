#!/usr/bin/env bash

set -euo pipefail

APP_NAME="${APP_NAME:-MacWiki}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/qa_process_safety.sh"
APP_BIN_DEFAULT="$REPO_ROOT/.build/arm64-apple-macosx/debug/MacWiki"
APP_BIN_FALLBACK="$REPO_ROOT/.build/debug/MacWiki"
APP_BIN="${APP_BIN:-$APP_BIN_DEFAULT}"

if [[ ! -x "$APP_BIN" && -x "$APP_BIN_FALLBACK" ]]; then
  APP_BIN="$APP_BIN_FALLBACK"
fi

timestamp="$(date +%Y%m%d_%H%M%S)"
suffix="$(printf '%04d' "$((RANDOM % 10000))")"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/nested-folder-rename-${timestamp}-${suffix}}"
STORE_PATH="${STORE_PATH:-$QA_HOME/Library/Application Support/default.store}"
PARENT_NAME="QA_PARENT_${timestamp}_${suffix}"
CHILD_NAME="QA_CHILD_${timestamp}_${suffix}"
RENAMED_CHILD_NAME="QA_CHILD_RENAMED_${timestamp}_${suffix}"

uuid_from_hex() {
  local hex="$1"
  if [[ ! "$hex" =~ ^[0-9a-f]{32}$ ]]; then
    return 1
  fi
  printf '%s-%s-%s-%s-%s\n' \
    "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}" | tr '[:lower:]' '[:upper:]'
}

wait_for_area_hex_id() {
  local area_name="$1"
  local hex=""
  for _ in $(seq 1 100); do
    if [[ -f "$STORE_PATH" ]]; then
      hex="$(sqlite3 "$STORE_PATH" "SELECT lower(hex(ZID)) FROM ZAREA WHERE ZNAME='${area_name}' ORDER BY Z_PK DESC LIMIT 1;" 2>/dev/null || true)"
      if [[ "$hex" =~ ^[0-9a-f]{32}$ ]]; then
        printf '%s\n' "$hex"
        return 0
      fi
    fi
    sleep 0.1
  done
  echo "ERROR: Timed out resolving SwiftData ID for $area_name" >&2
  return 1
}

echo "Starting nested-folder rename QA harness..."
echo "Parent folder:  ${PARENT_NAME}"
echo "Child folder:   ${CHILD_NAME}"
echo "Renamed child:  ${RENAMED_CHILD_NAME}"

if [[ ! -x "$APP_BIN" ]]; then
  echo "ERROR: App binary not found at $APP_BIN"
  exit 1
fi

qa_prepare_isolated_home
qa_assert_isolated_path "$STORE_PATH" "$QA_HOME"
cleanup() {
  qa_stop_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

activate_app() {
  osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null
using terms from application "System Events"
on contentWindowIndex(appName)
    tell application "System Events"
        if not (exists process appName) then return 0
        tell process appName
            set windowCount to count of windows
            repeat with idx from 1 to windowCount
                try
                    if exists outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of splitter group 1 of group 1 of window idx then return idx as integer
                end try
            end repeat
        end tell
    end tell
    return 0
end contentWindowIndex

on run argv
    set appName to item 1 of argv
    set targetIndex to my contentWindowIndex(appName)
    if targetIndex is 0 then error "No content window"

    tell application "System Events"
        tell process appName
            set frontmost to true
            try
                perform action "AXRaise" of window targetIndex
            end try
        end tell
    end tell
end run
end using terms from
APPLESCRIPT
}

echo "Launching isolated $APP_NAME from $APP_BIN..."
qa_launch_exact_bundle "/tmp/macwiki_qa_nested_folder_rename.log"

echo "Waiting for $APP_NAME process and content window..."
for _ in $(seq 1 60); do
  if osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1
using terms from application "System Events"
on contentWindowIndex(appName)
    tell application "System Events"
        if not (exists process appName) then return 0
        tell process appName
            set windowCount to count of windows
            repeat with idx from 1 to windowCount
                try
                    if exists outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of splitter group 1 of group 1 of window idx then return idx as integer
                end try
            end repeat
        end tell
    end tell
    return 0
end contentWindowIndex

on run argv
    set appName to item 1 of argv
    if my contentWindowIndex(appName) is 0 then error "missing content window"
end run
end using terms from
APPLESCRIPT
  then
    break
  fi
  sleep 0.2
done

echo "Creating parent and child folders via accessibility..."
osascript - "$APP_NAME" "$PARENT_NAME" "$CHILD_NAME" <<'APPLESCRIPT'
using terms from application "System Events"
on contentWindowIndex(appName)
    tell application "System Events"
        if not (exists process appName) then return 0
        tell process appName
            set windowCount to count of windows
            repeat with idx from 1 to windowCount
                try
                    if exists outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of splitter group 1 of group 1 of window idx then return idx as integer
                end try
            end repeat
        end tell
    end tell
    return 0
end contentWindowIndex

on waitForContentWindowIndex(appName, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set idx to my contentWindowIndex(appName)
        if idx is not 0 then return idx
        delay 0.1
    end repeat
    error "Timed out waiting for content window"
end waitForContentWindowIndex

on firstTextFieldIn(containerElement)
    set allElements to entire contents of containerElement
    repeat with e in allElements
        try
            if class of e is text field then return e
        end try
    end repeat
    return missing value
end firstTextFieldIn

on elementMatchesLabel(elementValue, targetLabel)
    try
        if (description of elementValue as text) is targetLabel then return true
    end try
    try
        if (value of elementValue as text) is targetLabel then return true
    end try
    try
        if (name of elementValue as text) is targetLabel then return true
    end try
    try
        if (title of elementValue as text) is targetLabel then return true
    end try
    return false
end elementMatchesLabel

on rowContainsLabel(rowElement, targetLabel)
    if my elementMatchesLabel(rowElement, targetLabel) then return true
    set rowElements to entire contents of rowElement
    repeat with e in rowElements
        if my elementMatchesLabel(e, targetLabel) then return true
    end repeat
    return false
end rowContainsLabel

on findRowByLabel(appName, windowIndex, targetLabel)
    tell application "System Events"
        tell process appName
            set outlineElement to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of splitter group 1 of group 1 of window windowIndex
            repeat with r in rows of outlineElement
                try
                    if my rowContainsLabel(r, targetLabel) then return r
                end try
            end repeat
        end tell
    end tell
    return missing value
end findRowByLabel

on selectRecentsRow(appName, windowIndex, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set recentsRow to my findRowByLabel(appName, windowIndex, "Recents")
        if recentsRow is not missing value then
            tell application "System Events"
                try
                    perform action "AXPress" of recentsRow
                    return true
                end try
                try
                    click recentsRow
                    return true
                end try
            end tell
        end if
        delay 0.05
    end repeat
    return false
end selectRecentsRow

on createFolder(appName, windowIndex, folderName)
    tell application "System Events"
        tell process appName
            click menu item "New Folder" of menu "File" of menu bar item "File" of menu bar 1
        end tell
    end tell

    set deadline to (current date) + 8
    repeat while (current date) < deadline
        tell application "System Events"
            tell process appName
                if exists sheet 1 of window windowIndex then
                    set createSheet to sheet 1 of window windowIndex
                    set nameField to my firstTextFieldIn(createSheet)
                    if nameField is missing value then error "New Folder sheet has no text field"
                    set value of nameField to folderName
                    tell application "System Events" to key code 36
                    return true
                end if
            end tell
        end tell
        delay 0.05
    end repeat

    error "New Folder sheet did not appear"
end createFolder

on run argv
    set appName to item 1 of argv
    set parentName to item 2 of argv
    set childName to item 3 of argv

    set windowIndex to my waitForContentWindowIndex(appName, 20)

    tell application "System Events"
        tell process appName
            set frontmost to true
            try
                perform action "AXRaise" of window windowIndex
            end try
        end tell
    end tell

    my createFolder(appName, windowIndex, parentName)
    my selectRecentsRow(appName, windowIndex, 4)
    my createFolder(appName, windowIndex, childName)
end run
end using terms from
APPLESCRIPT

parent_id_hex="$(wait_for_area_hex_id "$PARENT_NAME")"
child_id_hex="$(wait_for_area_hex_id "$CHILD_NAME")"
PARENT_ROW_ID="sidebar-row-area-$(uuid_from_hex "$parent_id_hex")"
CHILD_ROW_ID="sidebar-row-area-$(uuid_from_hex "$child_id_hex")"

echo "Resolving folder row coordinates..."
coords="$(osascript -l JavaScript "$SCRIPT_DIR/lib/qa_area_row_centers.js" pair "$APP_NAME" "$CHILD_ROW_ID" "$PARENT_ROW_ID")"

read -r source_x source_y target_x target_y <<<"$coords"

if [[ -z "${source_x:-}" || -z "${source_y:-}" || -z "${target_x:-}" || -z "${target_y:-}" ]]; then
  echo "ERROR: Failed to resolve drag coordinates."
  echo "Raw coordinate payload: '$coords'"
  exit 1
fi

echo "Dragging child folder into parent folder..."
activate_app
sleep 0.15
swift "$SCRIPT_DIR/cg_drag.swift" \
  --start-x "$source_x" \
  --start-y "$source_y" \
  --end-x "$target_x" \
  --end-y "$target_y" \
  --duration 0.42

echo "Resolving nested child folder coordinate for rename..."
rename_coords="$(osascript -l JavaScript "$SCRIPT_DIR/lib/qa_area_row_centers.js" nested "$APP_NAME" "$PARENT_ROW_ID" "$CHILD_ROW_ID")"

read -r rename_x rename_y <<<"$rename_coords"

if [[ -z "${rename_x:-}" || -z "${rename_y:-}" ]]; then
  echo "ERROR: Failed to resolve rename coordinates."
  echo "Raw rename coordinate payload: '$rename_coords'"
  exit 1
fi

echo "Renaming nested child folder via context menu..."
osascript -l JavaScript "$SCRIPT_DIR/lib/qa_rename_area.js" "$APP_NAME" "$CHILD_ROW_ID" "$RENAMED_CHILD_NAME"

sleep 0.8

echo "Verifying nested parent relation in SwiftData store..."
if [[ ! -f "$STORE_PATH" ]]; then
  echo "ERROR: SwiftData store not found at $STORE_PATH"
  exit 1
fi

parent_id_hex="$(sqlite3 "$STORE_PATH" "SELECT lower(hex(ZID)) FROM ZAREA WHERE ZNAME='${PARENT_NAME}' ORDER BY Z_PK DESC LIMIT 1;")"
renamed_parent_hex="$(sqlite3 "$STORE_PATH" "SELECT lower(hex(ZPARENTID)) FROM ZAREA WHERE ZNAME='${RENAMED_CHILD_NAME}' ORDER BY Z_PK DESC LIMIT 1;")"
old_child_count="$(sqlite3 "$STORE_PATH" "SELECT count(*) FROM ZAREA WHERE ZNAME='${CHILD_NAME}';")"

if [[ -z "$parent_id_hex" ]]; then
  echo "ERROR: Parent folder row not found in ZAREA"
  exit 1
fi

if [[ -z "$renamed_parent_hex" ]]; then
  echo "ERROR: Renamed child folder row not found in ZAREA"
  exit 1
fi

if [[ "$parent_id_hex" != "$renamed_parent_hex" ]]; then
  echo "ERROR: Nested parent relationship mismatch"
  echo "Expected parent ZID: $parent_id_hex"
  echo "Renamed child ZPARENTID: $renamed_parent_hex"
  exit 1
fi

if [[ "$old_child_count" != "0" ]]; then
  echo "ERROR: Old child name still exists after rename (count=$old_child_count)"
  exit 1
fi

echo "PASS: Nested-folder drag + rename verified."
echo "  Parent:  $PARENT_NAME"
echo "  Child:   $CHILD_NAME"
echo "  Renamed: $RENAMED_CHILD_NAME"
