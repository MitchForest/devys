// swift-tools-version: 5.9

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
