#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RUN_PACKAGING=1
SKIP_SECRET_SCAN=0
PACKAGE_VERSION=""
PACKAGE_BUILD=""
SIGN_IDENTITY=""
NOTARY_PROFILE=""
AD_HOC_SIGN=0
ALLOW_DIRTY=0

usage() {
  cat <<'EOF'
Run non-manual beta release preflight checks for MacWiki.

Usage:
  ./scripts/preflight_beta_release.sh [options]

Options:
  --no-package        Skip .app packaging
  --skip-secret-scan  Skip source secret-pattern scan
  --identity <name>   Developer ID signing identity for packaged public beta artifacts
  --notary-profile <name>
                      `notarytool` keychain profile used for notarization
  --ad-hoc-sign       Explicitly allow ad-hoc signing for local/internal packaging
  --allow-dirty       Skip the clean-git-tree enforcement (unsafe for public release)
  --version <tag>     Version passed to packaging (example: v0.5.0-beta.1)
  --build <number>    Build number passed to packaging (example: 1)
  --help              Show this help
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

package_min_os() {
  rg -o '\.macOS\(\.v[0-9]+\)' Package.swift | head -n 1 | sed -E 's/.*\.v([0-9]+)\).*/\1.0/'
}

readme_min_os() {
  awk '/^- macOS / { gsub(/\+/, "", $3); print $3; exit }' README.md
}

binary_min_os() {
  otool -l "$1" | awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_block = 1; next }
    in_block && $1 == "minos" { print $2; exit }
  '
}

ensure_clean_git_tree() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Git repo not initialized in this directory yet."
    return
  fi

  local status_output
  status_output="$(git status --porcelain --untracked-files=all)"
  if [[ -n "$status_output" ]]; then
    echo "Public beta preflight requires a clean git tree:"
    echo "$status_output"
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-package)
      RUN_PACKAGING=0
      shift
      ;;
    --skip-secret-scan)
      SKIP_SECRET_SCAN=1
      shift
      ;;
    --identity)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    --ad-hoc-sign)
      AD_HOC_SIGN=1
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --version)
      PACKAGE_VERSION="${2:-}"
      shift 2
      ;;
    --build)
      PACKAGE_BUILD="${2:-}"
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

require_tool swift
require_tool rg
require_tool otool

INFO_PLIST_PATH="Sources/MacWiki/Info.plist"
PLIST_MIN_OS="$(plist_value "$INFO_PLIST_PATH" "LSMinimumSystemVersion")"
PACKAGE_MIN_OS="$(package_min_os)"
README_MIN_OS="$(readme_min_os)"
EFFECTIVE_VERSION="${PACKAGE_VERSION:-$(plist_value "$INFO_PLIST_PATH" "CFBundleShortVersionString")}"
EFFECTIVE_BUILD="${PACKAGE_BUILD:-$(plist_value "$INFO_PLIST_PATH" "CFBundleVersion")}"

if [[ -z "$PACKAGE_MIN_OS" || -z "$README_MIN_OS" ]]; then
  echo "Failed to determine minimum macOS version from Package.swift or README.md"
  exit 1
fi

if [[ "$PLIST_MIN_OS" != "$PACKAGE_MIN_OS" || "$PLIST_MIN_OS" != "$README_MIN_OS" ]]; then
  echo "Minimum macOS version mismatch:"
  echo "  Package.swift: $PACKAGE_MIN_OS"
  echo "  Info.plist:   $PLIST_MIN_OS"
  echo "  README.md:    $README_MIN_OS"
  exit 1
fi

if [[ "$RUN_PACKAGING" -eq 1 ]]; then
  if [[ "$AD_HOC_SIGN" -eq 1 ]]; then
    if [[ -n "$SIGN_IDENTITY" || -n "$NOTARY_PROFILE" ]]; then
      echo "--ad-hoc-sign cannot be combined with --identity or --notary-profile."
      exit 1
    fi
  else
    if [[ -z "$SIGN_IDENTITY" || -z "$NOTARY_PROFILE" ]]; then
      echo "Public beta packaging requires both --identity and --notary-profile."
      echo "Use --no-package for local build/test preflight, or --ad-hoc-sign for an explicit internal-only package."
      exit 1
    fi
  fi
fi

echo "== MacWiki Beta Preflight =="
echo

