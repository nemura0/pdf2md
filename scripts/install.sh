#!/bin/bash
# Release build to ~/.local/bin (ad-hoc signed), Quick Action to ~/Library/Services. Idempotent.
source "$(dirname "$0")/lib.sh"
require_xcode

BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/pdf2md"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_NAME="Convert to Markdown.workflow"
TEMPLATE_DIR="$REPO_ROOT/templates/$WORKFLOW_NAME"

swift build -c release --product pdf2md
built="$(swift build -c release --show-bin-path)/pdf2md"

mkdir -p "$BIN_DIR" "$SERVICES_DIR"
# Copy then rename: overwriting a binary in place makes the kernel kill running jobs.
tmp="$(mktemp "$BIN_DIR/.pdf2md.XXXXXX")"
workflow_tmp="$(mktemp -d "$SERVICES_DIR/.pdf2md.XXXXXX")"
trap 'rm -f "$tmp"; rm -rf "$workflow_tmp"' EXIT
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

# The workflow holds the binary's absolute path, escaped first for the shell's double quotes and
# then for XML. Bash substitution, because sed would treat characters in a path as commands.
escaped_path="$BIN_PATH"
escaped_path="${escaped_path//\\/\\\\}"
escaped_path="${escaped_path//\"/\\\"}"
escaped_path="${escaped_path//\$/\\\$}"
escaped_path="${escaped_path//&/&amp;}"
escaped_path="${escaped_path//</&lt;}"
escaped_path="${escaped_path//>/&gt;}"

mkdir -p "$workflow_tmp/Contents"
cp "$TEMPLATE_DIR/Contents/Info.plist" "$workflow_tmp/Contents/Info.plist"
template="$(cat "$TEMPLATE_DIR/Contents/document.wflow")"
printf '%s\n' "${template//__PDF2MD_BIN__/$escaped_path}" > "$workflow_tmp/Contents/document.wflow"
plutil -lint -s "$workflow_tmp/Contents/document.wflow" || die "the rendered workflow isn't valid."

mv -f "$tmp" "$BIN_PATH"
rm -rf "$SERVICES_DIR/$WORKFLOW_NAME"
mv "$workflow_tmp" "$SERVICES_DIR/$WORKFLOW_NAME"
chmod 755 "$SERVICES_DIR/$WORKFLOW_NAME"
trap - EXIT

/System/Library/CoreServices/pbs -update

echo "installed: $BIN_PATH ($("$BIN_PATH" --version))"
echo "installed: $SERVICES_DIR/$WORKFLOW_NAME"
