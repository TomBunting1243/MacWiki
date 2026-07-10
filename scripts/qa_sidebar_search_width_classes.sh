#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

APP_NAME="${APP_NAME:-MacWiki}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.tombunting.MacWiki}"
APP_BIN_DEFAULT="$REPO_ROOT/.build/arm64-apple-macosx/debug/MacWiki"
APP_BIN_FALLBACK="$REPO_ROOT/.build/debug/MacWiki"
APP_BIN="${APP_BIN:-$APP_BIN_DEFAULT}"

if [[ ! -x "$APP_BIN" && -x "$APP_BIN_FALLBACK" ]]; then
  APP_BIN="$APP_BIN_FALLBACK"
fi

OUTPUT_DIR="${1:-/tmp/macwiki-qa/sidebar-search-widths-$(date +%Y%m%d_%H%M%S)}"
WIDTH_PRESETS_CSV="${WIDTH_PRESETS_CSV:-1040,1400,1760}"
WINDOW_HEIGHT="${WINDOW_HEIGHT:-980}"
WINDOW_POS_X="${WINDOW_POS_X:-20}"
WINDOW_POS_Y="${WINDOW_POS_Y:-70}"
WINDOW_WIDTH_TOLERANCE="${WINDOW_WIDTH_TOLERANCE:-24}"
SEARCH_QUERY="${SEARCH_QUERY:-Albert Einstein}"
LISTS_SIDEBAR_WIDTH="${LISTS_SIDEBAR_WIDTH:-180}"
STRICT_OCR="${STRICT_OCR:-0}"
INTERACTION_SETTLE_SECONDS="${INTERACTION_SETTLE_SECONDS:-0.8}"
RESULT_LOAD_SECONDS="${RESULT_LOAD_SECONDS:-2.3}"
HARNESS_DRIVER="${HARNESS_DRIVER:-app}"
LAUNCH_OPEN_SEARCH_KEY="${LAUNCH_OPEN_SEARCH_KEY:-qa.sidebarSearch.openOnLaunch}"
LAUNCH_SEARCH_QUERY_KEY="${LAUNCH_SEARCH_QUERY_KEY:-qa.sidebarSearch.queryOnLaunch}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/sidebar-search-home-$(date +%Y%m%d_%H%M%S)-$RANDOM}"

CAPTURE_SCRIPT="$SCRIPT_DIR/capture_macwiki_window.sh"
OCR_SCRIPT="$SCRIPT_DIR/ocr_text.swift"

if [[ ! -x "$CAPTURE_SCRIPT" ]]; then
  echo "ERROR: Missing executable capture script: $CAPTURE_SCRIPT" >&2
  exit 1
fi

if [[ ! -x "$OCR_SCRIPT" ]]; then
  chmod +x "$OCR_SCRIPT"
fi

if [[ ! -x "$APP_BIN" ]]; then
  echo "ERROR: App binary not found: $APP_BIN" >&2
  echo "Run: swift build" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
qa_prepare_isolated_home
REPORT_PATH="$OUTPUT_DIR/report.md"

warn_count=0
hard_fail_count=0

note_warn() {
  local message="$1"
  warn_count=$((warn_count + 1))
  echo "- WARN: $message" >>"$REPORT_PATH"
}

note_fail() {
  local message="$1"
  hard_fail_count=$((hard_fail_count + 1))
  echo "- FAIL: $message" >>"$REPORT_PATH"
}

note_pass() {
  local message="$1"
  echo "- PASS: $message" >>"$REPORT_PATH"
}

run_osascript_with_timeout() {
  local timeout_seconds="$1"
  shift
  local temp_script
  temp_script="$(mktemp)"
  cat >"$temp_script"

  osascript "$temp_script" "$@" &
  local script_pid=$!
  local elapsed_ticks=0
  local max_ticks=$((timeout_seconds * 10))

  while kill -0 "$script_pid" >/dev/null 2>&1; do
    if (( elapsed_ticks >= max_ticks )); then
      kill "$script_pid" >/dev/null 2>&1 || true
      wait "$script_pid" >/dev/null 2>&1 || true
      rm -f "$temp_script"
      return 124
    fi
    sleep 0.1
    elapsed_ticks=$((elapsed_ticks + 1))
  done

  local exit_code=0
  wait "$script_pid" || exit_code=$?
  rm -f "$temp_script"
  return "$exit_code"
}

