// swift-tools-version:5.9
//
// Lets Hatstand be built and tested with just the Command Line Tools, no Xcode:
//
//     swift test                          run the unit tests
//     scripts/build-without-xcode.sh      build Hatstand.app
//
// Hatstand.xcodeproj is still the main way to work on the app. This file only
// describes the same sources; the .app bundle itself is put together by the
// script, because SwiftPM doesn't make app bundles.

import PackageDescription

let package = Package(
    name: "Hatstand",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Hatstand",
            path: "Hatstand",
            // Asset catalogues need actool, which only comes with Xcode.
            // The build script copies the icons into the bundle instead.
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(
            name: "HatstandTests",
            dependencies: ["Hatstand"],
            path: "HatstandTests"
        ),
    ]
)
