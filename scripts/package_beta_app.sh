#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/dist"
INFO_PLIST_SOURCE="$ROOT_DIR/Sources/MacWiki/Info.plist"
VERSION=""
BUILD_NUMBER=""
SIGN_IDENTITY="-"
SIGN_ENABLED=1
ZIP_ENABLED=1
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Package MacWiki as a distributable .app for beta testing.

Usage:
  ./scripts/package_beta_app.sh [options]

Options:
  --version <semver>          Override CFBundleShortVersionString (example: 0.1.0-beta.1)
  --build <number>            Override CFBundleVersion (example: 1)
  --identity <name>           Code signing identity (default: ad-hoc "-")
  --output-dir <path>         Output directory for .app/.zip (default: ./dist)
  --no-sign                   Skip codesign step
  --no-zip                    Skip zip archive creation
  --skip-build                Skip `swift build -c release`
  --help                      Show this help
EOF
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

chmod +x "$APP_PATH/Contents/MacOS/MacWiki"

if [[ "$SIGN_ENABLED" -eq 1 ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_PATH"
  else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
  fi
  codesign --verify --deep --strict "$APP_PATH"
fi

if [[ "$ZIP_ENABLED" -eq 1 ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
fi

echo "Packaged app:"
echo "  App: $APP_PATH"
if [[ "$ZIP_ENABLED" -eq 1 ]]; then
  echo "  Zip: $ZIP_PATH"
fi
if [[ "$SIGN_ENABLED" -eq 1 ]]; then
  echo "  Signed with: $SIGN_IDENTITY"
else
  echo "  Signing: skipped"
fi
