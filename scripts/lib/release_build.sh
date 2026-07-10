#!/usr/bin/env bash

# Populate MACWIKI_RELEASE_BUILD_ARGS with an explicit LC_BUILD_VERSION contract.
# Swift auto-link metadata can otherwise lower the final binary's SDK field even
# when every object was compiled against the selected SDK. Derive the SDK value
# from xcrun so the embedded metadata remains traceable to the active Xcode.
macwiki_release_build_args() {
  local minimum_macos="$1"
  local sdk_version

  if ! command -v xcrun >/dev/null 2>&1; then
    echo "Release builds require xcrun to establish SDK provenance." >&2
    return 1
  fi

  sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
  if [[ ! "$minimum_macos" =~ ^[0-9]+\.[0-9]+$ || ! "$sdk_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid release platform versions: minimum=$minimum_macos sdk=$sdk_version" >&2
    return 1
  fi

  MACWIKI_RELEASE_BUILD_ARGS=(
    -Xlinker=-platform_version
    -Xlinker=macos
    -Xlinker="$minimum_macos"
    -Xlinker="$sdk_version"
  )
}
