#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RUN_PACKAGING=1
SKIP_SECRET_SCAN=0
PACKAGE_VERSION=""
PACKAGE_BUILD=""

usage() {
  cat <<'EOF'
Run non-manual beta release preflight checks for MacWiki.

Usage:
  ./scripts/preflight_beta_release.sh [options]

Options:
  --no-package        Skip .app packaging
  --skip-secret-scan  Skip source secret-pattern scan
  --version <tag>     Version passed to packaging (example: v0.5.0-beta.1)
  --build <number>    Build number passed to packaging (example: 1)
  --help              Show this help
EOF
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

echo "== MacWiki Beta Preflight =="
echo

echo "[1/6] Verifying icon assets and plist wiring..."
test -f "Sources/MacWiki/Resources/AppIcon.png"
test -f "Sources/MacWiki/Resources/AppIcon.icns"
ICON_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "Sources/MacWiki/Info.plist")"
if [[ "$ICON_NAME" != "AppIcon" ]]; then
  echo "Expected CFBundleIconFile=AppIcon, found '$ICON_NAME'"
  exit 1
fi

echo "[2/6] Verifying .gitignore includes private agent files..."
for entry in ".agent/" "AGENTS.md" "CLAUDE.md" "GEMINI.md" "ANTIGRAVITY.md"; do
  if ! rg -n "^${entry//./\\.}$" .gitignore >/dev/null 2>&1; then
    echo "Missing .gitignore entry: $entry"
    exit 1
  fi
done

if [[ "$SKIP_SECRET_SCAN" -eq 0 ]]; then
  echo "[3/6] Running secret-pattern scan..."
  SECRET_PATTERN='(?i)(api[_-]?key|client[_-]?secret|bearer\s+[A-Za-z0-9._-]{16,}|(access|refresh|auth)[_-]?token\s*[:=]\s*["'\''][^"'\'']{8,}|password\s*[:=]\s*["'\''][^"'\'']+)'
  if rg -n "$SECRET_PATTERN" Sources Tests scripts README.md Package.swift >/tmp/macwiki-secret-scan.txt; then
    echo "Potential secret-like strings detected:"
    cat /tmp/macwiki-secret-scan.txt
    exit 1
  fi
else
  echo "[3/6] Secret-pattern scan skipped."
fi

echo "[4/7] Running build/test gates..."
swift build
swift test
swift build -c release

echo "[5/7] Running maintainability check (advisory unless placeholder residue fails)..."
./scripts/check_maintainability.sh

if [[ "$RUN_PACKAGING" -eq 1 ]]; then
  echo "[6/7] Packaging beta .app artifact..."
  PACKAGE_ARGS=(--skip-build)
  if [[ -n "$PACKAGE_VERSION" ]]; then
    PACKAGE_ARGS+=(--version "$PACKAGE_VERSION")
  fi
  if [[ -n "$PACKAGE_BUILD" ]]; then
    PACKAGE_ARGS+=(--build "$PACKAGE_BUILD")
  fi
  ./scripts/package_beta_app.sh "${PACKAGE_ARGS[@]}"
else
  echo "[6/7] Packaging skipped."
fi

echo "[7/7] Recording status..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git status --short
else
  echo "Git repo not initialized in this directory yet."
fi

echo
echo "Preflight complete."
echo "Manual QA remains intentionally pending (your step)."
