#!/usr/bin/env bash
set -euo pipefail

echo "RETIRED: automated public release is outside the current internal-beta program." >&2
echo "Use INTERNAL_BETA_QUALITY_PROGRAM.md for the active readiness process." >&2
exit 2

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION=""
BUILD_NUMBER=""
REPO_SLUG="tombunting/MacWiki"
RELEASE_TITLE=""
VISIBILITY="public"
SKIP_PREFLIGHT=0
ASSUME_YES=0
DRY_RUN=0
SIGN_IDENTITY=""
NOTARY_PROFILE=""

require_git_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "release_beta.sh must be run inside an existing git repository."
    exit 1
  fi
}

require_clean_git_tree() {
  local status_output
  status_output="$(git status --porcelain --untracked-files=all)"
  if [[ -n "$status_output" ]]; then
    echo "Public beta releases require a clean git tree:"
    echo "$status_output"
    exit 1
  fi
}

usage() {
  cat <<'EOF'
Run the full MacWiki beta release flow with prompts.

Usage:
  ./scripts/release_beta.sh [options]

Options:
  --version <tag>         Release tag (example: v0.5.0-beta.1)
  --build <number>        Build number for packaged artifact (example: 1)
  --repo <owner/name>     GitHub repository slug (default: tombunting/MacWiki)
  --title <text>          GitHub release title (default: "MacWiki <version>")
  --identity <name>       Developer ID signing identity used for packaging
  --notary-profile <name>
                          `notarytool` keychain profile used for notarization
  --private               Create first-time repository as private
  --public                Create first-time repository as public (default)
  --skip-preflight        Skip preflight (not recommended)
  --yes                   Non-interactive mode (assume yes to prompts)
  --dry-run               Print commands without executing them
  --help                  Show this help
EOF
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

latest_zip_path() {
  ls -td "dist/MacWiki-${PACKAGE_VERSION}-build${BUILD_NUMBER}-"*.zip 2>/dev/null | head -1 || true
}

package_release_artifact() {
  run_cmd ./scripts/package_beta_app.sh \
    --version "$PACKAGE_VERSION" \
    --build "$BUILD_NUMBER" \
    --skip-build \
    --identity "$SIGN_IDENTITY" \
    --notary-profile "$NOTARY_PROFILE"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    ZIP_PATH="dist/MacWiki-${PACKAGE_VERSION}-build${BUILD_NUMBER}-DRY-RUN.zip"
  else
    ZIP_PATH="$(latest_zip_path)"
  fi
}

prompt_if_empty() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="${3:-}"
  local current_value="${!var_name}"

  if [[ -n "$current_value" ]]; then
    return
  fi

  if [[ "$ASSUME_YES" -eq 1 && -n "$default_value" ]]; then
    printf -v "$var_name" '%s' "$default_value"
    return
  fi

  local reply=""
  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt_text [$default_value]: " reply
    if [[ -z "$reply" ]]; then
      reply="$default_value"
    fi
  else
    read -r -p "$prompt_text: " reply
  fi

  printf -v "$var_name" '%s' "$reply"
}

confirm_or_exit() {
  local prompt_text="$1"
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return
  fi

  local answer=""
  read -r -p "$prompt_text [y/N]: " answer
  case "$answer" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
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
    --repo)
      REPO_SLUG="${2:-}"
      shift 2
      ;;
    --title)
      RELEASE_TITLE="${2:-}"
      shift 2
      ;;
    --identity)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    --private)
      VISIBILITY="private"
      shift
      ;;
    --public)
      VISIBILITY="public"
      shift
      ;;
    --skip-preflight)
      SKIP_PREFLIGHT=1
      shift
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
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

require_git_repo
CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "Release flow requires a checked-out branch, not detached HEAD."
  exit 1
fi
require_clean_git_tree

if ! command -v gh >/dev/null 2>&1; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Warning: GitHub CLI (gh) not found. Continuing because --dry-run is enabled."
  else
    echo "Missing GitHub CLI (gh). Install it first: https://cli.github.com/"
    exit 1
  fi
