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

PARENT_ROW_ID="area-row-${PARENT_NAME}"
CHILD_ROW_ID="area-row-${CHILD_NAME}"

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
                    if exists splitter group 1 of group 1 of window idx then return idx
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
qa_launch_exact "/tmp/macwiki_qa_nested_folder_rename.log"

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
                    if exists splitter group 1 of group 1 of window idx then return idx
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
                    if exists splitter group 1 of group 1 of window idx then return idx
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

on rowContainsLabel(rowElement, targetLabel)
    set rowElements to entire contents of rowElement
    repeat with e in rowElements
        try
            if class of e is static text then
                try
                    if (value of e as text) is targetLabel then return true
                end try
                try
                    if (name of e as text) is targetLabel then return true
                end try
            end if
        end try
    end repeat
    return false
end rowContainsLabel

on findRowByLabel(appName, windowIndex, targetLabel)
    tell application "System Events"
        tell process appName
            set outlineElement to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window windowIndex
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

echo "Resolving folder row coordinates..."
coords="$(
osascript - "$APP_NAME" "$CHILD_ROW_ID" "$PARENT_ROW_ID" <<'APPLESCRIPT'
using terms from application "System Events"
on contentWindowIndex(appName)
    tell application "System Events"
        if not (exists process appName) then return 0
        tell process appName
            set windowCount to count of windows
            repeat with idx from 1 to windowCount
                try
                    if exists splitter group 1 of group 1 of window idx then return idx
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

on rowMatchesIdentifier(rowElement, targetIdentifier)
    try
        if value of attribute "AXIdentifier" of rowElement is targetIdentifier then return true
    end try

    set rowElements to entire contents of rowElement
    repeat with e in rowElements
        try
            if value of attribute "AXIdentifier" of e is targetIdentifier then return true
        end try
    end repeat

    return false
end rowMatchesIdentifier

on findRowByIdentifier(appName, targetIdentifier)
    set windowIndex to my waitForContentWindowIndex(appName, 4)
    tell application "System Events"
        tell process appName
            set outlineElement to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window windowIndex
            repeat with r in rows of outlineElement
                try
                    if my rowMatchesIdentifier(r, targetIdentifier) then return r
                end try
            end repeat
        end tell
    end tell
    return missing value
end findRowByIdentifier

