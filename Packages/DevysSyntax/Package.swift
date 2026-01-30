// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DevysSyntax",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DevysSyntax",
            targets: ["DevysSyntax"]
        ),
    ],
    dependencies: [
        // Oniguruma regex engine for TextMate grammar support
        // Note: Will be added when implementing Phase 5
    ],
    targets: [
        .target(
            name: "DevysSyntax",
            dependencies: [],
            resources: [
                .copy("Resources/Grammars"),
                .copy("Resources/Themes")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DevysSyntaxTests",
            dependencies: ["DevysSyntax"]
        ),
    ]
)
