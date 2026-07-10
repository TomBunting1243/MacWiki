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
APP_PID="${APP_PID:-}"

if [[ ! -x "$app_binary" && -x "$app_binary_fallback" ]]; then
  app_binary="$app_binary_fallback"
fi

mkdir -p "$(dirname "$output_path")"
mkdir -p /tmp/macwiki-audit

if [[ -z "$APP_PID" || ! "$APP_PID" =~ ^[0-9]+$ ]]; then
  echo "APP_PID is required for a targeted capture." >&2
  exit 1
fi

expected_binary="$(cd "$(dirname "$app_binary")" && pwd -P)/$(basename "$app_binary")"
actual_binary="$(ps -p "$APP_PID" -o comm= 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
if [[ "$actual_binary" != "$expected_binary" ]]; then
  echo "PID $APP_PID does not match the requested app binary: $expected_binary" >&2
  exit 1
fi

macwiki_pid="$APP_PID"
osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "System Events"
  if exists (first process whose unix id is $macwiki_pid) then
    set frontmost of first process whose unix id is $macwiki_pid to true
  end if
end tell
APPLESCRIPT
sleep "$launch_delay_seconds"

capture_pids="$APP_PID"
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

let candidates: [(number: Int, area: Double)] = windowInfo.compactMap { window in
    let ownerPID = window[pidKey] as? Int ?? -1
    let ownerPidMatch = pidSet.contains(ownerPID)

    guard ownerPidMatch else { return nil }
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

window_number="$(printf '%s\n' "$window_number" | awk '/^[0-9]+$/ { value = $0 } END { print value }')"
if [[ -z "$window_number" ]]; then
  echo "Failed to resolve a visible layer-zero $APP_NAME window owned by PID $APP_PID." >&2
  exit 1
fi

capture_succeeded=0
for attempt in 1 2 3; do
  if screencapture -x -l "$window_number" "$output_path"; then
    capture_succeeded=1
    break
  fi
  sleep 0.4
done

if [[ "$capture_succeeded" != "1" ]]; then
  echo "Failed to capture $APP_NAME window $window_number after 3 attempts." >&2
  exit 1
fi

echo "$output_path"
