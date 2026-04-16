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
    dependencies: [
        .package(path: "../UI")
    ],
    targets: [
        .target(
            name: "Split",
            dependencies: [
                .product(name: "UI", package: "UI")
            ],
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
