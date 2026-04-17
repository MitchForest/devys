// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Canvas",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Canvas", targets: ["Canvas"])
    ],
    dependencies: [
        .package(path: "../UI")
    ],
    targets: [
        .target(
            name: "Canvas",
            dependencies: [
                .product(name: "UI", package: "UI")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CanvasTests",
            dependencies: ["Canvas"]
        )
    ]
)
