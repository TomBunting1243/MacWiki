#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/dist"
INFO_PLIST_SOURCE="$ROOT_DIR/Sources/MacWiki/Info.plist"
ENTITLEMENTS_SOURCE="$ROOT_DIR/Sources/MacWiki/MacWiki.entitlements"
VERSION=""
BUILD_NUMBER=""
SIGN_IDENTITY=""
SIGN_ENABLED=1
ZIP_ENABLED=1
SKIP_BUILD=0
AD_HOC_SIGN=0
NOTARY_PROFILE=""
EXPECTED_EXECUTABLE_SHA256=""
RESULT_FILE=""
MACWIKI_RELEASE_BUILD_ARGS=()

plist_add_string() {
  local plist_path="$1"
  local key="$2"
  local value="$3"
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist_path"
}

usage() {
  cat <<'EOF'
Package MacWiki as a distributable .app for beta testing.

Usage:
  ./scripts/package_beta_app.sh [options]

Options:
  --version <semver>          Override CFBundleShortVersionString (example: 0.1.0-beta.1)
  --build <number>            Override CFBundleVersion (example: 1)
  --identity <name>           Developer ID signing identity
  --ad-hoc-sign               Explicitly use ad-hoc signing for local/internal packages
  --notary-profile <name>     `notarytool` keychain profile for notarization
  --output-dir <path>         Output directory for .app/.zip (default: ./dist)
  --no-sign                   Skip codesign step
  --no-zip                    Skip zip archive creation
  --skip-build                Skip `swift build -c release`
  --expected-executable-sha256 <hash>
                              Required with --skip-build; proves the prebuilt executable
  --result-file <path>        Write exact APP_PATH/ZIP_PATH/MANIFEST_PATH outputs
  --help                      Show this help
EOF
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1"
    exit 1
  fi
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

binary_min_os() {
  otool -l "$1" | awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_block = 1; next }
    in_block && $1 == "minos" { print $2; exit }
  '
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

app_tree_sha256() {
  local app_path="$1"
  find -s "$app_path" -type f | while IFS= read -r file_path; do
    printf '%s\t%s\n' "${file_path#"$app_path"/}" "$(sha256_file "$file_path")"
  done | shasum -a 256 | awk '{print $1}'
}

require_clean_git_tree() {
  local status_output
  status_output="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)"
  if [[ -n "$status_output" ]]; then
    echo "Packaging requires a clean, committed source tree:" >&2
    echo "$status_output" >&2
    exit 1
  fi
}

verify_minimum_os_match() {
  local plist_path="$1"
  local binary_path="$2"
  local label="$3"
  local plist_min_os
  local binary_min_os_value

  plist_min_os="$(plist_value "$plist_path" "LSMinimumSystemVersion")"
  binary_min_os_value="$(binary_min_os "$binary_path")"

  if [[ -z "$binary_min_os_value" ]]; then
    echo "Unable to determine minimum macOS version from $label binary: $binary_path"
    exit 1
  fi

  if [[ "$plist_min_os" != "$binary_min_os_value" ]]; then
    echo "$label minimum macOS mismatch: plist advertises $plist_min_os but binary requires $binary_min_os_value"
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --identity)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    --ad-hoc-sign)
      AD_HOC_SIGN=1
      shift
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --no-sign)
      SIGN_ENABLED=0
      shift
      ;;
    --no-zip)
      ZIP_ENABLED=0
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --expected-executable-sha256)
      EXPECTED_EXECUTABLE_SHA256="${2:-}"
      shift 2
      ;;
    --result-file)
      RESULT_FILE="${2:-}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "$INFO_PLIST_SOURCE" ]]; then
  echo "Missing Info.plist source at $INFO_PLIST_SOURCE"
  exit 1
fi

require_tool swift
require_tool otool
require_tool shasum

if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Packaging requires a Git worktree for source provenance."
  exit 1
fi
require_clean_git_tree
SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
SOURCE_BRANCH="$(git -C "$ROOT_DIR" branch --show-current)"
if [[ -z "$SOURCE_BRANCH" ]]; then
  SOURCE_BRANCH="detached"
fi

