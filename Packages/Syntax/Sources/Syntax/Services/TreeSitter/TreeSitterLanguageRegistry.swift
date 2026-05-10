import Foundation
import SwiftTreeSitter

public enum TreeSitterLanguageRegistry {
    public static func bundledLanguage(
        for identifier: String
    ) -> BundledTreeSitterLanguage? {
        languageByIdentifier[normalized(identifier)]
    }

    public static func configuration(
        forLanguageIdentifier identifier: String
    ) -> LanguageConfiguration? {
        guard let bundledLanguage = bundledLanguage(for: identifier) else {
            return nil
        }

        return try? TreeSitterLanguageConfigurationProvider.configuration(
            for: bundledLanguage
        )
    }

    public static func configuration(
        forInjectionName name: String
    ) -> LanguageConfiguration? {
        configuration(forLanguageIdentifier: name)
    }

    private static func normalized(_ identifier: String) -> String {
        identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static let languageByIdentifier: [String: BundledTreeSitterLanguage] = {
        var aliases: [String: BundledTreeSitterLanguage] = [:]

        for entry in identifierAliases {
            for identifier in entry.identifiers {
                aliases[identifier] = entry.language
            }
        }

        return aliases
    }()

    private static let identifierAliases: [(language: BundledTreeSitterLanguage, identifiers: [String])] = [
        (.shellscript, ["bash", "sh", "zsh", "fish", "shell", "shellscript"]),
        (.c, ["c"]),
        (.cpp, ["c++", "cc", "cpp", "cxx", "hpp", "hxx"]),
        (.csharp, ["csharp", "cs"]),
        (.css, ["css"]),
        (.go, ["go"]),
        (.html, ["html"]),
        (.java, ["java"]),
        (.javascript, ["javascript", "js", "mjs", "cjs"]),
        (.json, ["json", "jsonc"]),
        (.jsx, ["jsx"]),
        (.kotlin, ["kotlin", "kt", "kts"]),
        (.lua, ["lua"]),
        (.make, ["make"]),
        (.markdown, ["markdown", "md"]),
        (.markdownInline, ["markdown_inline", "markdown-inline"]),
        (.php, ["php"]),
        (.python, ["python", "py"]),
        (.ruby, ["ruby", "rb"]),
        (.rust, ["rust", "rs"]),
        (.sql, ["sql"]),
        (.swift, ["swift"]),
        (.toml, ["toml"]),
        (.typescript, ["typescript", "ts", "mts", "cts"]),
        (.tsx, ["tsx"]),
        (.yaml, ["yaml", "yml"])
    ]
}
