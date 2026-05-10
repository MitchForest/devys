// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Git",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "Git", targets: ["Git"])
    ],
    dependencies: [
        .package(path: "../Diff")
    ],
    targets: [
        .target(
            name: "Git",
            dependencies: [
                "Diff"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "GitTests",
            dependencies: ["Git"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
