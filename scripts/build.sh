#!/bin/zsh
# Builds Hatstand.app. Needs only Apple's Command Line Tools
# (`xcode-select --install`); Xcode works too but isn't required.
#
# Usage:
#   scripts/build.sh           build build/Hatstand.app (universal, Release)
#   scripts/build.sh --test    run the unit tests instead
#
# `swift build` compiles the code from Package.swift but doesn't make app
# bundles, so this script puts Hatstand.app together itself:
#   - Info.plist: written below
#   - icons: the menu bar SVG is copied in as-is (NSImage reads SVG) and the
#     app icon PNGs in design/AppIcon.iconset become AppIcon.icns
#   - signing: ad hoc, with hardened runtime

set -euo pipefail

# The release tag must be "v" plus VERSION (for example v1.1): the update
# check compares the two. Bump BUILD_NUMBER with every release too.
VERSION=1.2
BUILD_NUMBER=3
BUNDLE_ID=io.github.willblackmore.Hatstand

ROOT=${0:A:h:h}
SCRATCH="$ROOT/build"
APP="$SCRATCH/Hatstand.app"
DESIGN="$ROOT/design"

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

cp "$DESIGN/menubar-icon.svg" "$APP/Contents/Resources/MenuBarIcon.svg"
iconutil -c icns "$DESIGN/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signing…"
codesign --force --sign - --options runtime "$APP"
codesign --verify --deep --strict "$APP"

echo "✓ $APP"
echo "  Universal ($(lipo -archs "$APP/Contents/MacOS/Hatstand")), $(du -sh "$APP" | cut -f1 | tr -d ' ')"
