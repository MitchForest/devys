// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RemoteFeatures",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "RemoteFeatures",
            targets: ["RemoteFeatures"]
        ),
    ],
    dependencies: [
        .package(path: "../RemoteCore"),
        .package(path: "../SSH"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.25.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "RemoteFeatures",
            dependencies: [
                .product(name: "RemoteCore", package: "RemoteCore"),
                .product(name: "SSH", package: "SSH"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "RemoteFeaturesTests",
            dependencies: [
                "RemoteFeatures",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
    ]
)
