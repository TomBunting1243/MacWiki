#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN_DEFAULT="$REPO_ROOT/.build/arm64-apple-macosx/debug/MacWiki"
APP_BIN_FALLBACK="$REPO_ROOT/.build/debug/MacWiki"
APP_BIN="${APP_BIN:-$APP_BIN_DEFAULT}"

if [[ ! -x "$APP_BIN" && -x "$APP_BIN_FALLBACK" ]]; then
  APP_BIN="$APP_BIN_FALLBACK"
fi
OUTPUT_DIR="${1:-/tmp/macwiki-qa/discover-$(date +%Y%m%d_%H%M%S)}"
DATE_LIST_CSV="${DATE_LIST_CSV:-2026-02-24,2025-12-25,2025-07-04,2024-02-29}"
USER_AGENT="${USER_AGENT:-MacWiki/1.0 (https://github.com/tombunting/MacWiki)}"
FORCE_FRESH_LAUNCH="${FORCE_FRESH_LAUNCH:-1}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/discover-home-$(date +%Y%m%d_%H%M%S)-$RANDOM}"

mkdir -p "$OUTPUT_DIR"
qa_prepare_isolated_home
cleanup() {
  qa_stop_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

echo "Output: $OUTPUT_DIR"

prepare_deterministic_launch() {
  qa_assert_no_conflicting_processes
}

find_macwiki_window_bounds() {
  MACWIKI_QA_PID="${QA_APP_PID:-}" swift - <<'SWIFT'
import CoreGraphics
import Foundation

let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let targetPid = Int(ProcessInfo.processInfo.environment["MACWIKI_QA_PID"] ?? "") ?? -1
let ownerKey = kCGWindowOwnerName as String
let pidKey = kCGWindowOwnerPID as String
let layerKey = kCGWindowLayer as String
let boundsKey = kCGWindowBounds as String

var bestPid = -1
var bestArea = -1.0
var bestBounds: [String: Double] = [:]

for w in windows {
    guard ((w[pidKey] as? Int) ?? -1) == targetPid else { continue }
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

    sleep 1
    attempts=$((attempts + 1))
  done

  echo "ERROR: Could not find an on-screen $APP_NAME window." >&2
  exit 1
}

select_discover_via_accessibility() {
  qa_run_command_with_timeout 30 swift "$SCRIPT_DIR/ax_select_sidebar_root.swift" \
    "$QA_APP_PID" Discover
}

verify_discover_via_accessibility() {
  qa_run_command_with_timeout 40 swift "$SCRIPT_DIR/ax_discover_surface_probe.swift" \
    "$QA_APP_PID"
}

prepare_deterministic_launch

if [[ ! -x "$APP_BIN" ]]; then
  echo "ERROR: App binary not found: $APP_BIN" >&2
  exit 1
fi
echo "Launching isolated $APP_NAME from $APP_BIN" >&2
qa_launch_candidate "/tmp/macwiki-qa-discover-launch.log"
window_info="$(ensure_macwiki_window)"
if [[ ! "$window_info" =~ ^-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]]; then
  echo "ERROR: Unexpected window bounds payload: $window_info" >&2
  exit 1
fi
IFS=',' read -r window_pid window_x window_y window_w window_h <<<"$window_info"
echo "Detected MacWiki window pid=$window_pid frame=($window_x,$window_y $window_w x $window_h)"

discover_selected="false"
discover_process_survived="false"
ax_selection_output=""
if ax_selection_output="$(select_discover_via_accessibility 2>&1)"; then
  discover_selected="true"
  sleep 1
  if kill -0 "$QA_APP_PID" 2>/dev/null; then
    discover_process_survived="true"
  fi
fi
printf '%s\n' "$ax_selection_output" >"$OUTPUT_DIR/01-ax-selection.txt"

time_machine_found="false"
ax_verification_output=""
if [[ "$discover_process_survived" == "true" ]] && ax_verification_output="$(verify_discover_via_accessibility 2>&1)"; then
  time_machine_found="true"
fi
printf '%s\n' "$ax_verification_output" >"$OUTPUT_DIR/02-ax-discover-time-machine.txt"

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

qa_status="PASS"
if [[ "$discover_selected" != "true" || "$discover_process_survived" != "true" || "$time_machine_found" != "true" ]]; then
  qa_status="FAIL"
fi

report_path="$OUTPUT_DIR/report.md"
{
  echo "# Discover QA Report"
  echo
  echo "- Status: **$qa_status**"
  echo "- Captured: $(date)"
  echo "- MacWiki window pid: \`$window_pid\`"
  echo "- App binary: \`$APP_BIN\`"
  echo "- Window frame: \`x=$window_x y=$window_y w=$window_w h=$window_h\`"
  echo "- Isolated defaults suite: \`$QA_DEFAULTS_SUITE\`"
  echo "- Discover route: full editorial reader page with optional companion pane"
  echo "- Forced fresh launch: \`$FORCE_FRESH_LAUNCH\`"
  echo
  echo "## Before/After"
  echo
  echo "- Before (reported): Discover smart list scroll felt jerky, and Time Machine was not working."
  echo "- After (this QA run):"
  echo "  - Discover selected through exact-PID accessibility: \`$discover_selected\`"
  echo "  - Exact candidate process survived Discovery presentation: \`$discover_process_survived\`"
  echo "  - Discover surface and Time Machine semantics reached through accessibility scrolling: \`$time_machine_found\`"
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
  echo "- Discover selection AX log: \`$OUTPUT_DIR/01-ax-selection.txt\`"
  echo "- Discover/Time Machine AX log: \`$OUTPUT_DIR/02-ax-discover-time-machine.txt\`"
  echo "- Coverage CSV: \`$coverage_csv\`"
} >"$report_path"

echo "QA report: $report_path"
echo "$report_path"
if [[ "$qa_status" != "PASS" ]]; then
  echo "ERROR: Discover QA did not reach and verify both Discover and Time Machine UI." >&2
  exit 1
fi
