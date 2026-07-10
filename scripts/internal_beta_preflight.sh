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

for tool in git rg swift shasum otool xcodebuild xcrun; do
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

CANONICAL_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Sources/MacWiki/Info.plist)"
if [[ "$CANONICAL_VERSION" != "1.0" ]]; then
  echo "Internal-beta preflight requires canonical MacWiki version 1.0, found: $CANONICAL_VERSION" >&2
  exit 1
fi
if [[ -n "$VERSION" && ! "$VERSION" =~ ^1\.0(-internal\.[0-9]+)?$ ]]; then
  echo "Internal-beta version must stay on the 1.0 line (1.0 or 1.0-internal.N): $VERSION" >&2
  exit 1
fi

SOURCE_COMMIT="$(git rev-parse HEAD)"
ARTIFACT_DIR="${CODEX_HOME:-$HOME/.codex}/artifacts/macwiki-internal-beta/$SOURCE_COMMIT"
mkdir -p "$ARTIFACT_DIR"

echo "[1/9] Xcode 27 toolchain and clean build state"
XCODE_VERSION="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [[ ! "$XCODE_VERSION" =~ ^27\. || ! "$SDK_VERSION" =~ ^27\. ]]; then
  echo "Internal-beta preflight requires Xcode 27 and macOS SDK 27; found Xcode $XCODE_VERSION / SDK $SDK_VERSION." >&2
  exit 1
fi
source "$ROOT_DIR/scripts/lib/release_build.sh"
macwiki_release_build_args "26.0"
swift package clean

echo "[2/9] Debug build"
swift build 2>&1 | tee "$ARTIFACT_DIR/swift-build.log"

echo "[3/9] Complete automated suite"
swift test 2>&1 | tee "$ARTIFACT_DIR/swift-test.log"

echo "[4/9] Release build"
swift build -c release "${MACWIKI_RELEASE_BUILD_ARGS[@]}" 2>&1 | tee "$ARTIFACT_DIR/swift-build-release.log"
BIN_DIR="$(swift build -c release "${MACWIKI_RELEASE_BUILD_ARGS[@]}" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/MacWiki"
EXECUTABLE_SHA256="$(shasum -a 256 "$EXECUTABLE_PATH" | awk '{print $1}')"
BUILD_VERSION_METADATA="$(otool -l "$EXECUTABLE_PATH" | awk '
  /cmd LC_BUILD_VERSION/ { in_build_version = 1; next }
  in_build_version && $1 == "minos" { print "MINOS=" $2 }
  in_build_version && $1 == "sdk" { print "SDK=" $2; exit }
')"
BINARY_MIN_OS="$(printf '%s\n' "$BUILD_VERSION_METADATA" | awk -F= '$1 == "MINOS" { print $2 }')"
BINARY_SDK="$(printf '%s\n' "$BUILD_VERSION_METADATA" | awk -F= '$1 == "SDK" { print $2 }')"
if [[ "$BINARY_MIN_OS" != "26.0" || ! "$BINARY_SDK" =~ ^27\. ]]; then
  echo "Release binary must declare minimum macOS 26.0 and SDK 27; found minos=$BINARY_MIN_OS sdk=$BINARY_SDK." >&2
  exit 1
fi

echo "[5/9] Maintainability"
./scripts/check_maintainability.sh 2>&1 | tee "$ARTIFACT_DIR/maintainability.log"

echo "[6/9] Shell syntax"
for script in scripts/*.sh scripts/lib/*.sh; do
  bash -n "$script"
done

echo "[7/9] Redacted secret-pattern scan"
SECRET_PATTERN='(?i)(api[_-]?key|client[_-]?secret|bearer\s+[A-Za-z0-9._-]{16,}|(access|refresh|auth)[_-]?token\s*[:=]\s*["'\''][^"'\'']{8,}|password\s*[:=]\s*["'\''][^"'\'']+)'
if rg -l "$SECRET_PATTERN" Sources Tests scripts README.md Package.swift >"$ARTIFACT_DIR/secret-scan-files.log"; then
  echo "Potential secret-like values found; only filenames were recorded:" >&2
  sed 's/^/  - /' "$ARTIFACT_DIR/secret-scan-files.log" >&2
  exit 1
fi

echo "[8/9] Provenance"
if [[ "$(git rev-parse HEAD)" != "$SOURCE_COMMIT" || -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "Source changed while preflight was running." >&2
  exit 1
fi
printf 'SourceCommit=%s\nXcodeVersion=%s\nSDKVersion=%s\nBinaryMinimumOS=%s\nBinarySDK=%s\nExecutableSHA256=%s\n' \
  "$SOURCE_COMMIT" "$XCODE_VERSION" "$SDK_VERSION" "$BINARY_MIN_OS" "$BINARY_SDK" "$EXECUTABLE_SHA256" \
  >"$ARTIFACT_DIR/preflight-provenance.txt"

echo "[9/9] Ad-hoc internal package"
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
