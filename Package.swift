// swift-tools-version:5.9
//
// Build Hatstand with scripts/build.sh, which compiles this package and then
// puts Hatstand.app together around it. Run the tests with `scripts/build.sh --test`.

import PackageDescription

let package = Package(
    name: "Hatstand",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Hatstand",
            path: "Hatstand"
        ),
        .testTarget(
            name: "HatstandTests",
            dependencies: ["Hatstand"],
            path: "HatstandTests"
        ),
    ]
)
