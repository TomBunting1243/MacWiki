#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN_DEFAULT="$REPO_ROOT/.build/arm64-apple-macosx/debug/MacWiki"
APP_BIN_FALLBACK="$REPO_ROOT/.build/debug/MacWiki"
APP_BIN="${APP_BIN:-$APP_BIN_DEFAULT}"

if [[ ! -x "$APP_BIN" && -x "$APP_BIN_FALLBACK" ]]; then
  APP_BIN="$APP_BIN_FALLBACK"
fi
OUTPUT_DIR="${1:-/tmp/macwiki-qa/discover-$(date +%Y%m%d_%H%M%S)}"
DATE_LIST_CSV="${DATE_LIST_CSV:-2026-02-24,2025-12-25,2025-07-04,2024-02-29}"
USER_AGENT="${USER_AGENT:-MacWiki/1.0 (contact@example.com)}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.tombunting.MacWiki}"
DISCOVER_OPEN_MODE="${DISCOVER_OPEN_MODE:-Sidebar}"
FORCE_FRESH_LAUNCH="${FORCE_FRESH_LAUNCH:-1}"

mkdir -p "$OUTPUT_DIR"

capture_script="$SCRIPT_DIR/capture_macwiki_window.sh"
click_script="$SCRIPT_DIR/cg_click.swift"
scroll_script="$SCRIPT_DIR/cg_scroll.swift"
ocr_script="$SCRIPT_DIR/ocr_text.swift"
ocr_centers_script="$SCRIPT_DIR/ocr_find_text_centers.swift"

if [[ ! -x "$capture_script" ]]; then
  echo "ERROR: Missing executable capture script: $capture_script" >&2
  exit 1
fi

if [[ ! -x "$click_script" ]]; then
  chmod +x "$click_script"
fi
if [[ ! -x "$scroll_script" ]]; then
  chmod +x "$scroll_script"
fi
if [[ ! -x "$ocr_script" ]]; then
  chmod +x "$ocr_script"
fi
if [[ ! -x "$ocr_centers_script" ]]; then
  chmod +x "$ocr_centers_script"
fi

echo "Output: $OUTPUT_DIR"

prepare_deterministic_launch() {
  defaults write "$APP_BUNDLE_ID" discoverOpenMode -string "$DISCOVER_OPEN_MODE" >/dev/null 2>&1 || true
  if [[ "$FORCE_FRESH_LAUNCH" == "1" ]]; then
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    sleep 0.6
  fi
}

find_macwiki_window_bounds() {
  MACWIKI_QA_APP_NAME="$APP_NAME" swift - <<'SWIFT'
import CoreGraphics
import Foundation

let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let appName = ProcessInfo.processInfo.environment["MACWIKI_QA_APP_NAME"] ?? "MacWiki"
let ownerKey = kCGWindowOwnerName as String
let pidKey = kCGWindowOwnerPID as String
let layerKey = kCGWindowLayer as String
let boundsKey = kCGWindowBounds as String

var bestPid = -1
var bestArea = -1.0
var bestBounds: [String: Double] = [:]

for w in windows {
    let owner = (w[ownerKey] as? String) ?? ""
    guard owner.localizedCaseInsensitiveContains(appName) else { continue }
    guard ((w[layerKey] as? Int) ?? 1) == 0 else { continue }
    let boundsAny = (w[boundsKey] as? [String: Any]) ?? [:]
    let x = (boundsAny["X"] as? Double) ?? 0
    let y = (boundsAny["Y"] as? Double) ?? 0
    let width = (boundsAny["Width"] as? Double) ?? 0
    let height = (boundsAny["Height"] as? Double) ?? 0
    let area = width * height
    if area > bestArea {
        bestArea = area
        bestPid = (w[pidKey] as? Int) ?? -1
        bestBounds = ["x": x, "y": y, "width": width, "height": height]
    }
}

if bestPid > 0, let x = bestBounds["x"], let y = bestBounds["y"], let width = bestBounds["width"], let height = bestBounds["height"] {
    print("\(bestPid),\(Int(x)),\(Int(y)),\(Int(width)),\(Int(height))")
}
SWIFT
}

