#!/bin/bash
# Renders the app icon from tools/MakeIcon/main.swift into Resources/AppIcon.icns.
# Every size is drawn from the vector art rather than resampled from one bitmap.
set -euo pipefail
cd "$(dirname "$0")"

BIN=$(mktemp -d)/makeicon
ICONSET="Resources/AppIcon.iconset"

echo "→ compiling generator"
swiftc -O -target arm64-apple-macos26.0 -framework AppKit tools/MakeIcon/main.swift -o "$BIN"

echo "→ rendering"
rm -rf "$ICONSET"
"$BIN" "$ICONSET"

echo "→ packing icns"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
cp "$ICONSET/icon_512x512.png" Resources/icon-preview.png

echo "✓ Resources/AppIcon.icns  ($(du -h Resources/AppIcon.icns | cut -f1))"
