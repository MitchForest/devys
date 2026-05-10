// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Text",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "Text",
            targets: ["Text"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Text",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TextTests",
            dependencies: ["Text"]
        )
    ]
)
