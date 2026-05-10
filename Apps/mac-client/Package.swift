// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MacClientFeatures",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "MacClientAppFeatures", targets: ["MacClientAppFeatures"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.24.1"),
        .package(path: "../../Packages/Diff"),
        .package(path: "../../Packages/Editor"),
        .package(path: "../../Packages/Git")
    ],
    targets: [
        .target(
            name: "MacClientAppFeatures",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Diff", package: "Diff"),
                .product(name: "Editor", package: "Editor"),
                .product(name: "Git", package: "Git")
            ],
            path: "Sources/mac_client",
            exclude: [
                "DevysAppMain.swift",
                "Hosts",
                "ReaderTabRootView.swift"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "MacClientAppFeaturesTests",
            dependencies: [
                "MacClientAppFeatures",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Git", package: "Git")
            ],
            path: "Tests/MacClientAppFeaturesTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
