// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Split",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Split",
            targets: ["Split"]
        ),
    ],
    targets: [
        .target(
            name: "Split",
            dependencies: [],
            path: "Sources/Split",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SplitTests",
            dependencies: ["Split"],
            path: "Tests/SplitTests"
        ),
    ]
)
