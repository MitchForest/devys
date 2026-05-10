import Foundation

public struct TreeSitterQuerySet: Sendable, Equatable {
    public let highlights: String
    public let locals: String
    public let injections: String

    public init(
        highlights: String,
        locals: String,
        injections: String
    ) {
        self.highlights = highlights
        self.locals = locals
        self.injections = injections
    }
}

public enum BundledTreeSitterLanguage: String, CaseIterable, Sendable {
    case c
    case cpp
    case csharp
    case css
    case go
    case html
    case java
    case javascript
    case json
    case jsx
    case kotlin
    case lua
    case make
    case markdown
    case markdownInline = "markdown_inline"
    case php
    case python
    case ruby
    case rust
    case shellscript
    case sql
    case swift
    case toml
    case typescript
    case tsx
    case yaml

    public var languageID: String {
        rawValue
    }

    public var querySubdirectory: String {
        "TreeSitterQueries/\(rawValue)"
    }

    public func loadQueries(bundle: Bundle) throws -> TreeSitterQuerySet {
        try TreeSitterQuerySet(
            highlights: loadQuery(named: "highlights", bundle: bundle),
            locals: loadQuery(named: "locals", bundle: bundle),
            injections: loadQuery(named: "injections", bundle: bundle)
        )
    }

    public func loadQueries() throws -> TreeSitterQuerySet {
        try loadQueries(bundle: .moduleBundle)
    }

    private func loadQuery(named name: String, bundle: Bundle) throws -> String {
        guard let url = bundle.url(
            forResource: name,
            withExtension: "scm",
            subdirectory: querySubdirectory
        ) else {
            throw BundledTreeSitterLanguageError.missingQuery(
                languageID: languageID,
                queryName: name
            )
        }

        return try String(contentsOf: url, encoding: .utf8)
    }
}

public enum BundledTreeSitterLanguageError: Error, LocalizedError, Sendable {
    case missingQuery(languageID: String, queryName: String)

    public var errorDescription: String? {
        switch self {
        case let .missingQuery(languageID, queryName):
            "Missing Tree-sitter query '\(queryName)' for language '\(languageID)'."
        }
    }
}
