// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mac-server",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "mac-server",
            targets: ["mac-server"]
        )
    ],
    dependencies: [
        .package(path: "../../Packages/Server"),
        .package(path: "../../Packages/Agents"),
        .package(path: "../../Packages/Chat"),
    ],
    targets: [
        .executableTarget(
            name: "mac-server",
            dependencies: [
                .product(name: "ServerProtocol", package: "Server"),
                "Agents",
                .product(name: "ChatCore", package: "Chat"),
            ],
            path: "Sources/mac_server",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