echo "[1/9] Verifying icon assets and platform metadata..."
test -f "Sources/MacWiki/Resources/AppIcon.png"
test -f "Sources/MacWiki/Resources/AppIcon.icns"
ICON_NAME="$(plist_value "$INFO_PLIST_PATH" "CFBundleIconFile")"
if [[ "$ICON_NAME" != "AppIcon" ]]; then
  echo "Expected CFBundleIconFile=AppIcon, found '$ICON_NAME'"
  exit 1
fi
echo "Minimum macOS version: $PLIST_MIN_OS"

echo "[2/9] Verifying repo hygiene rules..."
for entry in ".agent/" "AGENTS.md" "CLAUDE.md" "GEMINI.md" "ANTIGRAVITY.md" "MODEL_HANDOVER_*.md" "macwiki-sidebar-audit.png"; do
  if ! rg -Fx -- "$entry" .gitignore >/dev/null 2>&1; then
    echo "Missing .gitignore entry: $entry"
    exit 1
  fi
done
if [[ "$ALLOW_DIRTY" -eq 0 ]]; then
  ensure_clean_git_tree
else
  echo "Dirty-tree check skipped via --allow-dirty."
fi

if [[ "$SKIP_SECRET_SCAN" -eq 0 ]]; then
  echo "[3/9] Running secret-pattern scan..."
  SECRET_PATTERN='(?i)(api[_-]?key|client[_-]?secret|bearer\s+[A-Za-z0-9._-]{16,}|(access|refresh|auth)[_-]?token\s*[:=]\s*["'\''][^"'\'']{8,}|password\s*[:=]\s*["'\''][^"'\'']+)'
  if rg -n "$SECRET_PATTERN" Sources Tests scripts README.md Package.swift >/tmp/macwiki-secret-scan.txt; then
    echo "Potential secret-like strings detected:"
    cat /tmp/macwiki-secret-scan.txt
    exit 1
  fi
else
  echo "[3/9] Secret-pattern scan skipped."
fi

echo "[4/9] Running debug build gate..."
swift build

echo "[5/9] Running test gate..."
swift test

echo "[6/9] Running release build gate..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/MacWiki"
if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Missing release executable at $EXECUTABLE_PATH"
  exit 1
fi
EXECUTABLE_MIN_OS="$(binary_min_os "$EXECUTABLE_PATH")"
if [[ "$EXECUTABLE_MIN_OS" != "$PLIST_MIN_OS" ]]; then
  echo "Built executable minimum macOS mismatch: Info.plist advertises $PLIST_MIN_OS but the binary requires $EXECUTABLE_MIN_OS"
  exit 1
fi

echo "[7/9] Running maintainability check (advisory unless placeholder residue fails)..."
./scripts/check_maintainability.sh

if [[ "$RUN_PACKAGING" -eq 1 ]]; then
  echo "[8/9] Packaging beta .app artifact..."
  PACKAGE_ARGS=(--skip-build --version "$EFFECTIVE_VERSION" --build "$EFFECTIVE_BUILD")
  if [[ "$AD_HOC_SIGN" -eq 1 ]]; then
    PACKAGE_ARGS+=(--ad-hoc-sign)
  else
    PACKAGE_ARGS+=(--identity "$SIGN_IDENTITY" --notary-profile "$NOTARY_PROFILE")
  fi
  ./scripts/package_beta_app.sh "${PACKAGE_ARGS[@]}"
  APP_PATH="$(ls -td "dist/MacWiki-${EFFECTIVE_VERSION}-build${EFFECTIVE_BUILD}-"*.app 2>/dev/null | head -n 1 || true)"
  if [[ -z "$APP_PATH" ]]; then
    echo "Failed to locate packaged app in dist/."
    exit 1
  fi
  APP_MIN_OS="$(plist_value "$APP_PATH/Contents/Info.plist" "LSMinimumSystemVersion")"
  APP_BINARY_MIN_OS="$(binary_min_os "$APP_PATH/Contents/MacOS/MacWiki")"
  if [[ "$APP_MIN_OS" != "$APP_BINARY_MIN_OS" ]]; then
    echo "Packaged app minimum macOS mismatch: app plist advertises $APP_MIN_OS but packaged binary requires $APP_BINARY_MIN_OS"
    exit 1
  fi
else
  echo "[8/9] Packaging skipped."
fi

echo "[9/9] Recording status..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git status --short
else
  echo "Git repo not initialized in this directory yet."
fi

echo
echo "Preflight complete."
echo "Manual QA remains intentionally pending (your step)."
