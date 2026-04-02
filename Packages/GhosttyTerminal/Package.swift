// swift-tools-version: 6.0

import PackageDescription

let ghosttyKitRelativePath = "../../Vendor/Ghostty/GhosttyKit.xcframework"

let package = Package(
    name: "GhosttyTerminal",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "GhosttyTerminal", targets: ["GhosttyTerminal"]),
    ],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: ghosttyKitRelativePath
        ),
        .target(
            name: "GhosttyTerminal",
            dependencies: ["GhosttyKit"],
            path: "Sources/GhosttyTerminal",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedLibrary("c++", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "GhosttyTerminalTests",
            dependencies: ["GhosttyTerminal"],
            path: "Tests/GhosttyTerminalTests"
        ),
    ]
)