prepare_deterministic_defaults() {
  HOME="$QA_HOME" CFFIXED_USER_HOME="$QA_HOME" defaults delete "$APP_BUNDLE_ID" searchPresentationMode >/dev/null 2>&1 || true
  HOME="$QA_HOME" CFFIXED_USER_HOME="$QA_HOME" defaults write "$APP_BUNDLE_ID" mainWindow.sidebarWidth -float "$LISTS_SIDEBAR_WIDTH" >/dev/null 2>&1 || true
}

set_launch_sidebar_search_defaults() {
  local should_open="$1"
  local query_text="$2"

  if [[ "$should_open" == "1" ]]; then
    HOME="$QA_HOME" CFFIXED_USER_HOME="$QA_HOME" defaults write "$APP_BUNDLE_ID" "$LAUNCH_OPEN_SEARCH_KEY" -bool true >/dev/null 2>&1 || true
  else
    HOME="$QA_HOME" CFFIXED_USER_HOME="$QA_HOME" defaults delete "$APP_BUNDLE_ID" "$LAUNCH_OPEN_SEARCH_KEY" >/dev/null 2>&1 || true
  fi

  HOME="$QA_HOME" CFFIXED_USER_HOME="$QA_HOME" defaults write "$APP_BUNDLE_ID" "$LAUNCH_SEARCH_QUERY_KEY" -string "$query_text" >/dev/null 2>&1 || true
}

clear_launch_sidebar_search_defaults() {
  HOME="$QA_HOME" CFFIXED_USER_HOME="$QA_HOME" defaults delete "$APP_BUNDLE_ID" "$LAUNCH_OPEN_SEARCH_KEY" >/dev/null 2>&1 || true
  HOME="$QA_HOME" CFFIXED_USER_HOME="$QA_HOME" defaults delete "$APP_BUNDLE_ID" "$LAUNCH_SEARCH_QUERY_KEY" >/dev/null 2>&1 || true
}

relaunch_app() {
  qa_stop_exact
  sleep 0.7
  qa_launch_exact "/tmp/macwiki-qa-sidebar-search-launch.log"

  if ! wait_for_content_window; then
    echo "ERROR: Timed out waiting for MacWiki content window." >&2
    exit 1
  fi
}

require_accessibility_permissions() {
  if ! swift - <<'SWIFT' >/dev/null 2>&1
import ApplicationServices
import Foundation
exit(AXIsProcessTrusted() ? 0 : 1)
SWIFT
  then
    echo "ERROR: Accessibility permission is required for UI automation harnesses." >&2
    echo "Enable accessibility for Terminal/Codex app, then rerun." >&2
    exit 2
  fi
}

activate_macwiki() {
  run_osascript_with_timeout 8 "$APP_NAME" >/dev/null 2>&1 <<'APPLESCRIPT' || true
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
    tell application appName to activate
    set winIdx to my contentWindowIndex(appName)
    if winIdx is 0 then return
    tell application "System Events"
        tell process appName
            set frontmost to true
            try
                perform action "AXRaise" of window winIdx
            end try
        end tell
    end tell
end run
end using terms from
APPLESCRIPT
}

wait_for_content_window() {
  local attempts=0
  while (( attempts < 100 )); do
    if run_osascript_with_timeout 4 "$APP_NAME" >/dev/null 2>&1 <<'APPLESCRIPT'
using terms from application "System Events"
on run argv
    set appName to item 1 of argv
    tell application "System Events"
        if not (exists process appName) then error "missing process"
        tell process appName
            set windowCount to count of windows
            repeat with idx from 1 to windowCount
                try
                    if exists splitter group 1 of group 1 of window idx then return
                end try
            end repeat
        end tell
    end tell
    error "missing content window"
end run
end using terms from
APPLESCRIPT
    then
      return 0
    fi
    sleep 0.2
    attempts=$((attempts + 1))
  done
  return 1
}

