// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Browser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Browser",
            targets: ["Browser"]
        )
    ],
    dependencies: [
        .package(path: "../UI")
    ],
    targets: [
        .target(
            name: "Browser",
            dependencies: [
                .product(name: "UI", package: "UI")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
