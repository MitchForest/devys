// swift-tools-version: 6.0
// MetalASCII - GPU-accelerated ASCII art rendering with dithering and animation

import PackageDescription

let package = Package(
    name: "MetalASCII",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Library for reusable ASCII rendering infrastructure
        .library(
            name: "MetalASCII",
            targets: ["MetalASCII"]
        ),
        // Standalone executable for running ASCII art projects
        .executable(
            name: "ascii-runner",
            targets: ["MetalASCIIRunner"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MetalASCII",
            dependencies: [],
            resources: [
                .process("Core/Shaders"),
                .process("Projects/Particle/ParticleShaders.metal"),
                .copy("Resources/Artwork")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "MetalASCIIRunner",
            dependencies: ["MetalASCII"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "MetalASCIITests",
            dependencies: ["MetalASCII"]
        )
    ]
)
