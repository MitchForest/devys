// swift-tools-version: 6.2

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let ghosttyVTMacLibAbsolutePath = packageRoot + "/../../Vendor/Ghostty/libghostty-vt/macos-arm64/lib"

let package = Package(
    name: "Terminal",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "TerminalVT", targets: ["TerminalVT"]),
        .library(name: "TerminalHost", targets: ["TerminalHost"]),
        .library(name: "TerminalComposer", targets: ["TerminalComposer"]),
        .library(name: "TerminalProduct", targets: ["TerminalProduct"]),
    ],
    dependencies: [
        .package(path: "../SSH"),
        .package(path: "../Rendering"),
        .package(path: "../UI"),
    ],
    targets: [
        .target(
            name: "CGhosttyVT",
            path: "Sources/CGhosttyVT",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TerminalVT",
            dependencies: [
                "CGhosttyVT",
                .product(name: "SSH", package: "SSH"),
                .product(name: "Rendering", package: "Rendering"),
            ],
            exclude: ["README.md"],
            swiftSettings: terminalSwiftSettings,
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
                .linkedLibrary("c++", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "TerminalHost",
            swiftSettings: terminalSwiftSettings
        ),
        .target(
            name: "TerminalComposer",
            dependencies: [
                .product(name: "UI", package: "UI"),
            ],
            swiftSettings: terminalSwiftSettings
        ),
        .target(
            name: "TerminalProduct",
            dependencies: [
                "TerminalVT",
                "TerminalHost",
                "TerminalComposer",
                .product(name: "UI", package: "UI"),
            ],
            swiftSettings: terminalSwiftSettings
        ),
        .testTarget(
            name: "TerminalVTTests",
            dependencies: ["TerminalVT"]
        ),
        .testTarget(
            name: "TerminalHostTests",
            dependencies: ["TerminalHost"]
        ),
        .testTarget(
            name: "TerminalComposerTests",
            dependencies: ["TerminalComposer"]
        ),
        .testTarget(
            name: "TerminalProductTests",
            dependencies: ["TerminalProduct", "TerminalComposer", "TerminalHost"]
        ),
    ]
)

let terminalSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableExperimentalFeature("StrictConcurrency"),
]
