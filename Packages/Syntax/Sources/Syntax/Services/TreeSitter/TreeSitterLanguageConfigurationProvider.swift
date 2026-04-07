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
        let descriptor = try descriptor(for: language)
        return try makeConfiguration(
            language: descriptor.makeLanguage(),
            name: descriptor.name,
            bundledLanguage: descriptor.bundledLanguage
        )
    }

    public static func c() throws -> LanguageConfiguration {
        try configuration(for: .c)
    }

    public static func cpp() throws -> LanguageConfiguration {
        try configuration(for: .cpp)
    }

    public static func csharp() throws -> LanguageConfiguration {
        try configuration(for: .csharp)
    }

    public static func css() throws -> LanguageConfiguration {
        try configuration(for: .css)
    }

    public static func html() throws -> LanguageConfiguration {
        try configuration(for: .html)
    }

    public static func go() throws -> LanguageConfiguration {
        try configuration(for: .go)
    }

    public static func java() throws -> LanguageConfiguration {
        try configuration(for: .java)
    }

    public static func javascript() throws -> LanguageConfiguration {
        try configuration(for: .javascript)
    }

    public static func json() throws -> LanguageConfiguration {
        try configuration(for: .json)
    }

    public static func jsx() throws -> LanguageConfiguration {
        try configuration(for: .jsx)
    }

    public static func markdown() throws -> LanguageConfiguration {
        try configuration(for: .markdown)
    }

    public static func markdownInline() throws -> LanguageConfiguration {
        try configuration(for: .markdownInline)
    }

    public static func python() throws -> LanguageConfiguration {
        try configuration(for: .python)
    }

    public static func kotlin() throws -> LanguageConfiguration {
        try configuration(for: .kotlin)
    }

    public static func lua() throws -> LanguageConfiguration {
        try configuration(for: .lua)
    }

    public static func make() throws -> LanguageConfiguration {
        try configuration(for: .make)
    }

    public static func php() throws -> LanguageConfiguration {
        try configuration(for: .php)
    }

    public static func rust() throws -> LanguageConfiguration {
        try configuration(for: .rust)
    }

    public static func ruby() throws -> LanguageConfiguration {
        try configuration(for: .ruby)
    }

    public static func shellscript() throws -> LanguageConfiguration {
        try configuration(for: .shellscript)
    }

    public static func sql() throws -> LanguageConfiguration {
        try configuration(for: .sql)
    }

    public static func swift() throws -> LanguageConfiguration {
        try configuration(for: .swift)
    }

    public static func toml() throws -> LanguageConfiguration {
        try configuration(for: .toml)
    }

    public static func typescript() throws -> LanguageConfiguration {
        try configuration(for: .typescript)
    }

    public static func tsx() throws -> LanguageConfiguration {
        try configuration(for: .tsx)
    }

    public static func yaml() throws -> LanguageConfiguration {
        try configuration(for: .yaml)
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

    private static func descriptor(
        for language: BundledTreeSitterLanguage
    ) throws -> TreeSitterLanguageDescriptor {
        guard let descriptor = descriptors[language] else {
            throw TreeSitterLanguageConfigurationProviderError.invalidConfiguration
        }

        return descriptor
    }

    private static let descriptors: [BundledTreeSitterLanguage: TreeSitterLanguageDescriptor] = [
        .c: descriptor(name: "C", bundledLanguage: .c, makeLanguage: Language(tree_sitter_c())),
        .cpp: descriptor(name: "C++", bundledLanguage: .cpp, makeLanguage: Language(tree_sitter_cpp())),
        .csharp: descriptor(name: "C#", bundledLanguage: .csharp, makeLanguage: Language(tree_sitter_c_sharp())),
        .css: descriptor(name: "CSS", bundledLanguage: .css, makeLanguage: Language(tree_sitter_css())),
        .go: descriptor(name: "Go", bundledLanguage: .go, makeLanguage: Language(tree_sitter_go())),
        .html: descriptor(name: "HTML", bundledLanguage: .html, makeLanguage: Language(tree_sitter_html())),
        .java: descriptor(name: "Java", bundledLanguage: .java, makeLanguage: Language(tree_sitter_java())),
        .javascript: descriptor(
            name: "JavaScript",
            bundledLanguage: .javascript,
            makeLanguage: Language(tree_sitter_tsx())
        ),
        .json: descriptor(name: "JSON", bundledLanguage: .json, makeLanguage: Language(tree_sitter_json())),
        .jsx: descriptor(name: "JSX", bundledLanguage: .jsx, makeLanguage: Language(tree_sitter_tsx())),
        .kotlin: descriptor(
            name: "Kotlin",
            bundledLanguage: .kotlin,
            makeLanguage: Language(tree_sitter_kotlin())
        ),
        .lua: descriptor(name: "Lua", bundledLanguage: .lua, makeLanguage: Language(tree_sitter_lua())),
        .make: descriptor(name: "Make", bundledLanguage: .make, makeLanguage: Language(tree_sitter_make())),
        .markdown: descriptor(
            name: "Markdown",
            bundledLanguage: .markdown,
            makeLanguage: Language(tree_sitter_markdown())
        ),
        .markdownInline: descriptor(
            name: "MarkdownInline",
            bundledLanguage: .markdownInline,
            makeLanguage: Language(tree_sitter_markdown_inline())
        ),
        .php: descriptor(name: "PHP", bundledLanguage: .php, makeLanguage: Language(tree_sitter_php())),
        .python: descriptor(
            name: "Python",
            bundledLanguage: .python,
            makeLanguage: Language(tree_sitter_python())
        ),
        .ruby: descriptor(name: "Ruby", bundledLanguage: .ruby, makeLanguage: Language(tree_sitter_ruby())),
        .rust: descriptor(name: "Rust", bundledLanguage: .rust, makeLanguage: Language(tree_sitter_rust())),
        .shellscript: descriptor(
            name: "ShellScript",
            bundledLanguage: .shellscript,
            makeLanguage: Language(tree_sitter_bash())
        ),
        .sql: descriptor(name: "SQL", bundledLanguage: .sql, makeLanguage: Language(tree_sitter_sql())),
        .swift: descriptor(name: "Swift", bundledLanguage: .swift, makeLanguage: Language(tree_sitter_swift())),
        .toml: descriptor(name: "TOML", bundledLanguage: .toml, makeLanguage: Language(tree_sitter_toml())),
        .typescript: descriptor(
            name: "TypeScript",
            bundledLanguage: .typescript,
            makeLanguage: Language(tree_sitter_typescript())
        ),
        .tsx: descriptor(name: "TSX", bundledLanguage: .tsx, makeLanguage: Language(tree_sitter_tsx())),
        .yaml: descriptor(name: "YAML", bundledLanguage: .yaml, makeLanguage: Language(tree_sitter_yaml()))
    ]

    private static func descriptor(
        name: String,
        bundledLanguage: BundledTreeSitterLanguage,
        makeLanguage: @autoclosure @escaping @Sendable () -> Language
    ) -> TreeSitterLanguageDescriptor {
        TreeSitterLanguageDescriptor(
            name: name,
            bundledLanguage: bundledLanguage,
            makeLanguage: makeLanguage
        )
    }
}

private struct TreeSitterLanguageDescriptor: Sendable {
    let name: String
    let bundledLanguage: BundledTreeSitterLanguage
    let makeLanguage: @Sendable () -> Language
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
