// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppFeatures",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AppFeatures",
            targets: ["AppFeatures"]
        )
    ],
    dependencies: [
        .package(path: "../Workspace"),
        .package(path: "../Git"),
        .package(path: "../Split"),
        .package(path: "../UI"),
        .package(path: "../ACPClientKit"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.25.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "AppFeatures",
            dependencies: [
                .product(name: "Workspace", package: "Workspace"),
                .product(name: "Git", package: "Git"),
                .product(name: "Split", package: "Split"),
                .product(name: "UI", package: "UI"),
                .product(name: "ACPClientKit", package: "ACPClientKit"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing")
            ],
            path: "Sources/AppFeatures",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AppFeaturesTests",
            dependencies: [
                "AppFeatures",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            path: "Tests/AppFeaturesTests"
        )
    ]
)