launch_app_if_needed() {
  qa_stop_exact
  qa_launch_exact "/tmp/macwiki-qa-sidebar-search-launch.log"

  if ! wait_for_content_window; then
    echo "ERROR: Timed out waiting for MacWiki content window." >&2
    exit 1
  fi
}

set_window_geometry() {
  local width="$1"
  local height="$2"
  local x="$3"
  local y="$4"
  local actual_width

  if ! actual_width="$(run_osascript_with_timeout 10 "$APP_NAME" "$width" "$height" "$x" "$y" 2>/dev/null <<'APPLESCRIPT'
using terms from application "System Events"
on contentWindowIndex(appName)
    tell application "System Events"
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
    set targetWidth to (item 2 of argv) as integer
    set targetHeight to (item 3 of argv) as integer
    set targetX to (item 4 of argv) as integer
    set targetY to (item 5 of argv) as integer

    set windowIndex to my contentWindowIndex(appName)
    if windowIndex is 0 then error "No content window found"

    tell application appName to activate
    tell application "System Events"
        tell process appName
            set frontmost to true
            try
                set position of window windowIndex to {targetX, targetY}
            end try
            try
                set size of window windowIndex to {targetWidth, targetHeight}
            end try
            try
                perform action "AXRaise" of window windowIndex
            end try
            delay 0.35
            set actualSize to size of window windowIndex
            return item 1 of actualSize
        end tell
    end tell
end run
end using terms from
APPLESCRIPT
  )"; then
    echo "WARN: Failed to set window geometry to ${width}x${height} at ${x},${y}" >&2
    return 1
  fi

  actual_width="$(printf '%s\n' "$actual_width" | awk '/^[0-9]+$/ { value = $0 } END { print value }')"
  if [[ -z "$actual_width" ]]; then
    echo "WARN: Window geometry did not report an actual width for target ${width}px." >&2
    return 1
  fi

  local delta=$((actual_width - width))
  (( delta < 0 )) && delta=$((-delta))
  if (( delta > WINDOW_WIDTH_TOLERANCE )); then
    echo "WARN: Window width clamped to ${actual_width}px for target ${width}px." >&2
    return 1
  fi

  ACTUAL_WINDOW_WIDTH="$actual_width"
  return 0
}

open_search_ui() {
  if run_osascript_with_timeout 8 "$APP_NAME" >/dev/null 2>&1 <<'APPLESCRIPT'
using terms from application "System Events"
on run argv
    set appName to item 1 of argv
    tell application appName to activate
    tell application "System Events"
        tell process appName
            if exists menu item "Search Wikipedia" of menu "File" of menu bar item "File" of menu bar 1 then
                click menu item "Search Wikipedia" of menu "File" of menu bar item "File" of menu bar 1
                return
            end if
        end tell
        keystroke "k" using {command down}
    end tell
end run
end using terms from
APPLESCRIPT
  then
    return 0
  fi

  if ! run_osascript_with_timeout 8 "$APP_NAME" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
    set appName to item 1 of argv
    tell application appName to activate
    tell application "System Events"
        keystroke "k" using {command down}
    end tell
end run
APPLESCRIPT
  then
    return 1
  fi

  return 0
}

