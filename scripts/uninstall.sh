#!/bin/bash
# Reverses install. Doesn't need Xcode, so it works with the volume unmounted.
set -euo pipefail
rm -f "$HOME/.local/bin/pdf2md"
rmdir "$HOME/.local/bin" 2>/dev/null || true
echo "uninstalled"
