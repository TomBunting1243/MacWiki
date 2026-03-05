#!/usr/bin/env bash

set -euo pipefail

WORKDIR="/Users/tombunting/Developer/MacWiki"
APP_NAME="${APP_NAME:-MacWiki}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

stamp="$(date +%Y%m%d_%H%M%S)"
suffix="$(printf '%04d' "$((RANDOM % 10000))")"
AREA_NAME="QA_CTX_AREA_${stamp}_${suffix}"
LIST_NAME="QA_CTX_LIST_${stamp}_${suffix}"
AREA_ROW_ID="area-row-${AREA_NAME}"
out_dir="/tmp/macwiki-qa/context-menu-ocr-${stamp}-${suffix}"
mkdir -p "$out_dir"

if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "ERROR: $APP_NAME is not running. Start the app first."
  exit 1
fi

echo "Running context-menu OCR smoke..."
echo "Area: $AREA_NAME"
echo "List: $LIST_NAME"
echo "Artifacts: $out_dir"

# Create a root folder + root list so we can probe both area-row and list-row menus.
osascript - "$APP_NAME" "$AREA_NAME" "$LIST_NAME" <<'APPLESCRIPT'
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

  if selectedMenuItemName is missing value then error "No matching menu item found"

  set deadline to (current date) + 8
  repeat while (current date) < deadline
    tell application "System Events"
      tell process appName
        if exists sheet 1 of window windowIndex then
          set createSheet to sheet 1 of window windowIndex
          set nameField to my firstTextFieldIn(createSheet)
          if nameField is missing value then error "Sheet has no text field"
          set value of nameField to entityName
          key code 36
          return true
        end if
      end tell
    end tell
    delay 0.05
  end repeat

  if selectedMenuItemName contains "Folder" then
    error "Sheet did not appear"
  end if

  -- Fallback: invoke keyboard shortcut for reading-list creation only.
  tell application "System Events"
    tell process appName
      key code 45 using {command down, option down, shift down}
    end tell
  end tell

  set fallbackDeadline to (current date) + 5
  repeat while (current date) < fallbackDeadline
    tell application "System Events"
      tell process appName
        if exists sheet 1 of window windowIndex then
          set createSheet to sheet 1 of window windowIndex
          set nameField to my firstTextFieldIn(createSheet)
          if nameField is missing value then error "Sheet has no text field (fallback)"
          set value of nameField to entityName
          key code 36
          return true
        end if
      end tell
    end tell
    delay 0.05
  end repeat

  error "Sheet did not appear"
end createEntity

on run argv
  set appName to item 1 of argv
  set areaName to item 2 of argv
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

  my createEntity(appName, windowIndex, {"New Folder"}, areaName)
  my selectRecentsRow(appName, windowIndex, 4)
  my createEntity(appName, windowIndex, {"New Reading List", "New List"}, listName)
end run
end using terms from
APPLESCRIPT

# Open area-row context menu via AXShowMenu on row heading element.
osascript - "$APP_NAME" "$AREA_ROW_ID" <<'APPLESCRIPT'
using terms from application "System Events"
on contentWindowIndex(appName)
  tell application "System Events"
    tell process appName
      repeat with idx from 1 to count of windows
        try
          if exists splitter group 1 of group 1 of window idx then return idx
        end try
      end repeat
    end tell
  end tell
  return 0
end contentWindowIndex

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
  set win to my contentWindowIndex(appName)
  tell application "System Events"
    tell process appName
      set outlineElement to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window win
      repeat with r in rows of outlineElement
        try
          if my rowMatchesIdentifier(r, targetIdentifier) then return r
        end try
      end repeat
    end tell
  end tell
  return missing value
end findRowByIdentifier

on run argv
  set appName to item 1 of argv
  set rowID to item 2 of argv
  tell application "System Events"
    tell process appName
      set frontmost to true
    end tell
  end tell
  set rowEl to my findRowByIdentifier(appName, rowID)
  if rowEl is missing value then error "Area row missing"
  tell application "System Events"
    tell process appName
      perform action "AXShowMenu" of UI element 1 of UI element 1 of rowEl
    end tell
  end tell
end run
end using terms from
APPLESCRIPT
sleep 0.25
screencapture -x "$out_dir/area-menu.png"

# Assert area menu text via OCR
for term in "Rename" "Delete Folder"; do
  if ! swift "$SCRIPT_DIR/ocr_find_text_centers.swift" "$out_dir/area-menu.png" "$term" > "$out_dir/area-${term// /_}.txt"; then
    echo "ERROR: OCR failed for area term: $term"
    exit 2
  fi
  if [[ ! -s "$out_dir/area-${term// /_}.txt" ]]; then
    echo "ERROR: Area context menu missing term: $term"
    exit 3
  fi
done

# Close context menu
osascript <<'APPLESCRIPT'
tell application "System Events" to key code 53
APPLESCRIPT
sleep 0.15

# Open list-row context menu by exact list label.
osascript - "$APP_NAME" "$LIST_NAME" <<'APPLESCRIPT'
using terms from application "System Events"
on contentWindowIndex(appName)
  tell application "System Events"
    tell process appName
      repeat with idx from 1 to count of windows
        try
          if exists splitter group 1 of group 1 of window idx then return idx
        end try
      end repeat
    end tell
  end tell
  return 0
end contentWindowIndex

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

on findRowByLabel(appName, targetLabel)
  set win to my contentWindowIndex(appName)
  tell application "System Events"
    tell process appName
      set outlineElement to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window win
      repeat with r in rows of outlineElement
        try
          if my rowContainsLabel(r, targetLabel) then return r
        end try
      end repeat
    end tell
  end tell
  return missing value
end findRowByLabel

on run argv
  set appName to item 1 of argv
  set labelName to item 2 of argv
  tell application "System Events"
    tell process appName
      set frontmost to true
    end tell
  end tell
  set rowEl to my findRowByLabel(appName, labelName)
  if rowEl is missing value then error "List row missing"
  tell application "System Events"
    tell process appName
      perform action "AXShowMenu" of UI element 1 of UI element 1 of rowEl
    end tell
  end tell
end run
end using terms from
APPLESCRIPT
sleep 0.25
screencapture -x "$out_dir/list-menu.png"

# Assert list menu text via OCR
for term in "Rename" "Change Icon" "Delete"; do
  if ! swift "$SCRIPT_DIR/ocr_find_text_centers.swift" "$out_dir/list-menu.png" "$term" > "$out_dir/list-${term// /_}.txt"; then
    echo "ERROR: OCR failed for list term: $term"
    exit 4
  fi
  if [[ ! -s "$out_dir/list-${term// /_}.txt" ]]; then
    echo "ERROR: List context menu missing term: $term"
    exit 5
  fi
done

# Close context menu
osascript <<'APPLESCRIPT'
tell application "System Events" to key code 53
APPLESCRIPT

echo "PASS: Context menu OCR smoke passed (area + list menus)."
echo "Artifacts: $out_dir"
