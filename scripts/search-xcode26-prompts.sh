#!/usr/bin/env bash
set -euo pipefail

PROMPT_ROOT="${1:-.agent/references/xcode26-system-prompts}"
shift || true

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [prompt-root] <search pattern>"
  echo "Examples:"
  echo "  $0 .agent/references/xcode26-system-prompts toolbar"
  echo "  $0 .agent/references/xcode26-system-prompts liquid glass"
  exit 1
fi

if [[ ! -d "${PROMPT_ROOT}" ]]; then
  echo "Prompt root does not exist: ${PROMPT_ROOT}"
  echo "Run ./scripts/sync-xcode26-prompts.sh first."
  exit 1
fi

rg -n --no-heading --glob "*.idechatprompttemplate" --glob "AdditionalDocumentation/*.md" "$*" "${PROMPT_ROOT}"
