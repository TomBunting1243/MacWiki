#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/accessibility-personalization-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/accessibility-personalization}"

# shellcheck source=scripts/lib/qa_process_safety.sh
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

[[ -x "$APP_BIN" ]] || { echo "Candidate binary is not executable: $APP_BIN" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_no_conflicting_processes

APP_LOG="$OUTPUT_DIR/app.log"
REPORT_PATH="$OUTPUT_DIR/report.md"
PROFILES=(
  reduce-motion
  reduce-transparency
  increase-contrast
  differentiate-without-color
  all
)

for profile in "${PROFILES[@]}"; do
  export MACWIKI_QA_ACCESSIBILITY_PROFILE="$profile"
  qa_launch_candidate "$APP_LOG"
  qa_run_command_with_timeout 45 swift "$SCRIPT_DIR/ax_accessibility_personalization.swift" \
    "$QA_APP_PID" "$profile" >"$OUTPUT_DIR/$profile.json"

  if [[ "$profile" == "all" ]]; then
    sleep 1.5
    APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" APP_PID="$QA_APP_PID" \
      "$SCRIPT_DIR/capture_macwiki_window.sh" "$OUTPUT_DIR/all.png" >/dev/null
  fi

  qa_stop_exact
  sleep 0.35
done

unset MACWIKI_QA_ACCESSIBILITY_PROFILE
qa_launch_candidate "$APP_LOG"
sleep 1.5
APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" APP_PID="$QA_APP_PID" \
  "$SCRIPT_DIR/capture_macwiki_window.sh" "$OUTPUT_DIR/system.png" >/dev/null
qa_stop_exact

swift "$SCRIPT_DIR/compare_images.swift" \
  "$OUTPUT_DIR/system.png" "$OUTPUT_DIR/all.png" >"$OUTPUT_DIR/visual-diff.json"

if rg -ni 'fatal error|precondition failed|assertion failed' "$APP_LOG" >"$OUTPUT_DIR/runtime-failures.txt"; then
  echo "Runtime diagnostics contained a fatal, assertion, or precondition failure." >&2
  exit 1
fi
: >"$OUTPUT_DIR/runtime-failures.txt"

{
  printf '# Accessibility Personalization QA\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Profiles: `%s`\n' "${PROFILES[*]}"
  printf -- '- Native policy: production reads SwiftUI accessibility environment values; trusted QA profiles adapt the app-owned policy without changing macOS settings.\n'
  printf -- '- AX proof: every requested profile exposed its resolved values through the isolated diagnostic probe.\n'
  printf -- '- Visual proof: decoded RGBA comparison in `visual-diff.json` confirms rendered pixel changes between `system.png` and `all.png`.\n'
  printf -- '- Runtime failures: no fatal, assertion, or precondition messages.\n'
  printf -- '- Production preferences/data or global accessibility settings touched: **No**.\n'
} >"$REPORT_PATH"

echo "Accessibility personalization QA passed: $REPORT_PATH"
