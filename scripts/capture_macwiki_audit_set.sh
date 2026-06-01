#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
capture_window_script="$script_dir/capture_macwiki_window.sh"
repo_root="$(cd "$script_dir/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
app_binary_default="$repo_root/.build/arm64-apple-macosx/debug/MacWiki"
app_binary_fallback="$repo_root/.build/debug/MacWiki"
APP_BIN="${APP_BIN:-$app_binary_default}"

if [[ ! -x "$APP_BIN" && -x "$app_binary_fallback" ]]; then
  APP_BIN="$app_binary_fallback"
fi

if [[ ! -x "$capture_window_script" ]]; then
  echo "Missing required capture script: $capture_window_script" >&2
  exit 1
fi

launch_macwiki_if_needed() {
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    return
  fi

  if [[ -x "$APP_BIN" ]]; then
    "$APP_BIN" >/tmp/macwiki-audit/macwiki-audit-launch.log 2>&1 &
    sleep 1.2
  fi
}

raise_macwiki_window() {
  osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  set appName to item 1 of argv
tell application "System Events"
  if exists (first process whose name is appName) then
    set frontmost of first process whose name is appName to true
  end if
end tell
end run
APPLESCRIPT
}

capture_frontmost_window() {
  local destination="$1"
  local frontmost_bounds

  frontmost_bounds="$(
    osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  set frontProcess to first process whose frontmost is true
  if not (exists frontProcess) then return ""
  tell frontProcess
    if (count of windows) is 0 then return ""
    set win to front window
    set {xPos, yPos} to position of win
    set {w, h} to size of win
    return (xPos as text) & "," & (yPos as text) & "," & (w as text) & "," & (h as text)
  end tell
end tell
APPLESCRIPT
  )"

  if [[ "$frontmost_bounds" =~ ^-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+$ ]] \
    && screencapture -x -R "$frontmost_bounds" "$destination" >/dev/null 2>&1; then
    echo "Warning: fell back to frontmost-window capture for $destination" >&2
    return 0
  fi

  return 1
}

capture_with_retry() {
  local destination="$1"

  if APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" "$capture_window_script" "$destination" >/dev/null 2>&1; then
    return 0
  fi

  launch_macwiki_if_needed
  raise_macwiki_window
  sleep 1

  if APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" "$capture_window_script" "$destination" >/dev/null 2>&1; then
    return 0
  fi

  if capture_frontmost_window "$destination"; then
    return 0
  fi

  # Last-resort fallback so the audit run still completes even when
  # Accessibility/window-query APIs cannot resolve a specific MacWiki window.
  if screencapture -x "$destination" >/dev/null 2>&1; then
    echo "Warning: fell back to full-screen capture for $destination" >&2
    return 0
  fi

  return 1
}

output_dir="${1:-/tmp/macwiki-audit/set-$(date +%Y%m%d_%H%M%S)}"
prep_delay="${MACWIKI_AUDIT_PREP_DELAY:-4}"
states_csv="${MACWIKI_AUDIT_STATES:-home,discover,article,article_inspector,focus_toc,settings}"

mkdir -p "$output_dir"
mkdir -p /tmp/macwiki-audit
manifest_path="$output_dir/manifest.md"

IFS=',' read -r -a states <<< "$states_csv"

if [[ "${#states[@]}" -eq 0 ]]; then
  echo "No states configured. Set MACWIKI_AUDIT_STATES as a comma-separated list." >&2
  exit 1
fi

{
  echo "# MacWiki Audit Capture Set"
  echo
  echo "- Captured: $(date)"
  echo "- Output directory: \`$output_dir\`"
  echo "- App binary: \`$APP_BIN\`"
  echo "- Prep delay per state: \`${prep_delay}s\`"
  echo
  echo "## Images"
} > "$manifest_path"

index=1
for raw_state in "${states[@]}"; do
  state="$(echo "$raw_state" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ -z "$state" ]]; then
    continue
  fi

  safe_state="$(echo "$state" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [[ -z "$safe_state" ]]; then
    safe_state="state-$index"
  fi

  printf "\n[%02d/%02d] Arrange MacWiki for state: %s\n" "$index" "${#states[@]}" "$state"
  echo "Capturing in ${prep_delay}s..."

  osascript <<APPLESCRIPT >/dev/null 2>&1 || true
display notification "Capture in ${prep_delay} seconds: ${state}" with title "MacWiki Audit Capture"
APPLESCRIPT

  if [[ "$prep_delay" =~ ^[0-9]+$ ]] && (( prep_delay > 0 )); then
    sleep "$prep_delay"
  fi

  output_path="$(printf "%s/%02d-%s.png" "$output_dir" "$index" "$safe_state")"
  capture_with_retry "$output_path"

  echo "- **$state**: \`$output_path\`" >> "$manifest_path"
  echo "Saved: $output_path"

  index=$((index + 1))
done

echo
echo "Manifest: $manifest_path"
echo "$manifest_path"
