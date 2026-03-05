#!/usr/bin/env bash
set -euo pipefail

LOG_PATH="${LOG_PATH:-/tmp/macwiki-run.log}"

swift build

# Launch in background and capture logs
./.build/debug/MacWiki >"$LOG_PATH" 2>&1 &
PID=$!

echo "MacWiki started (pid $PID). Logs: $LOG_PATH"

if [[ "${TAIL_LOGS:-}" == "1" ]]; then
  tail -n 200 -f "$LOG_PATH"
fi


