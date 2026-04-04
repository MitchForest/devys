// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Git",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Git",
            targets: ["Git"]
        )
    ],
    dependencies: [
        .package(path: "../Workspace"),
        .package(path: "../Text"),
        .package(path: "../Syntax"),
        .package(path: "../Rendering"),
        .package(path: "../UI")
    ],
    targets: [
        .target(
            name: "Git",
            dependencies: [
                .product(name: "Workspace", package: "Workspace"),
                "Text",
                "Syntax",
                .product(name: "Rendering", package: "Rendering"),
                "UI"
            ],
            path: "Sources/Git",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "GitTests",
            dependencies: [
                "Git",
                .product(name: "Rendering", package: "Rendering")
            ],
            path: "Tests/GitTests"
        )
    ]
)
