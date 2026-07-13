#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/pseudolocalization-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/pseudolocalization}"

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

export MACWIKI_QA_PSEUDOLOCALIZATION=1
qa_prepare_isolated_home
qa_assert_no_conflicting_processes
qa_launch_candidate "$OUTPUT_DIR/app.log"
sleep 2.0

APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" APP_PID="$QA_APP_PID" \
  "$SCRIPT_DIR/capture_macwiki_window.sh" "$OUTPUT_DIR/pseudolocalized.png" >/dev/null
"$SCRIPT_DIR/ocr_text.swift" "$OUTPUT_DIR/pseudolocalized.png" >"$OUTPUT_DIR/pseudolocalized.ocr.txt"

rg -q 'Welcome to MacWiki Welcome to MacWiki' "$OUTPUT_DIR/pseudolocalized.ocr.txt"
rg -q 'articles articles' "$OUTPUT_DIR/pseudolocalized.ocr.txt"

if rg -ni 'fatal error|precondition failed|assertion failed' "$OUTPUT_DIR/app.log" >"$OUTPUT_DIR/runtime-failures.txt"; then
  echo "Runtime diagnostics contained a fatal, assertion, or precondition failure." >&2
  exit 1
fi
: >"$OUTPUT_DIR/runtime-failures.txt"

qa_stop_exact
qa_remove_isolated_home
trap - EXIT INT TERM

WIDTH_OUTPUT="$OUTPUT_DIR/widths"
MACWIKI_QA_PSEUDOLOCALIZATION=1 \
STRICT_OCR=1 \
APP_NAME="$APP_NAME" \
APP_BIN="$APP_BIN" \
APP_BUNDLE_PATH="$APP_BUNDLE_PATH" \
"$SCRIPT_DIR/qa_sidebar_search_width_classes.sh" "$WIDTH_OUTPUT"

rg -q -- '- Warnings: 0' "$WIDTH_OUTPUT/report.md"
rg -q -- '- Hard failures: 0' "$WIDTH_OUTPUT/report.md"

{
  printf '# Pseudolocalization QA\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Native mode: `-NSDoubleLocalizedStrings YES` passed only to the isolated app process.\n'
  printf -- '- Expansion proof: OCR found doubled `Welcome to MacWiki` and article-count strings.\n'
  printf -- '- Width proof: pseudolocalized Search passed strict OCR at 1040, 1400, and 1760 px with zero warnings or hard failures.\n'
  printf -- '- Runtime failures: no fatal, assertion, or precondition messages.\n'
  printf -- '- Production preferences/data or global language settings touched: **No**.\n'
} >"$OUTPUT_DIR/report.md"

echo "Pseudolocalization QA passed: $OUTPUT_DIR/report.md"
