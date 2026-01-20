// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DevysFeature",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "DevysFeature",
            targets: ["DevysFeature"]
        ),
    ],
    dependencies: [
        // Terminal emulator (Sprint 7)
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        // Note: CodeEditSourceEditor will be added in Sprint 9
    ],
    targets: [
        .target(
            name: "DevysFeature",
            dependencies: [
                "SwiftTerm",
            ]
        ),
        .testTarget(
            name: "DevysFeatureTests",
            dependencies: [
                "DevysFeature"
            ]
        ),
    ]
)
