// swift-tools-version: 6.3

import PackageDescription

// Same TCA26 pin as devys-old so the established idiom carries over unchanged.
let tcaRevision = "f670b08d91e9026e614e8b7aa6faea4dfa1313af"

let pureSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency=complete"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let uiSwiftSettings: [SwiftSetting] = [.defaultIsolation(MainActor.self)] + pureSwiftSettings

let package = Package(
    name: "DevysKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "DevysWorkspace", targets: ["DevysWorkspace"]),
        .library(name: "DevysDesignSystem", targets: ["DevysDesignSystem"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/TCA26",
            revision: tcaRevision,
            traits: ["Dependencies"]
        ),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.14.1"),
        // TCA26 pins swift-clocks to the clocks-2 branch; SwiftPM cannot mix a
        // revision requirement with that branch requirement in one graph.
        .package(url: "https://github.com/pointfreeco/swift-clocks", branch: "clocks-2"),
        .package(path: "../DevysTerminal")
    ],
    targets: [
        // The Face: avatar identity and expression, no UI framework.
        .target(name: "DevysCharacter", swiftSettings: pureSwiftSettings),
        .target(
            name: "DevysDesignSystem",
            dependencies: ["DevysCharacter"],
            swiftSettings: uiSwiftSettings
        ),
        // The Devys HTTP API contract and device session storage; fixtures in debug builds only.
        .target(
            name: "DevysClient",
            dependencies: [
                "DevysCharacter",
                .product(name: "Dependencies", package: "swift-dependencies")
            ],
            swiftSettings: pureSwiftSettings
        ),
        // The bundled web document surfaces (diffs first) in a web view; `bun run surfaces:build`.
        .target(
            name: "DevysSurfaces",
            resources: [.copy("Resources/surfaces")],
            swiftSettings: uiSwiftSettings
        ),
        // On-device speech: SpeechAnalyzer capture and AVSpeechSynthesizer playback.
        .target(
            name: "DevysSpeechLive",
            dependencies: ["DevysClient"],
            swiftSettings: pureSwiftSettings
        ),
        // Features and screens for the business workspace on macOS, iPhone and iPad.
        .target(
            name: "DevysWorkspace",
            dependencies: [
                "DevysCharacter",
                "DevysClient",
                "DevysSpeechLive",
                "DevysDesignSystem",
                "DevysSurfaces",
                .product(name: "DevysTerminal", package: "DevysTerminal"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies")
            ],
            swiftSettings: uiSwiftSettings
        ),
        .testTarget(
            name: "DevysCharacterTests",
            dependencies: ["DevysCharacter"],
            swiftSettings: pureSwiftSettings
        ),
        .testTarget(
            name: "DevysSurfacesTests",
            dependencies: ["DevysSurfaces"],
            swiftSettings: uiSwiftSettings
        ),
        .testTarget(
            name: "DevysClientTests",
            dependencies: ["DevysClient"],
            swiftSettings: pureSwiftSettings
        ),
        .testTarget(
            name: "DevysWorkspaceTests",
            dependencies: [
                "DevysClient",
                "DevysWorkspace",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies")
            ],
            swiftSettings: uiSwiftSettings
        )
    ]
)
