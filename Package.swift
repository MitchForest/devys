// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Devys",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Devys",
            targets: ["Devys"]
        ),
    ],
    dependencies: [
        // Bonsplit - Tab bar and split pane system
        .package(url: "https://github.com/almonk/bonsplit.git", from: "1.1.1"),
        
        // Local packages
        .package(path: "Packages/DevysCore"),
        .package(path: "Packages/DevysSyntax"),
        .package(path: "Packages/DevysUI"),
    ],
    targets: [
        .executableTarget(
            name: "Devys",
            dependencies: [
                .product(name: "Bonsplit", package: "bonsplit"),
                "DevysCore",
                "DevysSyntax",
                "DevysUI",
            ],
            path: "Apps/Devys/Sources/Devys",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ]
)
