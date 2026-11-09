#!/bin/zsh
# Builds Hatstand.app with just the Command Line Tools, for people who don't
# have Xcode. Install them with `xcode-select --install`.
#
# Usage:
#   scripts/build-without-xcode.sh           build build/swiftpm/Hatstand.app
#   scripts/build-without-xcode.sh --test    run the unit tests instead
#
# What Xcode normally does, done by hand:
#   - compile: `swift build`, using Package.swift (same sources as the project)
#   - Info.plist: written below, with the version read from the Xcode project
#   - icons: asset catalogues need actool, which only ships with Xcode, so the
#     menu bar SVG is copied in as-is (NSImage reads SVG) and the app icon PNGs
#     are turned into AppIcon.icns with iconutil
#   - signing: ad hoc with hardened runtime, like "Sign to Run Locally"

set -euo pipefail

ROOT=${0:A:h:h}
SCRATCH="$ROOT/build/swiftpm"
APP="$SCRATCH/Hatstand.app"
ASSETS="$ROOT/Hatstand/Assets.xcassets"
PBXPROJ="$ROOT/Hatstand.xcodeproj/project.pbxproj"

cd "$ROOT"

swift_flags=()
# The Command Line Tools ship Swift Testing somewhere SwiftPM doesn't look,
# and its Foundation overlay without a module, so point at the framework and
# skip the overlay. The tests don't use anything from it. Xcode needs neither.
DEV_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
if [[ $DEV_DIR == *CommandLineTools* ]]; then
    FW="$DEV_DIR/Library/Developer/Frameworks"
    swift_flags=(
        -Xswiftc -F -Xswiftc "$FW"
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
        -Xlinker -F -Xlinker "$FW"
        -Xlinker -rpath -Xlinker "$FW"
    )
fi

if [[ ${1:-} == --test ]]; then
    exec swift test --scratch-path "$SCRATCH" "${swift_flags[@]}"
fi

# One source of truth for the version: the Xcode project.
setting() { grep -m1 "$1 = " "$PBXPROJ" | sed -E 's/.*= "?([^";]*)"?;/\1/'; }
VERSION=$(setting MARKETING_VERSION)
BUILD_NUMBER=$(setting CURRENT_PROJECT_VERSION)
BUNDLE_ID=$(setting PRODUCT_BUNDLE_IDENTIFIER)

echo "→ Compiling Hatstand $VERSION ($BUILD_NUMBER)…"
# Built once per architecture and joined with lipo: `swift build` with two
# --arch flags needs Xcode's build system.
binaries=()
for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx14.0" \
        --scratch-path "$SCRATCH" --product Hatstand -Xswiftc -wmo --quiet
    binaries+=("$SCRATCH/$arch-apple-macosx/release/Hatstand")
done

echo "→ Assembling Hatstand.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/Hatstand"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>     <string>en-GB</string>
    <key>CFBundleDisplayName</key>           <string>Hatstand</string>
    <key>CFBundleExecutable</key>            <string>Hatstand</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleName</key>                  <string>Hatstand</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundleSupportedPlatforms</key>    <array><string>MacOSX</string></array>
    <key>CFBundleVersion</key>               <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>     <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSHumanReadableCopyright</key>      <string>Released under the MIT licence.</string>
</dict>
</plist>
EOF
plutil -lint -s "$APP/Contents/Info.plist"

cp "$ASSETS/MenuBarIcon.imageset/MenuBarIcon.svg" "$APP/Contents/Resources/"
ICONSET="$SCRATCH/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
cp "$ASSETS"/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signing…"
codesign --force --sign - --options runtime "$APP"
codesign --verify --deep --strict "$APP"

echo "✓ $APP"
echo "  Universal ($(lipo -archs "$APP/Contents/MacOS/Hatstand")), $(du -sh "$APP" | cut -f1 | tr -d ' ')"
