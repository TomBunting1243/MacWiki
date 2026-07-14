#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/toolbar-customization-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/toolbar-customization}"
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"
BUILD_INFO_PLIST="$APP_BUNDLE_PATH/Contents/Resources/BuildInfo.plist"

# shellcheck source=scripts/lib/qa_process_safety.sh
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

[[ -n "$APP_BIN" ]] || { echo "Set APP_BIN to a packaged candidate executable." >&2; exit 1; }
[[ -x "$APP_BIN" ]] || { echo "Candidate binary is not executable: $APP_BIN" >&2; exit 1; }
[[ -f "$INFO_PLIST" ]] || { echo "Candidate Info.plist is missing: $INFO_PLIST" >&2; exit 1; }
[[ -f "$BUILD_INFO_PLIST" ]] || { echo "Candidate BuildInfo.plist is missing: $BUILD_INFO_PLIST" >&2; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
TRACE_VERSION="$(plutil -extract Version raw "$BUILD_INFO_PLIST")"
TRACE_BUILD="$(plutil -extract BuildNumber raw "$BUILD_INFO_PLIST")"
TRACE_COMMIT="$(plutil -extract GitCommit raw "$BUILD_INFO_PLIST")"
TRACE_DIRTY="$(plutil -extract GitDirty raw "$BUILD_INFO_PLIST")"

[[ "$VERSION" == 1.0* ]] || { echo "Candidate is not on the 1.0 line: $VERSION" >&2; exit 1; }
[[ "$TRACE_VERSION" == "$VERSION" ]] || { echo "BuildInfo version does not match Info.plist" >&2; exit 1; }
[[ "$TRACE_BUILD" == "$BUILD" ]] || { echo "BuildInfo build does not match Info.plist" >&2; exit 1; }
[[ "$TRACE_DIRTY" == "false" ]] || { echo "BuildInfo says candidate source was dirty" >&2; exit 1; }
[[ "$TRACE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "BuildInfo commit is invalid" >&2; exit 1; }
qa_assert_candidate_manifest_matches_executable "$BUILD_INFO_PLIST"

mkdir -p "$OUTPUT_DIR"
FIRST_LOG="$OUTPUT_DIR/first-launch.log"
RELAUNCH_LOG="$OUTPUT_DIR/relaunch.log"
FIRST_RESULT="$OUTPUT_DIR/customize-result.txt"
RELAUNCH_RESULT="$OUTPUT_DIR/relaunch-result.txt"
IDENTIFIERS_RESULT="$OUTPUT_DIR/persisted-identifiers.txt"
REPORT_PATH="$OUTPUT_DIR/report.md"
rm -f "$FIRST_LOG" "$RELAUNCH_LOG" "$FIRST_RESULT" "$RELAUNCH_RESULT" \
  "$IDENTIFIERS_RESULT" "$REPORT_PATH"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_no_conflicting_processes
AX_DRIVER_BIN="$QA_HOME/ax-toolbar-customization-journey"
swiftc "$SCRIPT_DIR/ax_toolbar_customization_journey.swift" -o "$AX_DRIVER_BIN"

qa_launch_candidate "$FIRST_LOG"
FIRST_PID="$QA_APP_PID"
qa_run_command_with_timeout 90 "$AX_DRIVER_BIN" \
  "$QA_APP_PID" | tee "$FIRST_RESULT"
kill -0 "$QA_APP_PID"
qa_stop_exact

qa_launch_candidate "$RELAUNCH_LOG"
RELAUNCH_PID="$QA_APP_PID"
qa_run_command_with_timeout 30 "$AX_DRIVER_BIN" \
  "$QA_APP_PID" verify-order | tee "$RELAUNCH_RESULT"
kill -0 "$QA_APP_PID"

defaults read "$QA_DEFAULTS_SUITE" \
  "NSToolbar Configuration main-window-reader-scoped-toolbar-v15" >"$IDENTIFIERS_RESULT"
STYLE_LINE="$(rg -n '"reader\.style"' "$IDENTIFIERS_RESULT" | head -n 1 | cut -d: -f1)"
PAGE_VIEWS_LINE="$(rg -n '"reader\.page-views"' "$IDENTIFIERS_RESULT" | head -n 1 | cut -d: -f1)"
[[ "$STYLE_LINE" =~ ^[0-9]+$ && "$PAGE_VIEWS_LINE" =~ ^[0-9]+$ \
  && "$STYLE_LINE" -lt "$PAGE_VIEWS_LINE" ]] || {
  echo "Persisted native toolbar order does not place Reader Style before Page Views." >&2
  exit 1
}
qa_stop_exact

if rg -n "fatal error|precondition failed|assertion failed|AttributeGraph: cycle detected" \
  "$FIRST_LOG" "$RELAUNCH_LOG"; then
  echo "Toolbar customization journey emitted a fatal runtime diagnostic." >&2
  exit 1
fi

{
  printf '# Native Toolbar Customization Journey\n\n'
  printf -- '- Result: **PASS**\n'
  printf -- '- Candidate binary: `%s`\n' "$APP_BIN"
  printf -- '- Version/build: `%s (%s)`\n' "$VERSION" "$BUILD"
  printf -- '- BuildInfo commit: `%s`\n' "$TRACE_COMMIT"
  printf -- '- BuildInfo dirty: `%s`\n' "$TRACE_DIRTY"
  printf -- '- Package manifest: `%s`\n' "$QA_PACKAGE_MANIFEST_PATH"
  printf -- '- Packaged executable SHA-256: `%s`\n' "$QA_PACKAGED_EXECUTABLE_SHA256"
  printf -- '- App tree SHA-256: `%s`\n' "$QA_APP_TREE_SHA256"
  printf -- '- Toolchain: `%s`; Mach-O minOS/SDK: `%s / %s`\n' \
    "$QA_XCODE_VERSION" "$QA_BINARY_MIN_OS" "$QA_BINARY_SDK"
  printf -- '- First-launch exact PID: `%s`\n' "$FIRST_PID"
  printf -- '- Relaunch exact PID: `%s`\n' "$RELAUNCH_PID"
  printf -- '- Isolated QA home: `%s`\n' "$QA_HOME"
  printf -- '- Native journey: removed Reader Style, restored it before Page Views, rejected a cross-boundary move, kept Inspector fixed, committed Done, quit, and relaunched\n'
  printf -- '- Persistence assertion: customized Reader Style-before-Page Views order survived relaunch inside the reader zone\n'
  printf -- '- Persisted identifier evidence: `%s`\n' "$IDENTIFIERS_RESULT"
  printf -- '- First-launch AX evidence: `%s`\n' "$FIRST_RESULT"
  printf -- '- Relaunch AX evidence: `%s`\n' "$RELAUNCH_RESULT"
  printf -- '- Production preferences/data touched: **No** — state, defaults, persistence, and caches were isolated.\n'
} >"$REPORT_PATH"

echo "Toolbar customization journey passed: $REPORT_PATH"
