// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ACPClientKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ACPClientKit",
            targets: ["ACPClientKit"]
        ),
    ],
    targets: [
        .target(
            name: "ACPClientKit",
            path: "Sources/ACPClientKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "ACPClientKitTestAdapter",
            dependencies: ["ACPClientKit"],
            path: "Sources/ACPClientKitTestAdapter",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ACPClientKitTests",
            dependencies: [
                "ACPClientKit",
                "ACPClientKitTestAdapter",
            ],
            path: "Tests/ACPClientKitTests"
        ),
    ]
)
