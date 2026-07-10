#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
capture_window_script="$script_dir/capture_macwiki_window.sh"
repo_root="$(cd "$script_dir/.." && pwd)"
REPO_ROOT="$repo_root"
source "$script_dir/lib/qa_process_safety.sh"
APP_NAME="${APP_NAME:-MacWiki}"
app_binary_default="$repo_root/.build/arm64-apple-macosx/debug/MacWiki"
app_binary_fallback="$repo_root/.build/debug/MacWiki"
APP_BIN="${APP_BIN:-$app_binary_default}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/audit-capture-home-$(date +%Y%m%d_%H%M%S)-$RANDOM}"

if [[ ! -x "$APP_BIN" && -x "$app_binary_fallback" ]]; then
  APP_BIN="$app_binary_fallback"
fi

if [[ ! -x "$capture_window_script" ]]; then
  echo "Missing required capture script: $capture_window_script" >&2
  exit 1
fi

raise_macwiki_window() {
  osascript - "$QA_APP_PID" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  set appPid to item 1 of argv as integer
tell application "System Events"
  if exists (first process whose unix id is appPid) then
    set frontmost of first process whose unix id is appPid to true
  end if
end tell
end run
APPLESCRIPT
}

capture_with_retry() {
  local destination="$1"

  if APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" APP_PID="$QA_APP_PID" "$capture_window_script" "$destination" >/dev/null 2>&1; then
    return 0
  fi

  raise_macwiki_window
  sleep 1

  if APP_NAME="$APP_NAME" APP_BIN="$APP_BIN" APP_PID="$QA_APP_PID" "$capture_window_script" "$destination" >/dev/null 2>&1; then
    return 0
  fi
  echo "ERROR: Failed to capture the verified MacWiki PID $QA_APP_PID." >&2
  return 1
}

output_dir="${1:-/tmp/macwiki-audit/set-$(date +%Y%m%d_%H%M%S)}"
prep_delay="${MACWIKI_AUDIT_PREP_DELAY:-4}"
states_csv="${MACWIKI_AUDIT_STATES:-home,discover,article,article_inspector,focus_toc,settings}"

mkdir -p "$output_dir"
mkdir -p /tmp/macwiki-audit
qa_prepare_isolated_home
cleanup() {
  qa_stop_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM
qa_launch_exact "/tmp/macwiki-audit/macwiki-audit-launch.log"
sleep 1.2
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
