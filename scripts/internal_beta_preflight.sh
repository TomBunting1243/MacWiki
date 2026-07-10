#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RUN_PACKAGE=1
VERSION=""
BUILD_NUMBER=""
OUTPUT_DIR="$ROOT_DIR/dist"

usage() {
  cat <<'EOF'
Run the CLI-backed MacWiki internal-beta quality gates.

Usage:
  ./scripts/internal_beta_preflight.sh [options]

Options:
  --no-package        Run build/test/static gates without creating an app
  --version <value>   Package version override
  --build <number>    Package build-number override
  --output-dir <path> Package output directory (default: ./dist)
  --help              Show this help

This is a CLI fallback. Official Xcode 27 MCP evidence remains a separate final
sign-off requirement in INTERNAL_BETA_QUALITY_PROGRAM.md.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-package)
      RUN_PACKAGE=0
      shift
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for tool in git rg swift shasum otool; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

STATUS_OUTPUT="$(git status --porcelain --untracked-files=all)"
if [[ -n "$STATUS_OUTPUT" ]]; then
  echo "Internal-beta preflight requires a clean committed worktree:" >&2
  echo "$STATUS_OUTPUT" >&2
  exit 1
fi

SOURCE_COMMIT="$(git rev-parse HEAD)"
ARTIFACT_DIR="${CODEX_HOME:-$HOME/.codex}/artifacts/macwiki-internal-beta/$SOURCE_COMMIT"
mkdir -p "$ARTIFACT_DIR"

echo "[1/8] Debug build"
swift build 2>&1 | tee "$ARTIFACT_DIR/swift-build.log"

echo "[2/8] Complete automated suite"
swift test 2>&1 | tee "$ARTIFACT_DIR/swift-test.log"

echo "[3/8] Release build"
swift build -c release 2>&1 | tee "$ARTIFACT_DIR/swift-build-release.log"
BIN_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/MacWiki"
EXECUTABLE_SHA256="$(shasum -a 256 "$EXECUTABLE_PATH" | awk '{print $1}')"

echo "[4/8] Maintainability"
./scripts/check_maintainability.sh 2>&1 | tee "$ARTIFACT_DIR/maintainability.log"

echo "[5/8] Shell syntax"
for script in scripts/*.sh scripts/lib/*.sh; do
  bash -n "$script"
done

echo "[6/8] Redacted secret-pattern scan"
SECRET_PATTERN='(?i)(api[_-]?key|client[_-]?secret|bearer\s+[A-Za-z0-9._-]{16,}|(access|refresh|auth)[_-]?token\s*[:=]\s*["'\''][^"'\'']{8,}|password\s*[:=]\s*["'\''][^"'\'']+)'
if rg -l "$SECRET_PATTERN" Sources Tests scripts README.md Package.swift >"$ARTIFACT_DIR/secret-scan-files.log"; then
  echo "Potential secret-like values found; only filenames were recorded:" >&2
  sed 's/^/  - /' "$ARTIFACT_DIR/secret-scan-files.log" >&2
  exit 1
fi

echo "[7/8] Provenance"
if [[ "$(git rev-parse HEAD)" != "$SOURCE_COMMIT" || -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "Source changed while preflight was running." >&2
  exit 1
fi
printf 'SourceCommit=%s\nExecutableSHA256=%s\n' "$SOURCE_COMMIT" "$EXECUTABLE_SHA256" \
  >"$ARTIFACT_DIR/preflight-provenance.txt"

echo "[8/8] Ad-hoc internal package"
if [[ "$RUN_PACKAGE" -eq 1 ]]; then
  RESULT_FILE="$(mktemp /tmp/macwiki-internal-package-result.XXXXXX)"
  PACKAGE_ARGS=(
    --skip-build
    --expected-executable-sha256 "$EXECUTABLE_SHA256"
    --result-file "$RESULT_FILE"
    --output-dir "$OUTPUT_DIR"
    --ad-hoc-sign
  )
  if [[ -n "$VERSION" ]]; then PACKAGE_ARGS+=(--version "$VERSION"); fi
  if [[ -n "$BUILD_NUMBER" ]]; then PACKAGE_ARGS+=(--build "$BUILD_NUMBER"); fi

  ./scripts/package_beta_app.sh "${PACKAGE_ARGS[@]}"
  cp "$RESULT_FILE" "$ARTIFACT_DIR/package-result.txt"
  rm -f "$RESULT_FILE"
else
  echo "Packaging skipped."
fi

echo "Internal-beta CLI preflight passed for $SOURCE_COMMIT."
echo "Evidence: $ARTIFACT_DIR"
