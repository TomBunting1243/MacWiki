#!/usr/bin/env bash

set -euo pipefail

APP_NAME="${APP_NAME:-MacWiki}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BIN_DEFAULT="$REPO_ROOT/.build/arm64-apple-macosx/debug/MacWiki"
APP_BIN_FALLBACK="$REPO_ROOT/.build/debug/MacWiki"
APP_BIN="${APP_BIN:-$APP_BIN_DEFAULT}"
RESTART_APP="${RESTART_APP:-1}"

if [[ ! -x "$APP_BIN" && -x "$APP_BIN_FALLBACK" ]]; then
  APP_BIN="$APP_BIN_FALLBACK"
fi

timestamp="$(date +%Y%m%d_%H%M%S)"
suffix="$(printf '%04d' "$((RANDOM % 10000))")"
FOLDER_NAME="QA_COLLAPSE_FOLDER_${timestamp}_${suffix}"
LIST_NAME="QA_COLLAPSE_LIST_${timestamp}_${suffix}"
FOLDER_ROW_ID="area-row-${FOLDER_NAME}"

echo "Starting folder-collapse selected-list QA harness..."
echo "Folder: $FOLDER_NAME"
echo "List:   $LIST_NAME"

if [[ ! -x "$APP_BIN" ]]; then
  echo "ERROR: App binary not found at $APP_BIN"
  echo "Run: swift build"
  exit 1
fi

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

