// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DevysCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DevysCore",
            targets: ["DevysCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DevysCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DevysCoreTests",
            dependencies: ["DevysCore"]
        ),
    ]
)
