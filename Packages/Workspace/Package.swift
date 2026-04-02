// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Workspace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Workspace",
            targets: ["Workspace"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Workspace",
            dependencies: [],
            path: "Sources/Core",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "WorkspaceTests",
            dependencies: ["Workspace"],
            path: "Tests/CoreTests"
        ),
    ]
)
