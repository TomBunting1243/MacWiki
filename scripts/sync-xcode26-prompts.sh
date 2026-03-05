#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${1:-}"
DEST_PATH="${2:-.agent/references/xcode26-system-prompts}"

if [[ -z "${SOURCE_PATH}" ]]; then
  for candidate in \
    "/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources" \
    "/Applications/Xcode-beta.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources" \
    "/tmp/xcode-26-system-prompts"
  do
    if [[ -d "${candidate}" ]]; then
      SOURCE_PATH="${candidate}"
      break
    fi
  done
fi

if [[ -z "${SOURCE_PATH}" || ! -d "${SOURCE_PATH}" ]]; then
  echo "Could not find Xcode 26 prompt resources."
  echo "Usage: $0 <source-path> [destination-path]"
  echo "Example source path:"
  echo "  /Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources"
  exit 1
fi

mkdir -p "${DEST_PATH}"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --prune-empty-dirs \
    --include '*/' \
    --include '*.idechatprompttemplate' \
    --include '*.plist' \
    --include 'README.md' \
    --include 'AdditionalDocumentation/*.md' \
    --exclude '*' \
    "${SOURCE_PATH}/" "${DEST_PATH}/"
else
  rm -rf "${DEST_PATH:?}/"*
  find "${SOURCE_PATH}" -type f \
    \( -name "*.idechatprompttemplate" -o -name "*.plist" -o -name "README.md" -o -path "*/AdditionalDocumentation/*.md" \) \
    | while IFS= read -r file; do
        rel="${file#${SOURCE_PATH}/}"
        mkdir -p "${DEST_PATH}/$(dirname "${rel}")"
        cp "${file}" "${DEST_PATH}/${rel}"
      done
fi

echo "Synced Xcode 26 prompts from:"
echo "  ${SOURCE_PATH}"
echo "to:"
echo "  ${DEST_PATH}"