on waitForRowByIdentifier(appName, targetIdentifier, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set matchRow to my findRowByIdentifier(appName, targetIdentifier)
        if matchRow is not missing value then return matchRow
        delay 0.1
    end repeat
    error "Timed out waiting for row: " & targetIdentifier
end waitForRowByIdentifier

on elementSupportsAction(elementRef, actionName)
    try
        repeat with actionRef in actions of elementRef
            try
                if (name of actionRef as text) is actionName then return true
            end try
        end repeat
    end try
    return false
end elementSupportsAction

on rowElementForContextMenu(rowElement)
    if my elementSupportsAction(rowElement, "AXShowMenu") then return rowElement
    set rowElements to entire contents of rowElement
    repeat with e in rowElements
        if my elementSupportsAction(e, "AXShowMenu") then return e
    end repeat
    return missing value
end rowElementForContextMenu

on disclosureToggleInRow(rowElement)
    set rowElements to entire contents of rowElement
    repeat with e in rowElements
        try
            if value of attribute "AXRole" of e is "AXDisclosureTriangle" then return e
        end try
    end repeat
    return missing value
end disclosureToggleInRow

on rowExpandedState(rowElement)
    set rawValue to missing value
    try
        set rawValue to value of attribute "AXExpanded" of rowElement
    end try
    if rawValue is missing value then
        set toggleElement to my disclosureToggleInRow(rowElement)
        if toggleElement is not missing value then
            try
                set rawValue to value of attribute "AXValue" of toggleElement
            end try
        end if
    end if

    if rawValue is missing value then return missing value
    if class of rawValue is integer then
        return rawValue is not 0
    end if
    if class of rawValue is real then
        return rawValue is not 0
    end if
    if class of rawValue is text then
        try
            return (rawValue as integer) is not 0
        end try
    end if
    return rawValue
end rowExpandedState

on nudgeRowExpandedState(rowElement, desiredState)
    try
        set value of attribute "AXExpanded" of rowElement to desiredState
        return true
    end try

    set toggleElement to my disclosureToggleInRow(rowElement)
    if toggleElement is missing value then return false

    try
        perform action "AXPress" of toggleElement
        return true
    end try
    try
        click toggleElement
        return true
    end try
    return false
end nudgeRowExpandedState

on ensureRowExpandedState(appName, rowIdentifier, desiredState, timeoutSeconds, failureMessage)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set rowElement to my findRowByIdentifier(appName, rowIdentifier)
        if rowElement is not missing value then
            set expandedState to my rowExpandedState(rowElement)
            if expandedState is desiredState then return true
            if my nudgeRowExpandedState(rowElement, desiredState) then delay 0.12
        end if
        delay 0.08
    end repeat
    error failureMessage
end ensureRowExpandedState

on run argv
    set appName to item 1 of argv
    set sourceID to item 2 of argv
    set targetID to item 3 of argv

    set sourceRow to my waitForRowByIdentifier(appName, sourceID, 20)
    set targetRow to my waitForRowByIdentifier(appName, targetID, 20)

    set sourcePos to position of sourceRow
    set sourceSize to size of sourceRow
    set targetPos to position of targetRow
    set targetSize to size of targetRow

    set sourceCenterX to (item 1 of sourcePos) + ((item 1 of sourceSize) / 2)
    set sourceCenterY to (item 2 of sourcePos) + ((item 2 of sourceSize) / 2)
    set targetCenterX to (item 1 of targetPos) + ((item 1 of targetSize) / 2)
    set targetCenterY to (item 2 of targetPos) + ((item 2 of targetSize) / 2)

    return (sourceCenterX as text) & " " & (sourceCenterY as text) & " " & (targetCenterX as text) & " " & (targetCenterY as text)
end run
end using terms from
APPLESCRIPT
)"

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
  --duration 0.42 \
  --flip-y

echo "Resolving nested child folder coordinate for rename..."
rename_coords="$(
osascript - "$APP_NAME" "$PARENT_NAME" "$CHILD_NAME" <<'APPLESCRIPT'
using terms from application "System Events"
on contentWindowIndex(appName)
    tell application "System Events"
        if not (exists process appName) then return 0
        tell process appName
            set windowCount to count of windows
            repeat with idx from 1 to windowCount
                try
                    if exists splitter group 1 of group 1 of window idx then return idx
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

on rowMatchesIdentifier(rowElement, targetIdentifier)
    try
        if value of attribute "AXIdentifier" of rowElement is targetIdentifier then return true
    end try

    set rowElements to entire contents of rowElement
    repeat with e in rowElements
        try
            if value of attribute "AXIdentifier" of e is targetIdentifier then return true
        end try
    end repeat

    return false
end rowMatchesIdentifier

on findRowByIdentifier(appName, targetIdentifier)
    set windowIndex to my waitForContentWindowIndex(appName, 4)
    tell application "System Events"
        tell process appName
            set outlineElement to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window windowIndex
            repeat with r in rows of outlineElement
                try
                    if my rowMatchesIdentifier(r, targetIdentifier) then return r
                end try
            end repeat
        end tell
    end tell
    return missing value
end findRowByIdentifier

on waitForRowByIdentifier(appName, targetIdentifier, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set matchRow to my findRowByIdentifier(appName, targetIdentifier)
        if matchRow is not missing value then return matchRow
        delay 0.1
    end repeat
    error "Timed out waiting for row: " & targetIdentifier
end waitForRowByIdentifier

on run argv
    set appName to item 1 of argv
    set parentName to item 2 of argv
    set childName to item 3 of argv
    set parentRowID to "area-row-" & parentName
    set childRowID to "area-row-" & childName

    set windowIndex to my waitForContentWindowIndex(appName, 20)
    tell application "System Events"
        tell process appName
            set frontmost to true
            try
                perform action "AXRaise" of window windowIndex
            end try
        end tell
    end tell

    set parentRow to my waitForRowByIdentifier(appName, parentRowID, 14)
    try
        set value of attribute "AXExpanded" of parentRow to true
    end try

    set childRow to my waitForRowByIdentifier(appName, childRowID, 14)
    set childPos to position of childRow
    set childSize to size of childRow
    set childCenterX to (item 1 of childPos) + ((item 1 of childSize) / 2)
    set childCenterY to (item 2 of childPos) + ((item 2 of childSize) / 2)

    return (childCenterX as text) & " " & (childCenterY as text)
end run
end using terms from
APPLESCRIPT
)"

