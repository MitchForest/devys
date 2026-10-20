// swift-tools-version: 6.3

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableExperimentalFeature("StrictConcurrency=complete"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

/// The native terminal (.docs/COMPONENTS.md#terminal): libghostty-vt for terminal state and a
/// Metal renderer, ported from the owner's devys-old ComputerKit. The PTY lives on the Mac host;
/// clients reach it through `TerminalSurfacePTYClient`, which Devys implements over a WebSocket.
let package = Package(
    name: "DevysTerminal",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "DevysTerminal", targets: ["TerminalCore", "TerminalSurfaceCore", "TerminalSurface"])
    ],
    targets: [
        // libghostty-vt (with simdutf and highway) at the pin in vendor/ghostty/VERSION; built by
        // `bun run ghostty:build`. C++ inside, so the shim links c++.
        .binaryTarget(name: "GhosttyVTBinary", path: "Vendor/GhosttyVT.xcframework"),
        // Exposes the libghostty-vt headers as a Clang module.
        .target(
            name: "CGhosttyVT",
            dependencies: ["GhosttyVTBinary"],
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("c++")]
        ),
        .target(name: "TerminalCore", swiftSettings: swiftSettings),
        .target(name: "TerminalVT", dependencies: ["TerminalCore", "CGhosttyVT"], swiftSettings: swiftSettings),
        // Metal renderer: pipelines, glyph atlas, cell packing and the bundled symbol font.
        .target(
            name: "TerminalMetal",
            dependencies: ["TerminalVT"],
            resources: [.process("Resources/TerminalShaders.metal"), .copy("Resources/Fonts")],
            swiftSettings: swiftSettings
        ),
        // Render session, resize, scroll and the PTY seam; no platform UI.
        .target(name: "TerminalSurfaceCore", dependencies: ["TerminalCore", "TerminalVT"], swiftSettings: swiftSettings),
        // The macOS and iOS host views over the surface runtime, on the main actor.
        .target(
            name: "TerminalSurface",
            dependencies: ["TerminalCore", "TerminalVT", "TerminalMetal", "TerminalSurfaceCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)] + swiftSettings
        ),
        .testTarget(
            name: "DevysTerminalTests",
            dependencies: ["TerminalCore", "TerminalVT", "TerminalMetal", "TerminalSurfaceCore"],
            swiftSettings: swiftSettings
        )
    ],
    cLanguageStandard: .c11
)
