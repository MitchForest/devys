// swift-tools-version: 6.0
// Agents - Server-side agent process management for Codex and Claude Code CLIs.
// Used only by mac-server. Not imported by any client app.

import PackageDescription

let package = Package(
    name: "Agents",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Agents",
            targets: ["Agents"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "Agents",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/Agents",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "AgentsTests",
            dependencies: ["Agents"],
            path: "Tests/AgentsTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
