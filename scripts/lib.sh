#!/bin/bash
# Shared helpers for the scripts behind the Makefile. Source, don't run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

die() {
    echo "error: $*" >&2
    exit 1
}

# Xcode may live on an external volume, and CommandLineTools can be installed too, so a
# non-empty `xcode-select -p` proves nothing. Require a real Xcode with a macOS 26+ SDK.
require_xcode() {
    local developer_dir sdk_version
    developer_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"

    case "$developer_dir" in
        *.app/Contents/Developer) ;;
        *)
            die "the active developer directory is '${developer_dir:-none}', not an Xcode app. \
If Xcode lives on an external volume, make sure the volume is mounted, then run: \
sudo xcode-select -s /path/to/Xcode.app/Contents/Developer"
            ;;
    esac
    [ -d "$developer_dir" ] ||
        die "Xcode isn't available at '$developer_dir'. Is its volume mounted?"

    sdk_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
    [ "${sdk_version%%.*}" -ge 26 ] 2>/dev/null ||
        die "the macOS 26 SDK or newer is required (found '${sdk_version:-none}')."
}
