#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${1:-/Users/tombunting/Library/Mobile Documents/iCloud~md~obsidian/Documents/Jack/Projects/MacWiki/99 Reference/Settings Index.md}"

cd "$ROOT_DIR"
swift run SettingsIndexTool \
  --validate-sources "$ROOT_DIR/Sources/MacWiki" \
  --output "$OUTPUT_PATH"
