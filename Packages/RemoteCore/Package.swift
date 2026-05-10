// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RemoteCore",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "RemoteCore",
            targets: ["RemoteCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RemoteCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "RemoteCoreTests",
            dependencies: ["RemoteCore"]
        ),
    ]
)