read -r rename_x rename_y <<<"$rename_coords"

if [[ -z "${rename_x:-}" || -z "${rename_y:-}" ]]; then
  echo "ERROR: Failed to resolve rename coordinates."
  echo "Raw rename coordinate payload: '$rename_coords'"
  exit 1
fi

echo "Opening context menu on nested child folder..."
activate_app
sleep 0.15
swift "$SCRIPT_DIR/cg_right_click.swift" \
  --x "$rename_x" \
  --y "$rename_y" \
  --flip-y

echo "Renaming nested child folder via context menu..."
osascript - "$APP_NAME" "$RENAMED_CHILD_NAME" "$CHILD_NAME" <<'APPLESCRIPT'
using terms from application "System Events"
on contentWindowIndex(appName)
    tell application "System Events"
        if not (exists process appName) then return 0
        tell process appName
            set windowCount to count of windows
            repeat with idx from 1 to windowCount
                try
                    if exists splitter group 1 of group 1 of window idx then return idx
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

on rowMatchesIdentifier(rowElement, targetIdentifier)
    try
        if value of attribute "AXIdentifier" of rowElement is targetIdentifier then return true
    end try

    set rowElements to entire contents of rowElement
    repeat with e in rowElements
        try
            if value of attribute "AXIdentifier" of e is targetIdentifier then return true
        end try
    end repeat
    return false
end rowMatchesIdentifier

on findRowByIdentifier(appName, targetIdentifier)
    set windowIndex to my waitForContentWindowIndex(appName, 4)
    tell application "System Events"
        tell process appName
            set outlineElement to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window windowIndex
            repeat with r in rows of outlineElement
                try
                    if my rowMatchesIdentifier(r, targetIdentifier) then return r
                end try
            end repeat
        end tell
    end tell
    return missing value
end findRowByIdentifier

on waitForRowByIdentifier(appName, targetIdentifier, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set matchRow to my findRowByIdentifier(appName, targetIdentifier)
        if matchRow is not missing value then return matchRow
        delay 0.1
    end repeat
    error "Timed out waiting for row: " & targetIdentifier
end waitForRowByIdentifier

on run argv
    set appName to item 1 of argv
    set renamedName to item 2 of argv
    set childName to item 3 of argv
    set childRowID to "area-row-" & childName

    set windowIndex to my waitForContentWindowIndex(appName, 20)

    tell application "System Events"
        tell process appName
            set frontmost to true
            try
                perform action "AXRaise" of window windowIndex
            end try

            set childRow to my waitForRowByIdentifier(appName, childRowID, 10)
            try
                perform action "AXShowMenu" of UI element 1 of UI element 1 of childRow
            on error
                try
                    perform action "AXShowMenu" of childRow
                on error
                    try
                        perform action "AXShowAlternateUI" of childRow
                    end try
                end try
            end try

            delay 0.12
            tell application "System Events" to key code 36

            set deadline to (current date) + 8
            repeat while (current date) < deadline
                if exists sheet 1 of window windowIndex then
                    set renameSheet to sheet 1 of window windowIndex
                    set nameField to my firstTextFieldIn(renameSheet)
                    if nameField is not missing value then
                        set value of nameField to renamedName
                        tell application "System Events" to key code 36
                        return true
                    end if
                end if
                delay 0.05
            end repeat
        end tell
    end tell

    error "Rename sheet did not appear"
end run
end using terms from
APPLESCRIPT

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
