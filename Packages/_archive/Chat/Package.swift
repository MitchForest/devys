// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Chat",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ChatCore", targets: ["ChatCore"]),
        .library(name: "ChatUI", targets: ["ChatUI"]),
    ],
    dependencies: [
        .package(path: "../Server"),
        .package(path: "../UI"),
    ],
    targets: [
        .target(
            name: "ChatCore",
            path: "Sources/ChatCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "ChatUI",
            dependencies: [
                "ChatCore",
                .product(name: "ServerClient", package: "Server"),
                .product(name: "ServerProtocol", package: "Server"),
                "UI",
            ],
            path: "Sources/ChatUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ChatCoreTests",
            dependencies: ["ChatCore"],
            path: "Tests/ChatCoreTests"
        ),
        .testTarget(
            name: "ChatUITests",
            dependencies: [
                "ChatCore",
                "ChatUI",
                .product(name: "ServerProtocol", package: "Server"),
            ],
            path: "Tests/ChatUITests"
        ),
    ]
)
