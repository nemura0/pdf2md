#!/bin/bash
# Reverses install and removes tool-owned data. Doesn't need Xcode, so it works with the volume
# unmounted. Converted Markdown files are the user's, and they stay.
set -euo pipefail

BIN_PATH="$HOME/.local/bin/pdf2md"

if [ -x "$BIN_PATH" ]; then
    "$BIN_PATH" --cancel >/dev/null 2>&1 || true
fi

rm -f "$BIN_PATH"
rmdir "$HOME/.local/bin" 2>/dev/null || true
rm -rf "$HOME/Library/Services/Convert to Markdown.workflow"
rm -rf "$HOME/Library/Application Support/pdf2md"
rm -rf "$HOME/Library/Caches/pdf2md"
rm -rf "$HOME/Library/Logs/pdf2md"

/System/Library/CoreServices/pbs -update

echo "uninstalled"