ensure_macwiki_window() {
  local attempts=0
  local window_info=""

  while (( attempts < 12 )); do
    window_info="$(find_macwiki_window_bounds || true)"
    if [[ -n "$window_info" ]]; then
      echo "$window_info"
      return 0
    fi

    if (( attempts == 0 )); then
      if [[ -x "$APP_BIN" ]]; then
        echo "Launching $APP_NAME from $APP_BIN" >&2
        open -n "$APP_BIN" >/tmp/macwiki-qa-discover-launch.log 2>&1 || true
      else
        echo "ERROR: App binary not found: $APP_BIN" >&2
        exit 1
      fi
    fi

    sleep 1
    attempts=$((attempts + 1))
  done

  echo "ERROR: Could not find an on-screen $APP_NAME window." >&2
  exit 1
}

activate_macwiki() {
  osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  tell application (item 1 of argv) to activate
end run
APPLESCRIPT
}

send_page_down() {
  osascript -e 'tell application "System Events" to key code 121' >/dev/null 2>&1 || true
}

capture_window() {
  local path="$1"
  APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" "$capture_script" "$path" >/dev/null
}

ocr_image_to_file() {
  local image_path="$1"
  local text_path="$2"
  "$ocr_script" "$image_path" >"$text_path" 2>/dev/null || true
}

