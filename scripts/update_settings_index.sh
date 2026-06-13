#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <output-path>"
  echo "Example: $0 dist/SettingsIndex.md"
  exit 1
fi
OUTPUT_PATH="$1"

cd "$ROOT_DIR"
swift run SettingsIndexTool \
  --validate-sources "$ROOT_DIR/Sources/MacWiki" \
  --output "$OUTPUT_PATH"
