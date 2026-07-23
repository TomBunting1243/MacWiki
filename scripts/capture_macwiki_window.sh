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
if [[ -n "$actual_binary" && -e "$actual_binary" ]]; then
  actual_binary="$(cd "$(dirname "$actual_binary")" && pwd -P)/$(basename "$actual_binary")"
fi
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
resolve_window_number() {
  local resolved
  resolved="$(
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

let candidates: [(number: Int, area: Double, bounds: CGRect)] = windowInfo.compactMap { window in
    let ownerPID = window[pidKey] as? Int ?? -1
    let ownerPidMatch = pidSet.contains(ownerPID)

    guard ownerPidMatch else { return nil }
    guard (window[layerKey] as? Int ?? 1) == 0 else { return nil }
    let alpha = window[alphaKey] as? Double ?? 1
    guard alpha > 0 else { return nil }
    guard let number = window[numberKey] as? Int else { return nil }
    guard let bounds = window[boundsKey] as? [String: Any],
          let x = bounds["X"] as? NSNumber,
          let y = bounds["Y"] as? NSNumber,
          let width = bounds["Width"] as? NSNumber,
          let height = bounds["Height"] as? NSNumber else {
        return nil
    }
    let rect = CGRect(
        x: x.doubleValue,
        y: y.doubleValue,
        width: width.doubleValue,
        height: height.doubleValue
    )
    return (number: number, area: rect.width * rect.height, bounds: rect)
}

if let chosen = candidates.max(by: { $0.area < $1.area }) {
    guard let targetIndex = windowInfo.firstIndex(where: {
        ($0[numberKey] as? Int) == chosen.number
    }) else {
        exit(1)
    }
    let hasOccludingLayerZeroWindow = windowInfo[..<targetIndex].contains { window in
        guard (window[layerKey] as? Int ?? 1) == 0,
              (window[alphaKey] as? Double ?? 1) > 0,
              let number = window[numberKey] as? Int,
              number != chosen.number,
              let bounds = window[boundsKey] as? [String: Any],
              let x = bounds["X"] as? NSNumber,
              let y = bounds["Y"] as? NSNumber,
              let width = bounds["Width"] as? NSNumber,
              let height = bounds["Height"] as? NSNumber else {
            return false
        }
        let rect = CGRect(
            x: x.doubleValue,
            y: y.doubleValue,
            width: width.doubleValue,
            height: height.doubleValue
        )
        return rect.intersects(chosen.bounds)
    }
    print([
        String(chosen.number),
        String(Int(chosen.bounds.minX.rounded())),
        String(Int(chosen.bounds.minY.rounded())),
        String(Int(chosen.bounds.width.rounded())),
        String(Int(chosen.bounds.height.rounded())),
        hasOccludingLayerZeroWindow ? "1" : "0"
    ].joined(separator: ","))
}
SWIFT
)"
  printf '%s\n' "$resolved" | awk '/^[0-9]+,-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+,[01]$/ { value = $0 } END { print value }'
}

run_screencapture_with_timeout() {
  screencapture "$@" &
  local capture_pid=$!
  local elapsed_ticks=0
  while kill -0 "$capture_pid" 2>/dev/null; do
    if (( elapsed_ticks >= 15 )); then
      kill "$capture_pid" 2>/dev/null || true
      wait "$capture_pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.1
    elapsed_ticks=$((elapsed_ticks + 1))
  done
  wait "$capture_pid"
}

capture_succeeded=0
for attempt in 1 2 3; do
  window_number=""
  window_x=""
  window_y=""
  window_width=""
  window_height=""
  window_occluded=""
  capture_target="$(resolve_window_number)"
  if [[ -n "$capture_target" ]]; then
    IFS=',' read -r window_number window_x window_y window_width window_height window_occluded <<<"$capture_target"
  fi
  if [[ -n "$window_number" ]] && run_screencapture_with_timeout -x -l "$window_number" "$output_path" 2>/dev/null; then
    capture_succeeded=1
    break
  fi
  if [[ -n "$window_number" && "$window_occluded" == "0" ]] \
    && run_screencapture_with_timeout -x -R"$window_x,$window_y,$window_width,$window_height" "$output_path" 2>/dev/null; then
    capture_succeeded=1
    break
  fi
  osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "System Events"
  if exists (first process whose unix id is $macwiki_pid) then
    set frontmost of first process whose unix id is $macwiki_pid to true
  end if
end tell
APPLESCRIPT
  sleep 0.4
done

if [[ "$capture_succeeded" != "1" ]]; then
  echo "Failed to capture $APP_NAME window ${window_number:-<unresolved>} after 3 attempts." >&2
  exit 1
fi

echo "$output_path"
