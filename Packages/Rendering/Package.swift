// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Rendering",
    platforms: [
        .macOS(.v26),
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
                .process("Resources/EditorShaders.metal"),
                .process("Resources/TerminalShaders.metal"),
                .copy("Resources/Fonts")
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