set_search_query() {
  local query="$1"
  if run_osascript_with_timeout 8 "$APP_NAME" "$query" >/dev/null 2>&1 <<'APPLESCRIPT'
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

on sidebarSearchFieldIn(elementRef)
    set allElements to entire contents of elementRef
    repeat with e in allElements
        try
            if (value of attribute "AXIdentifier" of e) is "sidebar-search-field" then return e
        end try
    end repeat
    repeat with e in allElements
        try
            if class of e is text field then return e
        end try
    end repeat
    return missing value
end sidebarSearchFieldIn

on run argv
    set appName to item 1 of argv
    set queryText to item 2 of argv

    set windowIndex to my contentWindowIndex(appName)
    if windowIndex is 0 then error "missing content window"

    tell application appName to activate
    tell application "System Events"
        tell process appName
            set targetField to my sidebarSearchFieldIn(splitter group 1 of group 1 of window windowIndex)
            if targetField is missing value then error "missing search field"
            set value of targetField to queryText
        end tell
    end tell
end run
end using terms from
APPLESCRIPT
  then
    return 0
  fi

  if ! run_osascript_with_timeout 8 "$APP_NAME" "$query" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
    set appName to item 1 of argv
    set queryText to item 2 of argv
    tell application appName to activate
    tell application "System Events"
        keystroke "a" using {command down}
        key code 51
        if (length of queryText) > 0 then
            keystroke queryText
        end if
    end tell
end run
APPLESCRIPT
  then
    return 1
  fi

  return 0
}

capture_and_ocr() {
  local capture_path="$1"
  local ocr_path="$2"
  APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" APP_PID="$QA_APP_PID" "$CAPTURE_SCRIPT" "$capture_path" >/dev/null
  "$OCR_SCRIPT" "$capture_path" >"$ocr_path" 2>/dev/null || true
}

assert_contains_text() {
  local file="$1"
  local pattern="$2"
  local description="$3"
  local strict="$4"
  if rg -qi "$pattern" "$file"; then
    note_pass "$description"
  else
    if [[ "$strict" == "1" ]]; then
      note_fail "$description (missing pattern: $pattern)"
    else
      note_warn "$description (missing pattern: $pattern)"
    fi
  fi
}

layout_label_for_width() {
  local width="$1"
  if (( width < 1200 )); then
    echo "narrow"
  elif (( width < 1600 )); then
    echo "standard"
  else
    echo "wide"
  fi
}

if [[ "$HARNESS_DRIVER" != "app" && "$HARNESS_DRIVER" != "ax" ]]; then
  echo "ERROR: HARNESS_DRIVER must be 'app' or 'ax' (current: $HARNESS_DRIVER)." >&2
  exit 1
fi