fi

default_version="v0.5.0-beta.1"
default_build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "Sources/MacWiki/Info.plist" 2>/dev/null || echo "1")"

prompt_if_empty VERSION "Beta tag (format vX.Y.Z-beta.N)" "$default_version"
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]]; then
  echo "Version '$VERSION' does not match expected beta format vX.Y.Z-beta.N"
  exit 1
fi

prompt_if_empty BUILD_NUMBER "Build number" "$default_build"
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Build number must be numeric."
  exit 1
fi

if [[ -z "$SIGN_IDENTITY" || -z "$NOTARY_PROFILE" ]]; then
  echo "Public beta release requires both --identity and --notary-profile."
  exit 1
fi

if [[ -z "$RELEASE_TITLE" ]]; then
  RELEASE_TITLE="MacWiki $VERSION"
fi

PACKAGE_VERSION="${VERSION#v}"

echo
echo "Release plan:"
echo "  Version tag: $VERSION"
echo "  Package version: $PACKAGE_VERSION"
echo "  Build: $BUILD_NUMBER"
echo "  Repo: $REPO_SLUG"
echo "  Branch: $CURRENT_BRANCH"
echo "  Visibility (first create): $VISIBILITY"
echo "  Signing identity: $SIGN_IDENTITY"
echo "  Notary profile: $NOTARY_PROFILE"
echo "  Preflight: $([[ "$SKIP_PREFLIGHT" -eq 1 ]] && echo "skip" || echo "run")"
echo "  Dry run: $([[ "$DRY_RUN" -eq 1 ]] && echo "yes" || echo "no")"
echo

confirm_or_exit "Have you completed manual QA for this beta?"
confirm_or_exit "Proceed with automated release steps?"

if [[ "$SKIP_PREFLIGHT" -eq 0 ]]; then
  run_cmd ./scripts/preflight_beta_release.sh \
    --version "$PACKAGE_VERSION" \
    --build "$BUILD_NUMBER" \
    --identity "$SIGN_IDENTITY" \
    --notary-profile "$NOTARY_PROFILE"
else
  echo "Preflight skipped; packaging a fresh signed/notarized artifact before release."
  package_release_artifact
fi

ZIP_PATH="${ZIP_PATH:-$(latest_zip_path)}"
if [[ -z "$ZIP_PATH" ]]; then
  echo "No packaged zip found for $PACKAGE_VERSION build $BUILD_NUMBER in dist/. Running packaging now."
  package_release_artifact
fi
if [[ -z "$ZIP_PATH" ]]; then
  echo "Failed to locate packaged zip in dist/."
  exit 1
fi

REMOTE_EXISTS=0
if git remote get-url origin >/dev/null 2>&1; then
  REMOTE_EXISTS=1
fi

if [[ "$REMOTE_EXISTS" -eq 1 ]]; then
  echo "Git remote origin already configured."
  run_cmd git push -u origin "$CURRENT_BRANCH"
else
  echo "Creating GitHub repository and pushing $CURRENT_BRANCH..."
  if [[ "$VISIBILITY" == "private" ]]; then
    run_cmd gh repo create "$REPO_SLUG" --private --source=. --remote=origin --push
  else
    run_cmd gh repo create "$REPO_SLUG" --public --source=. --remote=origin --push
  fi
fi

if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null 2>&1; then
  echo "Tag $VERSION already exists locally."
else
  run_cmd git tag -a "$VERSION" -m "MacWiki beta $VERSION"
fi
run_cmd git push origin "$VERSION"

if gh release view "$VERSION" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  echo "GitHub release $VERSION already exists."
else
  run_cmd gh release create "$VERSION" \
    --repo "$REPO_SLUG" \
    --prerelease \
    --title "$RELEASE_TITLE" \
    --generate-notes
fi

run_cmd gh release upload "$VERSION" "$ZIP_PATH" --repo "$REPO_SLUG" --clobber

echo
echo "Release flow complete."
echo "Uploaded artifact: $ZIP_PATH"
