// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Rendering",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Rendering",
            targets: ["Rendering"]
        )
    ],
    targets: [
        .target(
            name: "Rendering",
            path: "Sources/TextRenderer",
            resources: [
                .process("Resources/EditorShaders.metal")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "RenderingTests",
            dependencies: ["Rendering"],
            path: "Tests/RenderingTests"
        )
    ]
)
