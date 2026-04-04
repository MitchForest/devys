import Foundation
import SwiftTreeSitter

public enum TreeSitterLanguageRegistry {
    public static func bundledLanguage(
        for identifier: String
    ) -> BundledTreeSitterLanguage? {
        switch normalized(identifier) {
        case "bash", "sh", "zsh", "fish", "shell", "shellscript":
            .shellscript
        case "c":
            .c
        case "c++", "cc", "cpp", "cxx", "hpp", "hxx":
            .cpp
        case "csharp", "cs":
            .csharp
        case "css":
            .css
        case "go":
            .go
        case "html":
            .html
        case "java":
            .java
        case "javascript", "js", "mjs", "cjs":
            .javascript
        case "json", "jsonc":
            .json
        case "jsx":
            .jsx
        case "kotlin", "kt", "kts":
            .kotlin
        case "lua":
            .lua
        case "make":
            .make
        case "markdown", "md":
            .markdown
        case "markdown_inline", "markdown-inline":
            .markdownInline
        case "php":
            .php
        case "python", "py":
            .python
        case "ruby", "rb":
            .ruby
        case "rust", "rs":
            .rust
        case "sql":
            .sql
        case "swift":
            .swift
        case "toml":
            .toml
        case "typescript", "ts", "mts", "cts":
            .typescript
        case "tsx":
            .tsx
        case "yaml", "yml":
            .yaml
        default:
            nil
        }
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
}
