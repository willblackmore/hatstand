#!/bin/zsh
# Builds Hatstand in Release and packages it as dist/Hatstand.dmg,
# with a shortcut to /Applications so people can drag it across.
#
# The file name has no version number on purpose: the website links to
# .../releases/latest/download/Hatstand.dmg, which always serves the newest one.
#
# Usage: scripts/make-release.sh

set -euo pipefail

ROOT=${0:A:h:h}
BUILD="$ROOT/build"
DIST="$ROOT/dist"
STAGE="$BUILD/dmg"
APP="$BUILD/Hatstand.app"
DMG="$DIST/Hatstand.dmg"

cd "$ROOT"

scripts/build.sh

codesign --verify --deep --strict "$APP"
# Universal, so it runs on both Apple silicon and Intel Macs.
ARCHS=$(lipo -archs "$APP/Contents/MacOS/Hatstand")
[[ $ARCHS == *arm64* && $ARCHS == *x86_64* ]] || { echo "✗ Not universal: $ARCHS" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")

echo "→ Packaging Hatstand $VERSION ($BUILD_NUMBER)…"
rm -rf "$STAGE" && mkdir -p "$STAGE" "$DIST"
ditto "$APP" "$STAGE/Hatstand.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Hatstand" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
hdiutil verify "$DMG" -quiet

echo "✓ $DMG"
echo "  Version $VERSION ($BUILD_NUMBER), $(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "  Tag the release v$VERSION and upload Hatstand.dmg."
