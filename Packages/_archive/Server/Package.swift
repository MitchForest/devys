// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Server",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ServerProtocol", targets: ["ServerProtocol"]),
        .library(name: "ServerClient", targets: ["ServerClient"]),
    ],
    dependencies: [
        .package(path: "../Chat"),
        .package(path: "../Terminal"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.94.1"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.9.1"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.9.2"),
    ],
    targets: [
        .target(
            name: "ServerProtocol",
            dependencies: [
                .product(name: "ChatCore", package: "Chat"),
            ],
            path: "Sources/ServerProtocol",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "ServerClient",
            dependencies: [
                .product(name: "ChatCore", package: "Chat"),
                "ServerProtocol",
                .product(name: "TerminalCore", package: "Terminal"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            ],
            path: "Sources/ServerClient",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ServerProtocolTests",
            dependencies: [
                "ServerProtocol",
                .product(name: "ChatCore", package: "Chat"),
            ],
            path: "Tests/ServerProtocolTests"
        ),
        .testTarget(
            name: "ServerClientTests",
            dependencies: [
                "ServerClient",
                "ServerProtocol",
                .product(name: "ChatCore", package: "Chat"),
            ],
            path: "Tests/ServerClientTests"
        ),
    ]
)
