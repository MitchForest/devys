// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UI",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "UI",
            targets: ["UI"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "UI",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "UITests",
            dependencies: ["UI"]
        ),
    ]
)
