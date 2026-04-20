// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let ghosttyVTMacLibAbsolutePath = packageRoot + "/../../Vendor/Ghostty/libghostty-vt/macos-arm64/lib"
let ghosttyVTIOSLibAbsolutePath = packageRoot + "/../../Vendor/Ghostty/libghostty-vt/ios-arm64/lib"

let package = Package(
    name: "GhosttyTerminal",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "GhosttyTerminalCore", targets: ["GhosttyTerminalCore"]),
        .library(name: "GhosttyTerminal", targets: ["GhosttyTerminal"]),
    ],
    dependencies: [
        .package(path: "../SSH"),
        .package(path: "../Rendering"),
    ],
    targets: [
        .target(
            name: "CGhosttyVT",
            path: "Sources/CGhosttyVT",
            publicHeadersPath: "include"
        ),
        .target(
            name: "GhosttyTerminalCore",
            dependencies: [
                "CGhosttyVT",
                .product(name: "SSH", package: "SSH"),
            ],
            path: "Sources/GhosttyTerminalCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-L", ghosttyVTMacLibAbsolutePath,
                        "-lghostty-vt",
                        "-lsimdutf",
                        "-lhighway",
                    ],
                    .when(platforms: [.macOS])
                ),
                .unsafeFlags(
                    [
                        "-L", ghosttyVTIOSLibAbsolutePath,
                        "-lghostty-vt",
                        "-lsimdutf",
                        "-lhighway",
                    ],
                    .when(platforms: [.iOS])
                ),
                .linkedLibrary("c++", .when(platforms: [.macOS, .iOS])),
            ]
        ),
        .target(
            name: "GhosttyTerminal",
            dependencies: [
                "GhosttyTerminalCore",
                .product(name: "Rendering", package: "Rendering"),
            ],
            path: "Sources/GhosttyTerminal",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .linkedLibrary("c++", .when(platforms: [.macOS, .iOS])),
            ]
        ),
        .testTarget(
            name: "GhosttyTerminalTests",
            dependencies: ["GhosttyTerminal", "GhosttyTerminalCore"],
            path: "Tests/GhosttyTerminalTests"
        ),
    ]
)