if [[ "$RESTART_APP" == "1" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  sleep 1
  echo "Launching $APP_NAME..."
  open -n "$APP_BIN" >/tmp/macwiki_qa_folder_collapse_selected_list.log 2>&1
elif ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "Launching $APP_NAME..."
  open -n "$APP_BIN" >/tmp/macwiki_qa_folder_collapse_selected_list.log 2>&1
fi

echo "Waiting for $APP_NAME process and content window..."
content_window_ready=0
for _ in $(seq 1 80); do
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
    content_window_ready=1
    break
  fi
  sleep 0.2
done

if [[ "$content_window_ready" != "1" ]]; then
  window_diag="$(
    osascript - "$APP_NAME" <<'APPLESCRIPT' 2>/dev/null || echo "window-diagnostics-unavailable"
tell application "System Events"
    if not (exists process (item 1 of argv)) then return "process-missing"
    tell process (item 1 of argv)
        return "windows=" & (count of windows)
    end tell
end tell
APPLESCRIPT
  )"
  echo "ERROR: Timed out waiting for $APP_NAME content window."
  echo "Diagnostic: $window_diag"
  echo "This harness requires a visible desktop GUI session with Accessibility permissions."
  exit 1
fi

echo "Creating folder and list..."
osascript - "$APP_NAME" "$FOLDER_NAME" "$LIST_NAME" <<'APPLESCRIPT'
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

on createEntity(appName, windowIndex, menuItemNames, entityName)
    set selectedMenuItemName to missing value

    tell application "System Events"
        tell process appName
            repeat with candidateName in menuItemNames
                if exists menu item (candidateName as text) of menu "File" of menu bar item "File" of menu bar 1 then
                    click menu item (candidateName as text) of menu "File" of menu bar item "File" of menu bar 1
                    set selectedMenuItemName to (candidateName as text)
                    exit repeat
                end if
            end repeat
        end tell
    end tell

    if selectedMenuItemName is missing value then
        error "No matching menu item found in File menu"
    end if

    set deadline to (current date) + 8
    repeat while (current date) < deadline
        tell application "System Events"
            tell process appName
                if exists sheet 1 of window windowIndex then
                    set createSheet to sheet 1 of window windowIndex
                    set nameField to my firstTextFieldIn(createSheet)
                    if nameField is missing value then error "Sheet has no text field: " & selectedMenuItemName
                    set value of nameField to entityName
                    tell application "System Events" to key code 36
                    return true
                end if
            end tell
        end tell
        delay 0.05
    end repeat

    error "Sheet did not appear for menu item: " & selectedMenuItemName
end createEntity

on run argv
    set appName to item 1 of argv
    set folderName to item 2 of argv
    set listName to item 3 of argv

    set windowIndex to my waitForContentWindowIndex(appName, 20)

    tell application "System Events"
        tell process appName
            set frontmost to true
            try
                perform action "AXRaise" of window windowIndex
            end try
        end tell
    end tell

    my createEntity(appName, windowIndex, {"New Folder"}, folderName)
    my selectRecentsRow(appName, windowIndex, 4)
    my createEntity(appName, windowIndex, {"New Reading List", "New List"}, listName)
end run
end using terms from
APPLESCRIPT

echo "Resolving row coordinates for drag-to-folder..."
coords="$(
osascript - "$APP_NAME" "$LIST_NAME" "$FOLDER_ROW_ID" <<'APPLESCRIPT'
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

on findRowByLabel(appName, targetLabel)
    set windowIndex to my waitForContentWindowIndex(appName, 4)
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

on waitForRowByIdentifier(appName, targetIdentifier, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set matchRow to my findRowByIdentifier(appName, targetIdentifier)
        if matchRow is not missing value then return matchRow
        delay 0.1
    end repeat
    error "Timed out waiting for row with AXIdentifier: " & targetIdentifier
end waitForRowByIdentifier

on waitForRowByLabel(appName, targetLabel, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set matchRow to my findRowByLabel(appName, targetLabel)
        if matchRow is not missing value then return matchRow
        delay 0.1
    end repeat
    error "Timed out waiting for row label: " & targetLabel
end waitForRowByLabel

on run argv
    set appName to item 1 of argv
    set listName to item 2 of argv
    set folderRowID to item 3 of argv

    set listRow to my waitForRowByLabel(appName, listName, 20)
    set folderRow to my waitForRowByIdentifier(appName, folderRowID, 20)

    set listPos to position of listRow
    set listSize to size of listRow
    set folderPos to position of folderRow
    set folderSize to size of folderRow

    set listCenterX to (item 1 of listPos) + ((item 1 of listSize) / 2)
    set listCenterY to (item 2 of listPos) + ((item 2 of listSize) / 2)
    set folderCenterX to (item 1 of folderPos) + ((item 1 of folderSize) / 2)
    set folderCenterY to (item 2 of folderPos) + ((item 2 of folderSize) / 2)

    return (listCenterX as text) & " " & (listCenterY as text) & " " & (folderCenterX as text) & " " & (folderCenterY as text)
end run
end using terms from
APPLESCRIPT
)"

read -r list_x list_y folder_x folder_y <<<"$coords"

if [[ -z "${list_x:-}" || -z "${list_y:-}" || -z "${folder_x:-}" || -z "${folder_y:-}" ]]; then
  echo "ERROR: Failed to resolve row coordinates."
  echo "Raw coordinate payload: '$coords'"
  exit 1
fi

echo "Dragging list into folder..."
activate_app
sleep 0.15
swift "$SCRIPT_DIR/cg_drag.swift" \
  --start-x "$list_x" \
  --start-y "$list_y" \
  --end-x "$folder_x" \
  --end-y "$folder_y" \
  --duration 0.42 \
  --flip-y

echo "Verifying collapse fallback and folder responsiveness..."
osascript - "$APP_NAME" "$FOLDER_ROW_ID" "$LIST_NAME" <<'APPLESCRIPT'
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

on rowPrimaryLabel(rowElement)
    set rowElements to entire contents of rowElement
    repeat with e in rowElements
        try
            if class of e is static text then
                try
                    set rowValue to value of e as text
                    if rowValue is not "" then return rowValue
                end try
                try
                    set rowName to name of e as text
                    if rowName is not "" then return rowName
                end try
            end if
        end try
    end repeat
    return ""
end rowPrimaryLabel

on listContainsValue(theList, expectedValue)
    repeat with listValue in theList
        if (listValue as text) is expectedValue then return true
    end repeat
    return false
end listContainsValue

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

on findRowByLabel(appName, targetLabel)
    set windowIndex to my waitForContentWindowIndex(appName, 4)
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

on waitForRowByIdentifier(appName, targetIdentifier, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set matchRow to my findRowByIdentifier(appName, targetIdentifier)
        if matchRow is not missing value then return matchRow
        delay 0.1
    end repeat
    error "Timed out waiting for row with AXIdentifier: " & targetIdentifier
end waitForRowByIdentifier

on waitForRowByLabel(appName, targetLabel, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set matchRow to my findRowByLabel(appName, targetLabel)
        if matchRow is not missing value then return matchRow
        delay 0.1
    end repeat
    error "Timed out waiting for row label: " & targetLabel
end waitForRowByLabel

on waitForNoRowByLabel(appName, targetLabel, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    repeat while (current date) < deadline
        set matchRow to my findRowByLabel(appName, targetLabel)
        if matchRow is missing value then return true
        delay 0.1
    end repeat
    error "Row still visible after collapse: " & targetLabel
end waitForNoRowByLabel

on selectedRowLabels(appName)
    set labels to {}
    set windowIndex to my waitForContentWindowIndex(appName, 4)
    tell application "System Events"
        tell process appName
            set outlineElement to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window windowIndex
            repeat with r in rows of outlineElement
                set isSelected to false
                try
                    set isSelected to value of attribute "AXSelected" of r
                end try
                if isSelected then
                    set labelValue to my rowPrimaryLabel(r)
                    if labelValue is not "" then set end of labels to labelValue
                end if
            end repeat
        end tell
    end tell
    return labels
end selectedRowLabels

on pressRow(rowElement)
    try
        perform action "AXPress" of rowElement
        return true
    end try
    try
        click rowElement
        return true
    end try
    return false
end pressRow

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
    set folderRowID to item 2 of argv
    set listName to item 3 of argv

    set windowIndex to my waitForContentWindowIndex(appName, 20)
    tell application "System Events"
        tell process appName
            set frontmost to true
            try
                perform action "AXRaise" of window windowIndex
            end try
        end tell
    end tell

    my ensureRowExpandedState(appName, folderRowID, true, 12, "Could not ensure folder is expanded before selection")

    set listRow to my waitForRowByLabel(appName, listName, 12)
    if my pressRow(listRow) is false then
        error "Could not select list row before collapse"
    end if

    delay 0.2
    set selectedBeforeCollapse to my selectedRowLabels(appName)
    if my listContainsValue(selectedBeforeCollapse, listName) is false then
        error "Expected selected row to be list before collapse"
    end if

    my ensureRowExpandedState(appName, folderRowID, false, 8, "Could not collapse folder")

    my waitForNoRowByLabel(appName, listName, 10)

    delay 0.2
    set selectedAfterCollapse to my selectedRowLabels(appName)
    if my listContainsValue(selectedAfterCollapse, "Recents") is false then
        error "Expected selection fallback to Recents after collapse"
    end if

    my ensureRowExpandedState(appName, folderRowID, true, 8, "Could not re-expand folder")

    set _ to my waitForRowByLabel(appName, listName, 10)

    my ensureRowExpandedState(appName, folderRowID, false, 8, "Folder did not stay responsive after first re-expand")

    my ensureRowExpandedState(appName, folderRowID, true, 8, "Folder did not stay responsive after second expand")

    set _ to my waitForRowByLabel(appName, listName, 10)
end run
end using terms from
APPLESCRIPT

echo "PASS: Folder collapse while selected list is inside subtree is stable."
echo "Verified:"
echo "  - selected list moved inside folder"
echo "  - collapse hid selected list row"
echo "  - selection fell back to Recents"
echo "  - folder remained expandable/collapsible after fallback"