image_dimensions() {
  local image_path="$1"
  local width
  local height
  width="$(sips -g pixelWidth "$image_path" 2>/dev/null | awk '/pixelWidth/ {print $2; exit}')"
  height="$(sips -g pixelHeight "$image_path" 2>/dev/null | awk '/pixelHeight/ {print $2; exit}')"
  if [[ ! "$width" =~ ^[0-9]+$ ]] || [[ ! "$height" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  echo "$width,$height"
}

map_image_point_to_window_point() {
  local image_x="$1"
  local image_y="$2"
  awk \
    -v image_x="$image_x" \
    -v image_y="$image_y" \
    -v image_w="$capture_image_w" \
    -v image_h="$capture_image_h" \
    -v window_x="$window_x" \
    -v window_y="$window_y" \
    -v window_w="$window_w" \
    -v window_h="$window_h" \
    'BEGIN {
      scale_x = image_w / window_w
      scale_y = image_h / window_h
      scale = (scale_x + scale_y) / 2.0
      if (scale <= 0) {
        exit 1
      }
      margin_x = (image_w - (window_w * scale)) / 2.0
      margin_y = (image_h - (window_h * scale)) / 2.0
      click_x = window_x + ((image_x - margin_x) / scale)
      click_y = window_y + ((image_y - margin_y) / scale)
      printf("%d,%d\n", int(click_x + 0.5), int(click_y + 0.5))
    }'
}

prepare_deterministic_launch
discover_mode_effective="$(defaults read "$APP_BUNDLE_ID" discoverOpenMode 2>/dev/null || true)"

window_info="$(ensure_macwiki_window)"
if [[ ! "$window_info" =~ ^-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]]; then
  echo "ERROR: Unexpected window bounds payload: $window_info" >&2
  exit 1
fi
IFS=',' read -r window_pid window_x window_y window_w window_h <<<"$window_info"
echo "Detected MacWiki window pid=$window_pid frame=($window_x,$window_y $window_w x $window_h)"

activate_macwiki
sleep 0.7

top_shot="$OUTPUT_DIR/01-before-click.png"
capture_window "$top_shot"
ocr_image_to_file "$top_shot" "$OUTPUT_DIR/01-before-click.ocr.txt"
capture_dimensions="$(image_dimensions "$top_shot" || true)"
if [[ "$capture_dimensions" =~ ^[0-9]+,[0-9]+$ ]]; then
  IFS=',' read -r capture_image_w capture_image_h <<<"$capture_dimensions"
else
  capture_image_w="$window_w"
  capture_image_h="$window_h"
fi

# Attempt to click Discover row area in sidebar.
discover_selected="false"
discover_click_shot=""
discover_centers="$("$ocr_centers_script" "$top_shot" "Discover" 2>/dev/null || true)"

if [[ -n "$discover_centers" ]]; then
  discover_click_index=0
  while IFS=',' read -r center_x center_y center_text; do
    [[ -z "${center_x:-}" || -z "${center_y:-}" ]] && continue
    discover_click_index=$((discover_click_index + 1))
    mapped_click="$(map_image_point_to_window_point "$center_x" "$center_y" || true)"
    if [[ "$mapped_click" =~ ^-?[0-9]+,-?[0-9]+$ ]]; then
      IFS=',' read -r click_x click_y <<<"$mapped_click"
    else
      click_x=$((window_x + center_x))
      click_y=$((window_y + center_y))
    fi
    "$click_script" --x "$click_x" --y "$click_y" --flip-y >/dev/null || true
    sleep 1.0

    shot="$OUTPUT_DIR/02-after-click-ocr-${discover_click_index}.png"
    capture_window "$shot"
    ocr_file="$OUTPUT_DIR/02-after-click-ocr-${discover_click_index}.ocr.txt"
    ocr_image_to_file "$shot" "$ocr_file"

    if rg -qi "Current events and historical anniversaries|Discover date|Loading discover feed|Discover unavailable|Featured Article|News Briefing|In the News|Most Read|This Day in History" "$ocr_file"; then
      discover_selected="true"
      discover_click_shot="$shot"
      break
    fi

    if (( discover_click_index >= 6 )); then
      break
    fi
  done <<< "$discover_centers"
fi

if [[ "$discover_selected" != "true" ]]; then
  # Fallback to fixed y offsets when OCR center extraction cannot target the row.
  for y_offset in 132 160 188 216 244; do
    click_x=$((window_x + 110))
    click_y=$((window_y + y_offset))
    "$click_script" --x "$click_x" --y "$click_y" --flip-y >/dev/null || true
    sleep 0.9

    shot="$OUTPUT_DIR/02-after-click-y${y_offset}.png"
    capture_window "$shot"
    ocr_file="$OUTPUT_DIR/02-after-click-y${y_offset}.ocr.txt"
    ocr_image_to_file "$shot" "$ocr_file"

    if rg -qi "Current events and historical anniversaries|Discover date|Loading discover feed|Discover unavailable|Featured Article|News Briefing|In the News|Most Read|This Day in History" "$ocr_file"; then
      discover_selected="true"
      discover_click_shot="$shot"
      break
    fi
  done
fi

scroll_anchor_x=$((window_x + 220))
scroll_anchor_y=$((window_y + (window_h / 2)))
scroll_mode="sidebar"

if [[ -n "$discover_click_shot" ]]; then
  discover_click_ocr="${discover_click_shot%.png}.ocr.txt"
  if [[ -f "$discover_click_ocr" ]]; then
    # If Discover opens in reader-page mode, scroll in the reader column.
    if rg -qi "New Tab|Featured|Most Read|In the News|News Briefing" "$discover_click_ocr"; then
      scroll_anchor_x=$((window_x + (window_w * 62 / 100)))
      scroll_mode="reader_page"
    fi
    # If Discover opens in sidebar mode, keep scrolling in directory column.
    if rg -qi "Current events and historical anniversaries|Discover date|Featured Article" "$discover_click_ocr"; then
      scroll_anchor_x=$((window_x + 220))
      scroll_mode="sidebar"
    fi
  fi
fi

time_machine_found="false"
time_machine_shot=""
latest_scroll_shot=""

for pass in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if [[ "$scroll_mode" == "reader_page" ]]; then
    "$click_script" --x "$scroll_anchor_x" --y "$scroll_anchor_y" --flip-y >/dev/null || true
    sleep 0.2
    send_page_down
  else
    # Negative delta scrolls down in this harness.
    "$scroll_script" --x "$scroll_anchor_x" --y "$scroll_anchor_y" --delta-y -8 --steps 36 --interval-ms 15 --flip-y >/dev/null || true
  fi
  sleep 0.7

  pass_shot="$OUTPUT_DIR/03-scroll-pass-${pass}.png"
  latest_scroll_shot="$pass_shot"
  capture_window "$pass_shot"
  pass_ocr="$OUTPUT_DIR/03-scroll-pass-${pass}.ocr.txt"
  ocr_image_to_file "$pass_shot" "$pass_ocr"

  if rg -qi "Time Machine|Born on This Day|Died on This Day|Holidays & Observances" "$pass_ocr"; then
    time_machine_found="true"
    time_machine_shot="$pass_shot"
    break
  fi
done

coverage_csv="$OUTPUT_DIR/time_machine_date_coverage.csv"
{
  echo "date,births,deaths,holidays,non_empty"
  IFS=',' read -r -a dates <<<"$DATE_LIST_CSV"
  for raw_date in "${dates[@]}"; do
    date_trimmed="$(echo "$raw_date" | xargs)"
    if [[ -z "$date_trimmed" ]]; then
      continue
    fi

    mmdd="$(date -j -f "%Y-%m-%d" "$date_trimmed" "+%m/%d" 2>/dev/null || true)"
    if [[ -z "$mmdd" ]]; then
      echo "$date_trimmed,ERR,ERR,ERR,false"
      continue
    fi

    endpoint="https://en.wikipedia.org/api/rest_v1/feed/onthisday/all/$mmdd"
    payload="$(curl -fsSL -H "User-Agent: $USER_AGENT" "$endpoint" 2>/dev/null || true)"
    if [[ -z "$payload" ]]; then
      echo "$date_trimmed,ERR,ERR,ERR,false"
      continue
    fi

    births="$(printf "%s" "$payload" | jq '.births | length' 2>/dev/null || echo "ERR")"
    deaths="$(printf "%s" "$payload" | jq '.deaths | length' 2>/dev/null || echo "ERR")"
    holidays="$(printf "%s" "$payload" | jq '.holidays | length' 2>/dev/null || echo "ERR")"

    non_empty="false"
    if [[ "$births" =~ ^[0-9]+$ ]] && [[ "$deaths" =~ ^[0-9]+$ ]] && [[ "$holidays" =~ ^[0-9]+$ ]]; then
      if (( births > 0 || deaths > 0 || holidays > 0 )); then
        non_empty="true"
      fi
    fi

    echo "$date_trimmed,$births,$deaths,$holidays,$non_empty"
  done
} >"$coverage_csv"

report_path="$OUTPUT_DIR/report.md"
{
  echo "# Discover QA Report"
  echo
  echo "- Captured: $(date)"
  echo "- MacWiki window pid: \`$window_pid\`"
  echo "- App binary: \`$APP_BIN\`"
  echo "- Window frame: \`x=$window_x y=$window_y w=$window_w h=$window_h\`"
  echo "- Defaults domain: \`$APP_BUNDLE_ID\`"
  echo "- Forced discoverOpenMode: \`$DISCOVER_OPEN_MODE\` (effective: \`${discover_mode_effective:-unknown}\`)"
  echo "- Forced fresh launch: \`$FORCE_FRESH_LAUNCH\`"
  echo
  echo "## Before/After"
  echo
  echo "- Before (reported): Discover smart list scroll felt jerky, and Time Machine was not working."
  echo "- After (this QA run):"
  echo "  - Discover selection detected by OCR: \`$discover_selected\`"
  if [[ -n "$discover_click_shot" ]]; then
    echo "  - Discover evidence screenshot: \`$discover_click_shot\`"
  else
    echo "  - Discover evidence screenshot: not confirmed by OCR in click attempts."
  fi
  echo "  - Time Machine heading detected after scroll by OCR: \`$time_machine_found\`"
  if [[ -n "$time_machine_shot" ]]; then
    echo "  - Time Machine evidence screenshot: \`$time_machine_shot\`"
  else
    echo "  - Time Machine evidence screenshot: not found in automated scroll passes."
  fi
  if [[ -n "$latest_scroll_shot" ]]; then
    echo "  - Last scroll screenshot: \`$latest_scroll_shot\`"
  fi
  echo
  echo "## Date Coverage (API)"
  echo
  echo "| Date | Births | Deaths | Holidays | Any Time Machine Data |"
  echo "|---|---:|---:|---:|---|"
  tail -n +2 "$coverage_csv" | while IFS=',' read -r d b de h non_empty; do
    echo "| $d | $b | $de | $h | $non_empty |"
  done
  echo
  echo "## Artifacts"
  echo
  echo "- Before click screenshot: \`$top_shot\`"
  echo "- Coverage CSV: \`$coverage_csv\`"
  echo "- OCR text files: \`$OUTPUT_DIR/*.ocr.txt\`"
} >"$report_path"

echo "QA report: $report_path"
echo "$report_path"
