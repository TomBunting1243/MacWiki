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
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/folder-collapse-${timestamp}-${suffix}}"
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

qa_prepare_isolated_home
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
qa_launch_exact "/tmp/macwiki_qa_folder_collapse_selected_list.log"

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
coords="$(osascript -l JavaScript "$SCRIPT_DIR/lib/qa_sidebar_row_centers.js" "$APP_NAME" "$FOLDER_ROW_ID")"

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
  --duration 0.42

echo "Verifying collapse fallback and folder responsiveness..."
osascript -l JavaScript "$SCRIPT_DIR/lib/qa_verify_folder_collapse.js" "$APP_NAME" "$FOLDER_ROW_ID"

echo "PASS: Folder collapse while selected list is inside subtree is stable."
echo "Verified:"
echo "  - selected list moved inside folder"
echo "  - collapse hid selected list row"
echo "  - selection fell back to Recents"
echo "  - folder remained expandable/collapsible after fallback"
