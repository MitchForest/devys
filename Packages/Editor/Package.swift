// swift-tools-version: 6.2
// Editor - Metal-accelerated code editor

import PackageDescription

let package = Package(
    name: "Editor",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "Editor",
            targets: ["Editor"]
        ),
    ],
    dependencies: [
        .package(path: "../Text"),
        .package(path: "../Syntax"),
        .package(path: "../Rendering"),
        .package(path: "../UI"),
    ],
    targets: [
        .target(
            name: "Editor",
            dependencies: [
                "Text",
                "Syntax",
                .product(name: "Rendering", package: "Rendering"),
                "UI"
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
