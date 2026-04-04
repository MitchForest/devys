// swift-tools-version: 6.0
// Syntax - Tree-sitter-backed syntax highlighting

import PackageDescription

let package = Package(
    name: "Syntax",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Syntax",
            targets: ["Syntax"]
        ),
    ],
    dependencies: [
        .package(path: "../Text"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", from: "0.10.0"),
        .package(
            url: "https://github.com/alex-pinkus/tree-sitter-swift.git",
            revision: "190aedc3042a2a1fcc17838eb05b2b2f2c0b7880"
        )
    ],
    targets: [
        .target(
            name: "TreeSitterBash",
            dependencies: [],
            path: "Sources/TreeSitterBash",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterC",
            dependencies: [],
            path: "Sources/TreeSitterC",
            sources: ["src/parser.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterCPP",
            dependencies: [],
            path: "Sources/TreeSitterCPP",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterCSharp",
            dependencies: [],
            path: "Sources/TreeSitterCSharp",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterCSS",
            dependencies: [],
            path: "Sources/TreeSitterCSS",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterGo",
            dependencies: [],
            path: "Sources/TreeSitterGo",
            sources: ["src/parser.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterHTML",
            dependencies: [],
            path: "Sources/TreeSitterHTML",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterJava",
            dependencies: [],
            path: "Sources/TreeSitterJava",
            sources: ["src/parser.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterJavaScript",
            dependencies: [],
            path: "Sources/TreeSitterJavaScript",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterJSON",
            dependencies: [],
            path: "Sources/TreeSitterJSON",
            sources: ["src/parser.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterKotlin",
            dependencies: [],
            path: "Sources/TreeSitterKotlin",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterLua",
            dependencies: [],
            path: "Sources/TreeSitterLua",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterMake",
            dependencies: [],
            path: "Sources/TreeSitterMake",
            sources: ["src/parser.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterMarkdown",
            dependencies: [],
            path: "Sources/TreeSitterMarkdown",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterMarkdownInline",
            dependencies: [],
            path: "Sources/TreeSitterMarkdownInline",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterPHP",
            dependencies: [],
            path: "Sources/TreeSitterPHP",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterPython",
            dependencies: [],
            path: "Sources/TreeSitterPython",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterRuby",
            dependencies: [],
            path: "Sources/TreeSitterRuby",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterSQL",
            dependencies: [],
            path: "Sources/TreeSitterSQL",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterRust",
            dependencies: [],
            path: "Sources/TreeSitterRust",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterTOML",
            dependencies: [],
            path: "Sources/TreeSitterTOML",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterTypeScript",
            dependencies: [],
            path: "Sources/TreeSitterTypeScript",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterTSX",
            dependencies: [],
            path: "Sources/TreeSitterTSX",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "TreeSitterYAML",
            dependencies: [],
            path: "Sources/TreeSitterYAML",
            sources: [
                "src/parser.c",
                "src/scanner.c",
                "src/schema.core.c",
                "src/schema.json.c",
                "src/schema.legacy.c"
            ],
            publicHeadersPath: "bindings/swift",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("../TreeSitterSupport/include")
            ]
        ),
        .target(
            name: "Syntax",
            dependencies: [
                "Text",
                "TreeSitterBash",
                "TreeSitterC",
                "TreeSitterCPP",
                "TreeSitterCSharp",
                "TreeSitterCSS",
                "TreeSitterGo",
                "TreeSitterHTML",
                "TreeSitterJava",
                "TreeSitterJavaScript",
                "TreeSitterJSON",
                "TreeSitterKotlin",
                "TreeSitterLua",
                "TreeSitterMake",
                "TreeSitterMarkdown",
                "TreeSitterMarkdownInline",
                "TreeSitterPHP",
                "TreeSitterPython",
                "TreeSitterRuby",
                "TreeSitterSQL",
                "TreeSitterRust",
                "TreeSitterTOML",
                "TreeSitterTypeScript",
                "TreeSitterTSX",
                "TreeSitterYAML",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "SwiftTreeSitterLayer", package: "swift-tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift")
            ],
            resources: [
                .process("Resources/TreeSitterThemes"),
                .copy("Resources/TreeSitterQueries")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        .testTarget(
            name: "SyntaxTests",
            dependencies: ["Syntax"],
            resources: [
                .process("Fixtures")
            ]
        ),
    ]
)
