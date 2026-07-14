#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BIN="${APP_BIN:-}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/main-window-lifecycle-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.qa/main-window-lifecycle}"
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"
BUILD_INFO_PLIST="$APP_BUNDLE_PATH/Contents/Resources/BuildInfo.plist"

# shellcheck source=scripts/lib/qa_process_safety.sh
source "$SCRIPT_DIR/lib/qa_process_safety.sh"

[[ -n "$APP_BIN" ]] || { echo "Set APP_BIN to a packaged candidate executable." >&2; exit 1; }
[[ -x "$APP_BIN" ]] || { echo "Candidate binary is not executable: $APP_BIN" >&2; exit 1; }
[[ -f "$INFO_PLIST" ]] || { echo "Candidate Info.plist is missing: $INFO_PLIST" >&2; exit 1; }
[[ -f "$BUILD_INFO_PLIST" ]] || { echo "Candidate BuildInfo.plist is missing: $BUILD_INFO_PLIST" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required for lifecycle evidence validation." >&2; exit 1; }

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
APP_LOG="$OUTPUT_DIR/app.log"
AX_RESULT="$OUTPUT_DIR/lifecycle-result.json"
REPORT_PATH="$OUTPUT_DIR/report.md"
rm -f "$APP_LOG" "$AX_RESULT" "$REPORT_PATH"

cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_no_conflicting_processes
AX_DRIVER_BIN="$QA_HOME/ax-main-window-lifecycle"
swiftc "$SCRIPT_DIR/ax_main_window_lifecycle.swift" -o "$AX_DRIVER_BIN"

qa_launch_candidate "$APP_LOG"
LIFECYCLE_PID="$QA_APP_PID"
qa_run_command_with_timeout 90 "$AX_DRIVER_BIN" \
  "$QA_APP_PID" "$APP_BUNDLE_PATH" 5 --audit-close >"$AX_RESULT"
kill -0 "$QA_APP_PID"

jq -e --argjson pid "$LIFECYCLE_PID" '
  .pid == $pid
  and .stableObservationSeconds >= 3
  and .stableSampleCount >= 30
  and .initialWindowCount == 1
  and .initialMainWindowCount == 1
  and .initialToolbarCount == 0
  and .finalWindowCount == 1
  and .finalMainWindowCount == 1
  and .finalToolbarCount == 0
  and .closeAudit.residencyObservationSeconds >= 2
  and .closeAudit.processTerminatedAfterClose == false
  and .closeAudit.processResidentAfterClose == true
  and .closeAudit.windowCountAfterClose == 0
  and .closeAudit.reopenedSamePID == true
  and .closeAudit.reopenedWindowCount == 1
  and .closeAudit.reopenedMainWindowCount == 1
  and .closeAudit.reopenedToolbarCount == 0
  and .closeAudit.reopenedFramePreserved == true
  and (.cycles | length) == 5
  and all(.cycles[];
    .pid == $pid
    and .sameWindowIdentity == true
    and .framePreserved == true
    and .totalWindowCount == 1
    and .mainWindowCount == 1
    and .toolbarCount == 0
    and .minimizeLatencyMilliseconds >= 0
    and .reopenLatencyMilliseconds >= 0
  )
' "$AX_RESULT" >/dev/null

qa_stop_exact

if rg -n -i \
  "fatal error|precondition failed|assertion failed|AttributeGraph: cycle detected|EXC_BAD_ACCESS|EXC_CRASH|SIGABRT|Abort trap|Segmentation fault|uncaught exception" \
  "$APP_LOG"; then
  echo "Main-window lifecycle emitted a fatal runtime diagnostic." >&2
  exit 1
fi

MAX_MINIMIZE_LATENCY="$(jq -r '[.cycles[].minimizeLatencyMilliseconds] | max' "$AX_RESULT")"
MAX_REOPEN_LATENCY="$(jq -r '[.cycles[].reopenLatencyMilliseconds] | max' "$AX_RESULT")"

{
  printf '# Native Main-Window Lifecycle\n\n'
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
  printf -- '- Exact lifecycle PID: `%s`\n' "$LIFECYCLE_PID"
  printf -- '- Isolated QA home: `%s`\n' "$QA_HOME"
  printf -- '- Cold launch: one main window remained stable for more than three seconds with reader toolbar chrome absent outside article view\n'
  printf -- '- Native lifecycle: five minimize and LaunchServices reopen cycles retained the same PID, AX window identity, frame, and article-only toolbar state\n'
  printf -- '- Red close: the app remained resident without windows for 2.5 seconds, then LaunchServices recreated one native main window in the same PID and frame\n'
  printf -- '- Maximum minimize latency: `%s ms`\n' "$MAX_MINIMIZE_LATENCY"
  printf -- '- Maximum reopen latency: `%s ms`\n' "$MAX_REOPEN_LATENCY"
  printf -- '- AX evidence: `%s`\n' "$AX_RESULT"
  printf -- '- Fatal-diagnostic scan: **PASS**\n'
  printf -- '- Global input injection: **None** — the driver uses bounded AXPress and LaunchServices actions only.\n'
  printf -- '- Production preferences/data touched: **No** — state, defaults, persistence, and caches were isolated.\n'
} >"$REPORT_PATH"

echo "Native main-window lifecycle passed: $REPORT_PATH"
