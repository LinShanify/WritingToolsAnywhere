#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="WritingToolsAnywhere"
BUNDLE="build/$APP_NAME.app"

pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "  (no icon yet — run ./make-icon.sh)"
fi

echo "→ compiling"
swiftc -O \
    -target arm64-apple-macos26.0 \
    -framework AppKit -framework Carbon -framework ApplicationServices -framework FoundationModels \
    -o "$BUNDLE/Contents/MacOS/$APP_NAME" \
    Sources/*.swift

IDENTITY="WritingToolsAnywhere Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "→ signing ($IDENTITY — stable identity, Accessibility permission survives rebuilds)"
    codesign --force --deep --sign "$IDENTITY" "$BUNDLE"
else
    echo "→ signing (ad-hoc — run ./setup-signing.sh to stop re-granting Accessibility every build)"
    codesign --force --deep --sign - "$BUNDLE"
fi

echo "✓ built $BUNDLE"

if [[ "${1:-}" == "--run" ]]; then
    open "$BUNDLE"
    echo "✓ launched"
fi
