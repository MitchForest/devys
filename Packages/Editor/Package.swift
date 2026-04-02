// swift-tools-version: 6.0
// Editor - Metal-accelerated code editor

import PackageDescription

let package = Package(
    name: "Editor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Editor",
            targets: ["Editor"]
        ),
    ],
    dependencies: [
        .package(path: "../Syntax"),
        .package(path: "../Rendering"),
    ],
    targets: [
        .target(
            name: "Editor",
            dependencies: [
                "Syntax",
                .product(name: "Rendering", package: "Rendering")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "EditorTests",
            dependencies: ["Editor"]
        ),
    ]
)
