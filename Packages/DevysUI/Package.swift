// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DevysUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DevysUI",
            targets: ["DevysUI"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DevysUI",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DevysUITests",
            dependencies: ["DevysUI"]
        ),
    ]
)
