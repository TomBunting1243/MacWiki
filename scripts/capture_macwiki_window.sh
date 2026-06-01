#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

output_path="${1:-/tmp/macwiki-audit/macwiki-window-$(date +%Y%m%d_%H%M%S).png}"
launch_delay_seconds="${MACWIKI_CAPTURE_DELAY:-0.35}"
APP_NAME="${APP_NAME:-MacWiki}"
app_binary_default="$repo_root/.build/arm64-apple-macosx/debug/MacWiki"
app_binary_fallback="$repo_root/.build/debug/MacWiki"
app_binary="${APP_BIN:-$app_binary_default}"

if [[ ! -x "$app_binary" && -x "$app_binary_fallback" ]]; then
  app_binary="$app_binary_fallback"
fi

mkdir -p "$(dirname "$output_path")"
mkdir -p /tmp/macwiki-audit

if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  if [[ -x "$app_binary" ]]; then
    "$app_binary" >/tmp/macwiki-audit/capture-window-launch.log 2>&1 &
    sleep 1
  else
    echo "$APP_NAME is not running and app binary was not found at: $app_binary" >&2
    exit 1
  fi
fi

macwiki_pid="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
if [[ -n "$macwiki_pid" ]]; then
osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "System Events"
  if exists (first process whose unix id is $macwiki_pid) then
    set frontmost of first process whose unix id is $macwiki_pid to true
  end if
end tell
APPLESCRIPT
fi
sleep "$launch_delay_seconds"

capture_pids="$({ pgrep -x "$APP_NAME" || true; } | tr '\n' ',' | sed 's/,$//')"
window_number="$(
MACWIKI_CAPTURE_PIDS="$capture_pids" \
MACWIKI_CAPTURE_APP_NAME="$APP_NAME" \
swift - <<'SWIFT'
import CoreGraphics
import Foundation

guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

let ownerKey = kCGWindowOwnerName as String
let layerKey = kCGWindowLayer as String
let numberKey = kCGWindowNumber as String
let boundsKey = kCGWindowBounds as String
let alphaKey = kCGWindowAlpha as String
let pidKey = kCGWindowOwnerPID as String

let pidSet: Set<Int> = {
    guard let raw = ProcessInfo.processInfo.environment["MACWIKI_CAPTURE_PIDS"], !raw.isEmpty else {
        return []
    }
    return Set(raw.split(separator: ",").compactMap { Int($0) })
}()
let appName = ProcessInfo.processInfo.environment["MACWIKI_CAPTURE_APP_NAME"] ?? "MacWiki"

let candidates: [(number: Int, area: Double)] = windowInfo.compactMap { window in
    let ownerName = (window[ownerKey] as? String) ?? ""
    let ownerPID = window[pidKey] as? Int ?? -1
    let ownerNameMatch = ownerName.localizedCaseInsensitiveContains(appName)
    let ownerPidMatch = pidSet.contains(ownerPID)

    guard ownerNameMatch || ownerPidMatch else { return nil }
    guard (window[layerKey] as? Int ?? 1) == 0 else { return nil }
    let alpha = window[alphaKey] as? Double ?? 1
    guard alpha > 0 else { return nil }
    guard let number = window[numberKey] as? Int else { return nil }
    guard let bounds = window[boundsKey] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else {
        return nil
    }
    return (number: number, area: width * height)
}

if let chosen = candidates.max(by: { $0.area < $1.area }) {
    print(chosen.number)
}
SWIFT
)"

window_number="$(echo "$window_number" | tr -cd '0-9')"
if [[ -z "$window_number" ]]; then
  if [[ -n "${macwiki_pid:-}" ]]; then
    window_bounds="$(
      osascript <<APPLESCRIPT 2>/dev/null || true
tell application "System Events"
  if not (exists (first process whose unix id is $macwiki_pid)) then
    return ""
  end if
  tell first process whose unix id is $macwiki_pid
    if (count of windows) is 0 then
      return ""
    end if
    set win to front window
    set {xPos, yPos} to position of win
    set {w, h} to size of win
    return (xPos as text) & "," & (yPos as text) & "," & (w as text) & "," & (h as text)
  end tell
end tell
APPLESCRIPT
    )"

    if [[ "$window_bounds" =~ ^-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+$ ]]; then
      screencapture -x -R "$window_bounds" "$output_path"
      echo "$output_path"
      exit 0
    fi
  fi

  echo "Failed to resolve a visible $APP_NAME window id for targeted capture." >&2
  exit 1
fi

screencapture -x -l "$window_number" "$output_path"
echo "$output_path"
