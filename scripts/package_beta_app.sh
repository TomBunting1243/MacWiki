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
  swift build -c release
fi

BIN_DIR="$(swift build -c release --show-bin-path)"
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

GIT_COMMIT="unknown"
GIT_BRANCH="unknown"
GIT_DIRTY="unknown"
if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  GIT_BRANCH="$(git -C "$ROOT_DIR" branch --show-current)"
  if [[ -z "$GIT_BRANCH" ]]; then
    GIT_BRANCH="detached"
  fi
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
    GIT_DIRTY="true"
  else
    GIT_DIRTY="false"
  fi
fi
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
plist_add_string "$BUILD_INFO_PATH" "GitCommit" "$GIT_COMMIT"
plist_add_string "$BUILD_INFO_PATH" "GitBranch" "$GIT_BRANCH"
plist_add_string "$BUILD_INFO_PATH" "GitDirty" "$GIT_DIRTY"
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

if [[ "$ZIP_ENABLED" -eq 1 ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  spctl --assess --type execute -vv "$APP_PATH"
fi

echo "Packaged app:"
echo "  App: $APP_PATH"
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
if [[ "$ZIP_ENABLED" -eq 1 ]]; then
  echo "ZIP_PATH=$ZIP_PATH"
fi
