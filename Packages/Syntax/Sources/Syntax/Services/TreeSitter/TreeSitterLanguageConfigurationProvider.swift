import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSharp
import TreeSitterCSS
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterKotlin
import TreeSitterLua
import TreeSitterMake
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterPHP
import TreeSitterPython
import TreeSitterRuby
import TreeSitterSQL
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTypeScript
import TreeSitterTSX
import TreeSitterYAML

public enum TreeSitterLanguageConfigurationProvider {
    public static func configuration(
        for language: BundledTreeSitterLanguage
    ) throws -> LanguageConfiguration {
        switch language {
        case .cpp:
            try cpp()
        case .csharp:
            try csharp()
        case .c:
            try c()
        case .css:
            try css()
        case .go:
            try go()
        case .html:
            try html()
        case .java:
            try java()
        case .javascript:
            try javascript()
        case .json:
            try json()
        case .jsx:
            try jsx()
        case .kotlin:
            try kotlin()
        case .lua:
            try lua()
        case .make:
            try make()
        case .markdown:
            try markdown()
        case .markdownInline:
            try markdownInline()
        case .php:
            try php()
        case .python:
            try python()
        case .ruby:
            try ruby()
        case .rust:
            try rust()
        case .shellscript:
            try shellscript()
        case .sql:
            try sql()
        case .swift:
            try swift()
        case .toml:
            try toml()
        case .typescript:
            try typescript()
        case .tsx:
            try tsx()
        case .yaml:
            try yaml()
        }
    }

    public static func c() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_c()),
            name: "C",
            bundledLanguage: .c
        )
    }

    public static func cpp() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_cpp()),
            name: "C++",
            bundledLanguage: .cpp
        )
    }

    public static func csharp() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_c_sharp()),
            name: "C#",
            bundledLanguage: .csharp
        )
    }

    public static func css() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_css()),
            name: "CSS",
            bundledLanguage: .css
        )
    }

    public static func html() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_html()),
            name: "HTML",
            bundledLanguage: .html
        )
    }

    public static func go() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_go()),
            name: "Go",
            bundledLanguage: .go
        )
    }

    public static func java() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_java()),
            name: "Java",
            bundledLanguage: .java
        )
    }

    public static func javascript() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_tsx()),
            name: "JavaScript",
            bundledLanguage: .javascript
        )
    }

    public static func json() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_json()),
            name: "JSON",
            bundledLanguage: .json
        )
    }

    public static func jsx() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_tsx()),
            name: "JSX",
            bundledLanguage: .jsx
        )
    }

    public static func markdown() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_markdown()),
            name: "Markdown",
            bundledLanguage: .markdown
        )
    }

    public static func markdownInline() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_markdown_inline()),
            name: "MarkdownInline",
            bundledLanguage: .markdownInline
        )
    }

    public static func python() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_python()),
            name: "Python",
            bundledLanguage: .python
        )
    }

    public static func kotlin() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_kotlin()),
            name: "Kotlin",
            bundledLanguage: .kotlin
        )
    }

    public static func lua() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_lua()),
            name: "Lua",
            bundledLanguage: .lua
        )
    }

    public static func make() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_make()),
            name: "Make",
            bundledLanguage: .make
        )
    }

    public static func php() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_php()),
            name: "PHP",
            bundledLanguage: .php
        )
    }

    public static func rust() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_rust()),
            name: "Rust",
            bundledLanguage: .rust
        )
    }

    public static func ruby() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_ruby()),
            name: "Ruby",
            bundledLanguage: .ruby
        )
    }

    public static func shellscript() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_bash()),
            name: "ShellScript",
            bundledLanguage: .shellscript
        )
    }

    public static func sql() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_sql()),
            name: "SQL",
            bundledLanguage: .sql
        )
    }

    public static func swift() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_swift()),
            name: "Swift",
            bundledLanguage: .swift
        )
    }

    public static func toml() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_toml()),
            name: "TOML",
            bundledLanguage: .toml
        )
    }

    public static func typescript() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_typescript()),
            name: "TypeScript",
            bundledLanguage: .typescript
        )
    }

    public static func tsx() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_tsx()),
            name: "TSX",
            bundledLanguage: .tsx
        )
    }

    public static func yaml() throws -> LanguageConfiguration {
        try makeConfiguration(
            language: Language(tree_sitter_yaml()),
            name: "YAML",
            bundledLanguage: .yaml
        )
    }

    private static func makeConfiguration(
        language: Language,
        name: String,
        bundledLanguage: BundledTreeSitterLanguage
    ) throws -> LanguageConfiguration {
        let querySet = try bundledLanguage.loadQueries()
        return LanguageConfiguration(
            language,
            name: name,
            queries: try compileQueries(
                querySet,
                language: language
            )
        )
    }

    private static func compileQueries(
        _ querySet: TreeSitterQuerySet,
        language: Language
    ) throws -> [Query.Definition: Query] {
        [
            .highlights: try Query(language: language, data: Data(querySet.highlights.utf8)),
            .locals: try Query(language: language, data: Data(querySet.locals.utf8)),
            .injections: try Query(language: language, data: Data(querySet.injections.utf8))
        ]
    }
}

public enum TreeSitterLanguageConfigurationProviderError: Error, LocalizedError, Sendable {
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Invalid Tree-sitter language configuration."
        }
    }
}