cleanup() {
  clear_launch_sidebar_search_defaults
  qa_stop_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

prepare_deterministic_defaults
require_accessibility_permissions
if [[ "$HARNESS_DRIVER" == "app" ]]; then
  set_launch_sidebar_search_defaults 1 "$SEARCH_QUERY"
fi
launch_app_if_needed
activate_macwiki
sleep "$INTERACTION_SETTLE_SECONDS"

echo "Output directory: $OUTPUT_DIR"
echo "Harness target widths: $WIDTH_PRESETS_CSV"
echo "Search query: $SEARCH_QUERY"

{
  echo "# MacWiki Window Width-Class QA Report"
  echo
  echo "- Captured: $(date)"
  echo "- Output directory: \`$OUTPUT_DIR\`"
  echo "- App binary: \`$APP_BIN\`"
  echo "- Lists sidebar width seed: \`${LISTS_SIDEBAR_WIDTH}px\`"
  echo "- Practical whole-window width presets: \`$WIDTH_PRESETS_CSV\`"
  echo "- Search query: \`$SEARCH_QUERY\`"
  echo "- Strict OCR checks: \`$STRICT_OCR\`"
  echo
} >"$REPORT_PATH"

IFS=',' read -r -a widths <<<"$WIDTH_PRESETS_CSV"
index=1

for raw_width in "${widths[@]}"; do
  width="$(echo "$raw_width" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ ! "$width" =~ ^[0-9]+$ ]]; then
    continue
  fi

  class_label="$(layout_label_for_width "$width")"
  state_prefix="$(printf "%02d-%s-%spx" "$index" "$class_label" "$width")"

  echo "Running width case $index: ${width}px ($class_label)"

  ACTUAL_WINDOW_WIDTH=""
  if ! set_window_geometry "$width" "$WINDOW_HEIGHT" "$WINDOW_POS_X" "$WINDOW_POS_Y"; then
    note_fail "Could not establish and verify target window width ${width}px."
    index=$((index + 1))
    continue
  fi
  note_pass "Window width reached ${ACTUAL_WINDOW_WIDTH}px for target ${width}px."
  sleep "$INTERACTION_SETTLE_SECONDS"
  activate_macwiki

  if ! open_search_ui; then
    note_warn "Failed to open Search UI at ${width}px (automation unavailable in this runtime)."
    fallback_shot="$OUTPUT_DIR/${state_prefix}-fallback.png"
    fallback_ocr="$OUTPUT_DIR/${state_prefix}-fallback.ocr.txt"
    capture_and_ocr "$fallback_shot" "$fallback_ocr"
    {
      echo "## Width $width ($class_label)"
      echo
      echo "- Fallback capture (search UI unavailable): \`$fallback_shot\`"
      echo "- Fallback OCR: \`$fallback_ocr\`"
      echo
    } >>"$REPORT_PATH"
    index=$((index + 1))
    continue
  fi

  sleep 0.35
  if ! set_search_query "$SEARCH_QUERY"; then
    note_warn "Failed to set search query at ${width}px (automation unavailable in this runtime)."
    fallback_shot="$OUTPUT_DIR/${state_prefix}-query-fallback.png"
    fallback_ocr="$OUTPUT_DIR/${state_prefix}-query-fallback.ocr.txt"
    capture_and_ocr "$fallback_shot" "$fallback_ocr"
    {
      echo "## Width $width ($class_label)"
      echo
      echo "- Query fallback capture (query injection unavailable): \`$fallback_shot\`"
      echo "- Query fallback OCR: \`$fallback_ocr\`"
      echo
    } >>"$REPORT_PATH"
    index=$((index + 1))
    continue
  fi
  sleep "$RESULT_LOAD_SECONDS"

  query_shot="$OUTPUT_DIR/${state_prefix}-query.png"
  query_ocr="$OUTPUT_DIR/${state_prefix}-query.ocr.txt"
  capture_and_ocr "$query_shot" "$query_ocr"

  {
    echo "## Width $width ($class_label)"
    echo
    echo "- Verified actual window width: \`${ACTUAL_WINDOW_WIDTH}px\`"
    echo "- Query capture: \`$query_shot\`"
    echo "- OCR: \`$query_ocr\`"
  } >>"$REPORT_PATH"

  assert_contains_text "$query_ocr" "Search" "Search header visible at $width px" 1
  assert_contains_text "$query_ocr" "result|results|searching" "Results metadata visible at $width px" "$STRICT_OCR"

  if set_search_query ""; then
    sleep 0.7
  else
    note_warn "Failed to clear query text at ${width}px."
  fi

  empty_shot="$OUTPUT_DIR/${state_prefix}-empty.png"
  empty_ocr="$OUTPUT_DIR/${state_prefix}-empty.ocr.txt"
  capture_and_ocr "$empty_shot" "$empty_ocr"

  {
    echo "- Empty capture: \`$empty_shot\`"
    echo "- Empty OCR: \`$empty_ocr\`"
  } >>"$REPORT_PATH"

  assert_contains_text "$empty_ocr" "Search Wikipedia|Search" "Empty-state search prompt visible at $width px" "$STRICT_OCR"
  echo >>"$REPORT_PATH"

  index=$((index + 1))
done

echo "## Summary" >>"$REPORT_PATH"
echo >>"$REPORT_PATH"
echo "- Warnings: $warn_count" >>"$REPORT_PATH"
echo "- Hard failures: $hard_fail_count" >>"$REPORT_PATH"
echo >>"$REPORT_PATH"
echo "- Harness: \`scripts/qa_sidebar_search_width_classes.sh\`" >>"$REPORT_PATH"

if (( hard_fail_count > 0 )); then
  echo "FAIL: Harness found $hard_fail_count hard failure(s). Report: $REPORT_PATH" >&2
  exit 1
fi

echo "MacWiki window width-class QA complete. Report: $REPORT_PATH"
