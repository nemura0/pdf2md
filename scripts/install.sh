#!/bin/bash
# Release build to ~/.local/bin (ad-hoc signed). The workflow step arrives in P5. Idempotent.
source "$(dirname "$0")/lib.sh"
require_xcode

BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/pdf2md"

swift build -c release --product pdf2md
built="$(swift build -c release --show-bin-path)/pdf2md"

mkdir -p "$BIN_DIR"
# Copy then rename: overwriting a binary in place makes the kernel kill running jobs.
tmp="$(mktemp "$BIN_DIR/.pdf2md.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cp "$built" "$tmp"
chmod 755 "$tmp"

# The installed tool must never depend on the volume holding Xcode.
while IFS= read -r rpath; do
    case "$rpath" in
        /Volumes/*) install_name_tool -delete_rpath "$rpath" "$tmp" ;;
    esac
done < <(otool -l "$tmp" | awk '/cmd LC_RPATH/ { getline; getline; sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print }')
codesign --force --sign - --identifier dev.nemura.pdf2md "$tmp" 2>/dev/null

if otool -L "$tmp" | grep -q '/Volumes/' || otool -l "$tmp" | grep -q 'path /Volumes/'; then
    die "the binary still references an external volume. Refusing to install."
fi
"$tmp" --version >/dev/null || die "the built binary doesn't run."

mv -f "$tmp" "$BIN_PATH"
trap - EXIT

echo "installed: $BIN_PATH ($("$BIN_PATH" --version))"