if [[ "$SKIP_BUILD" -eq 1 && ! "$EXPECTED_EXECUTABLE_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "--skip-build requires --expected-executable-sha256 with a 64-character SHA-256."
  exit 1
fi

if [[ "$SIGN_ENABLED" -eq 0 ]]; then
  if [[ "$AD_HOC_SIGN" -eq 1 || -n "$SIGN_IDENTITY" || -n "$NOTARY_PROFILE" ]]; then
    echo "--no-sign cannot be combined with signing or notarization options."
    exit 1
  fi
else
  require_tool codesign

  if [[ "$AD_HOC_SIGN" -eq 1 && -n "$SIGN_IDENTITY" ]]; then
    echo "Choose either --identity or --ad-hoc-sign, not both."
    exit 1
  fi

  if [[ "$AD_HOC_SIGN" -eq 0 && -z "$SIGN_IDENTITY" ]]; then
    echo "Signing now requires an explicit choice: provide --identity, --ad-hoc-sign, or --no-sign."
    exit 1
  fi
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  require_tool xcrun
  require_tool spctl

  if [[ "$SIGN_ENABLED" -ne 1 ]]; then
    echo "Notarization requires signing to be enabled."
    exit 1
  fi

  if [[ "$AD_HOC_SIGN" -eq 1 ]]; then
    echo "Ad-hoc signed apps cannot be notarized."
    exit 1
  fi

  if [[ "$ZIP_ENABLED" -ne 1 ]]; then
    echo "Notarization requires zip creation. Remove --no-zip."
    exit 1
  fi
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  source "$ROOT_DIR/scripts/lib/release_build.sh"
  macwiki_release_build_args "$(plist_value "$INFO_PLIST_SOURCE" "LSMinimumSystemVersion")"
  swift build -c release "${MACWIKI_RELEASE_BUILD_ARGS[@]}"
fi

if [[ "$(git -C "$ROOT_DIR" rev-parse HEAD)" != "$SOURCE_COMMIT" ]]; then
  echo "Source commit changed during packaging."
  exit 1
fi
require_clean_git_tree

if [[ "$SKIP_BUILD" -eq 1 ]]; then
  BIN_DIR="$(swift build -c release --show-bin-path)"
else
  BIN_DIR="$(swift build -c release "${MACWIKI_RELEASE_BUILD_ARGS[@]}" --show-bin-path)"
fi
EXECUTABLE_PATH="$BIN_DIR/MacWiki"
RESOURCE_BUNDLE_PATH="$BIN_DIR/MacWiki_MacWiki.bundle"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Missing release executable at $EXECUTABLE_PATH"
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "Missing SwiftPM resource bundle at $RESOURCE_BUNDLE_PATH"
  exit 1
fi

SOURCE_EXECUTABLE_SHA256="$(sha256_file "$EXECUTABLE_PATH")"
EXPECTED_EXECUTABLE_SHA256_LOWER="$(printf '%s' "$EXPECTED_EXECUTABLE_SHA256" | tr '[:upper:]' '[:lower:]')"
if [[ "$SKIP_BUILD" -eq 1 && "$EXPECTED_EXECUTABLE_SHA256_LOWER" != "$SOURCE_EXECUTABLE_SHA256" ]]; then
  echo "Prebuilt executable hash mismatch."
  echo "  Expected: $EXPECTED_EXECUTABLE_SHA256_LOWER"
  echo "  Actual:   $SOURCE_EXECUTABLE_SHA256"
  exit 1
fi

verify_minimum_os_match "$INFO_PLIST_SOURCE" "$EXECUTABLE_PATH" "Built executable"

if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST_SOURCE")"
fi
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST_SOURCE")"
fi

mkdir -p "$OUTPUT_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
APP_BASENAME="MacWiki-${VERSION}-build${BUILD_NUMBER}-${STAMP}"
APP_PATH="$OUTPUT_DIR/$APP_BASENAME.app"
ZIP_PATH="$OUTPUT_DIR/$APP_BASENAME.zip"
BUILD_INFO_PATH="$APP_PATH/Contents/Resources/BuildInfo.plist"
MANIFEST_PATH="$OUTPUT_DIR/$APP_BASENAME.manifest.txt"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$EXECUTABLE_PATH" "$APP_PATH/Contents/MacOS/MacWiki"
cp -R "$RESOURCE_BUNDLE_PATH" "$APP_PATH/Contents/Resources/MacWiki_MacWiki.bundle"
cp "$INFO_PLIST_SOURCE" "$APP_PATH/Contents/Info.plist"

if [[ -f "$ROOT_DIR/Sources/MacWiki/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Sources/MacWiki/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi
if [[ -f "$ROOT_DIR/Sources/MacWiki/Resources/AppIcon.png" ]]; then
  cp "$ROOT_DIR/Sources/MacWiki/Resources/AppIcon.png" "$APP_PATH/Contents/Resources/AppIcon.png"
fi
if [[ -f "$ROOT_DIR/Sources/MacWiki/Resources/WebView.js" ]]; then
  cp "$ROOT_DIR/Sources/MacWiki/Resources/WebView.js" "$APP_PATH/Contents/Resources/WebView.js"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

XCODE_VERSION="unavailable"
if command -v xcodebuild >/dev/null 2>&1; then
  XCODE_VERSION="$(xcodebuild -version | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')"
fi
SWIFT_VERSION="$(swift --version 2>&1 | head -n 1)"

/usr/libexec/PlistBuddy -c "Clear dict" "$BUILD_INFO_PATH" >/dev/null 2>&1
plist_add_string "$BUILD_INFO_PATH" "AppName" "MacWiki"
plist_add_string "$BUILD_INFO_PATH" "Version" "$VERSION"
plist_add_string "$BUILD_INFO_PATH" "BuildNumber" "$BUILD_NUMBER"
plist_add_string "$BUILD_INFO_PATH" "PackageTimestampUTC" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
plist_add_string "$BUILD_INFO_PATH" "GitCommit" "$SOURCE_COMMIT"
plist_add_string "$BUILD_INFO_PATH" "GitBranch" "$SOURCE_BRANCH"
plist_add_string "$BUILD_INFO_PATH" "GitDirty" "false"
plist_add_string "$BUILD_INFO_PATH" "SourceExecutableSHA256" "$SOURCE_EXECUTABLE_SHA256"
plist_add_string "$BUILD_INFO_PATH" "XcodeVersion" "$XCODE_VERSION"
plist_add_string "$BUILD_INFO_PATH" "SwiftVersion" "$SWIFT_VERSION"

chmod +x "$APP_PATH/Contents/MacOS/MacWiki"
verify_minimum_os_match "$APP_PATH/Contents/Info.plist" "$APP_PATH/Contents/MacOS/MacWiki" "Packaged app"

if [[ "$SIGN_ENABLED" -eq 1 ]]; then
  codesign_args=(--force --deep)
  if [[ -f "$ENTITLEMENTS_SOURCE" ]]; then
    codesign_args+=(--entitlements "$ENTITLEMENTS_SOURCE")
  fi

  if [[ "$AD_HOC_SIGN" -eq 1 ]]; then
    codesign "${codesign_args[@]}" --sign - "$APP_PATH"
    SIGN_SUMMARY="ad-hoc"
  else
    codesign "${codesign_args[@]}" --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
    SIGN_SUMMARY="$SIGN_IDENTITY"
  fi
  codesign --verify --deep --strict "$APP_PATH"
else
  SIGN_SUMMARY="disabled"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  spctl --assess --type execute -vv "$APP_PATH"
  rm -f "$ZIP_PATH"
fi

PACKAGED_EXECUTABLE_SHA256="$(sha256_file "$APP_PATH/Contents/MacOS/MacWiki")"
APP_TREE_SHA256="$(app_tree_sha256 "$APP_PATH")"

if [[ "$ZIP_ENABLED" -eq 1 ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
  ZIP_SHA256="$(sha256_file "$ZIP_PATH")"
else
  ZIP_SHA256="disabled"
fi

{
  printf 'SourceCommit=%s\n' "$SOURCE_COMMIT"
  printf 'SourceBranch=%s\n' "$SOURCE_BRANCH"
  printf 'SourceDirty=false\n'
  printf 'SourceExecutableSHA256=%s\n' "$SOURCE_EXECUTABLE_SHA256"
  printf 'PackagedExecutableSHA256=%s\n' "$PACKAGED_EXECUTABLE_SHA256"
  printf 'AppTreeSHA256=%s\n' "$APP_TREE_SHA256"
  printf 'ZipSHA256=%s\n' "$ZIP_SHA256"
  printf 'AppPath=%s\n' "$APP_PATH"
  printf 'ZipPath=%s\n' "$([[ "$ZIP_ENABLED" -eq 1 ]] && printf '%s' "$ZIP_PATH" || printf 'disabled')"
  printf 'Signing=%s\n' "$SIGN_SUMMARY"
  printf 'NotaryProfile=%s\n' "${NOTARY_PROFILE:-disabled}"
} >"$MANIFEST_PATH"

if [[ -n "$RESULT_FILE" ]]; then
  mkdir -p "$(dirname "$RESULT_FILE")"
  {
    printf 'APP_PATH=%s\n' "$APP_PATH"
    printf 'ZIP_PATH=%s\n' "$([[ "$ZIP_ENABLED" -eq 1 ]] && printf '%s' "$ZIP_PATH" || printf '')"
    printf 'MANIFEST_PATH=%s\n' "$MANIFEST_PATH"
    printf 'SOURCE_COMMIT=%s\n' "$SOURCE_COMMIT"
    printf 'APP_TREE_SHA256=%s\n' "$APP_TREE_SHA256"
    printf 'ZIP_SHA256=%s\n' "$ZIP_SHA256"
  } >"$RESULT_FILE"
fi

echo "Packaged app:"
echo "  App: $APP_PATH"
echo "  Manifest: $MANIFEST_PATH"
if [[ "$ZIP_ENABLED" -eq 1 ]]; then
  echo "  Zip: $ZIP_PATH"
fi
if [[ "$SIGN_ENABLED" -eq 1 ]]; then
  echo "  Signed with: $SIGN_SUMMARY"
else
  echo "  Signing: skipped"
fi
if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "  Notarized with profile: $NOTARY_PROFILE"
else
  echo "  Notarization: skipped"
fi
echo "APP_PATH=$APP_PATH"
echo "MANIFEST_PATH=$MANIFEST_PATH"
if [[ "$ZIP_ENABLED" -eq 1 ]]; then
  echo "ZIP_PATH=$ZIP_PATH"
fi
