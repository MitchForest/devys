// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Browser",
    platforms: [
        .macOS(.v26)
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
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "BrowserTests",
            dependencies: ["Browser"]
        )
    ]
)
