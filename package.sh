#!/bin/bash
# Builds a distributable copy and wraps it in a DMG.
#
#   ./package.sh                 build + sign with the best identity available
#   ./package.sh --notarize WTA  additionally notarise and staple, using the
#                                notarytool keychain profile named "WTA"
#
# Signing identity is chosen automatically:
#   1. "Developer ID Application: …"  → hardened runtime + secure timestamp, so the
#      result can be notarised and will open on any Mac with no warning.
#   2. anything else                  → ad-hoc. The app still runs, but every recipient
#      has to clear Gatekeeper by hand (see the note printed at the end).
#
# The local "WritingToolsAnywhere Dev" certificate is deliberately NOT used here: it is
# trusted only on the machine that created it, so shipping it helps nobody.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="WritingToolsAnywhere"
# The distribution copy is signed separately from build/. Re-signing the dev build would
# change its cdhash and silently revoke the Accessibility permission granted to it.
STAGE=$(mktemp -d)
BUNDLE="$STAGE/$APP_NAME.app"
NOTARY_PROFILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --notarize) NOTARY_PROFILE="${2:-}"; shift 2 ;;
        *) echo "unknown argument: $1"; exit 1 ;;
    esac
done

trap 'rm -rf "$STAGE"' EXIT

[ -f Resources/AppIcon.icns ] || ./make-icon.sh
./build.sh
cp -R "build/$APP_NAME.app" "$BUNDLE"

VERSION=$(defaults read "$BUNDLE/Contents/Info.plist" CFBundleShortVersionString)
DEV_ID=$(security find-identity -v -p codesigning \
         | grep "Developer ID Application" | head -1 \
         | sed -E 's/.*"(.*)"/\1/' || true)

if [ -n "$DEV_ID" ]; then
    echo "→ signing for distribution: $DEV_ID"
    # Capture rather than stream: codesign reports a missing intermediate as a *warning*
    # alongside an opaque errSecInternalComponent, and the useful half scrolls past.
    if ! SIGN_OUTPUT=$(codesign --force --deep --options runtime --timestamp \
                                --sign "$DEV_ID" "$BUNDLE" 2>&1); then
        echo "$SIGN_OUTPUT"
        if grep -q "unable to build chain" <<<"$SIGN_OUTPUT"; then
            cat <<'NOTE'

✗ The signature has no path to a trusted root.

  Double-clicking the certificate downloaded from Apple installs only your own
  certificate. codesign also needs the "Developer ID Certification Authority"
  intermediate present in the keychain.

  `security verify-cert` is no help diagnosing this: it fetches the intermediate over
  the network and reports success even when the keychain lacks it.

  Fix:
      curl -O https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
      security import DeveloperIDG2CA.cer -k ~/Library/Keychains/login.keychain-db
NOTE
        fi
        exit 1
    fi
    echo "$SIGN_OUTPUT"
    SIGNED_PROPERLY=1
else
    echo "→ no Developer ID found; signing ad-hoc"
    codesign --force --deep --sign - "$BUNDLE"
    SIGNED_PROPERLY=0
fi

codesign --verify --deep --strict --verbose=1 "$BUNDLE"

if [ -n "$NOTARY_PROFILE" ]; then
    if [ "$SIGNED_PROPERLY" != "1" ]; then
        echo "✗ notarisation needs a Developer ID signature; skipping"
        exit 1
    fi
    echo "→ submitting for notarisation (this takes a few minutes)"
    ZIP=$(mktemp -d)/"$APP_NAME.zip"
    ditto -c -k --keepParent "$BUNDLE" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$BUNDLE"
    echo "✓ notarised and stapled"

    # The point of notarising is that the app opens on a machine that has never seen it.
    # Assert that rather than assuming it.
    echo "→ verifying the way Gatekeeper will see it"
    xcrun stapler validate "$BUNDLE"
    spctl --assess --type execute --verbose=2 "$BUNDLE"
    echo "✓ passes Gatekeeper"
fi

echo "→ building dmg"
mkdir -p dist
DMG="dist/$APP_NAME-$VERSION.dmg"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
    -ov -format UDZO -quiet "$DMG"

# The app inside is notarised, but to Gatekeeper the disk image carrying it is a
# separate piece of code — left unsigned it assesses as "no usable signature". Sign and
# notarise the container too, so the thing being downloaded is clean, not just its
# contents.
if [ "$SIGNED_PROPERLY" = "1" ]; then
    echo "→ signing the disk image"
    codesign --force --timestamp --sign "$DEV_ID" "$DMG"

    if [ -n "$NOTARY_PROFILE" ]; then
        echo "→ notarising the disk image"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"

        echo "→ verifying the download the way a stranger's Mac will see it"
        xcrun stapler validate "$DMG"
        spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
        echo "✓ the disk image itself passes Gatekeeper"
    fi
fi

echo
echo "✓ $DMG  ($(du -h "$DMG" | cut -f1))"
echo "  sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"

if [ "$SIGNED_PROPERLY" != "1" ]; then
    cat <<'NOTE'

⚠️  This build is ad-hoc signed, so macOS will refuse to open it after download.
    Recipients must run:

        xattr -dr com.apple.quarantine /Applications/WritingToolsAnywhere.app

    To remove that step, get an Apple Developer account, then:

        xcrun notarytool store-credentials WTA \
            --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PW
        ./package.sh --notarize WTA
NOTE
fi
