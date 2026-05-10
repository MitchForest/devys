// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Diff",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "Diff", targets: ["Diff"])
    ],
    dependencies: [
        .package(path: "../Rendering"),
        .package(path: "../Syntax"),
        .package(path: "../Text"),
        .package(path: "../UI")
    ],
    targets: [
        .target(
            name: "Diff",
            dependencies: [
                "Rendering",
                "Syntax",
                "Text",
                "UI"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DiffTests",
            dependencies: ["Diff", "UI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
