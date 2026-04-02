// swift-tools-version: 6.0
// Syntax - Shiki-compatible syntax highlighting

import PackageDescription

let package = Package(
    name: "Syntax",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Syntax",
            targets: ["Syntax"]
        ),
        .library(
            name: "OnigurumaKit",
            targets: ["OnigurumaKit"]
        ),
    ],
    dependencies: [],
    targets: [
        // C module for Oniguruma headers - links to the xcframework
        .target(
            name: "COniguruma",
            dependencies: ["libonig"],
            path: "Sources/COniguruma",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        
        // Binary target for the Oniguruma static library
        .binaryTarget(
            name: "libonig",
            path: "xcframeworks/libonig.xcframework"
        ),
        
        // Swift wrapper for Oniguruma
        .target(
            name: "OnigurumaKit",
            dependencies: ["COniguruma"],
            path: "Sources/OnigurumaKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // Main syntax highlighting library
        .target(
            name: "Syntax",
            dependencies: ["OnigurumaKit"],
            resources: [
                .process("Resources/Grammars"),
                .process("Resources/Themes")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        .testTarget(
            name: "SyntaxTests",
            dependencies: ["Syntax"],
            resources: [
                .process("Fixtures")
            ]
        ),
        
        .testTarget(
            name: "OnigurumaKitTests",
            dependencies: ["OnigurumaKit"]
        ),
    ]
)
