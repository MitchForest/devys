// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SSH",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SSH", targets: ["SSH"]),
    ],
    dependencies: [
        .package(path: "../RemoteCore"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.94.1"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.9.1"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.9.2"),
    ],
    targets: [
        .target(
            name: "SSH",
            dependencies: [
                .product(name: "RemoteCore", package: "RemoteCore"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "SSHTests",
            dependencies: ["SSH"]
        ),
    ]
)
