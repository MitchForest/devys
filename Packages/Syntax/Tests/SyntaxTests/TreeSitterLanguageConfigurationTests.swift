import Testing
import SwiftTreeSitter
@testable import Syntax

@Suite("Tree-sitter Language Configuration Tests")
struct TreeSitterLanguageConfigurationTests {
    @Test("Loads bundled Tree-sitter configurations for all shipped languages")
    func testLoadBundledConfigurations() throws {
        for language in BundledTreeSitterLanguage.allCases {
            let configuration: LanguageConfiguration
            do {
                configuration = try TreeSitterLanguageConfigurationProvider.configuration(for: language)
            } catch {
                Issue.record("Failed to load configuration for \(language.languageID): \(error)")
                continue
            }

            #expect(!configuration.name.isEmpty)
            #expect(configuration.queries[.highlights] != nil)
            #expect(configuration.queries[.locals] != nil)
            #expect(configuration.queries[.injections] != nil)
        }
    }

    @Test("Language detection parity stays backed by the Tree-sitter registry")
    func parityDetectionResolvesToBundledConfigurations() {
        for fixture in parityLanguageFixtures {
            let detectedLanguage = LanguageDetector.detect(from: fixture.fileName)
            #expect(detectedLanguage == fixture.language)
            #expect(
                TreeSitterLanguageRegistry.bundledLanguage(for: detectedLanguage)?.languageID == fixture.language
            )
            #expect(
                TreeSitterLanguageRegistry.configuration(forLanguageIdentifier: detectedLanguage) != nil
            )
        }
    }

    @Test("Shipped injection aliases resolve to real Tree-sitter configurations")
    func shippedInjectionAliasesResolve() {
        for alias in shippedInjectionAliases {
            #expect(TreeSitterLanguageRegistry.configuration(forInjectionName: alias) != nil)
        }
    }
}

private let parityLanguageFixtures: [(fileName: String, language: String)] = [
    ("sample.c", "c"),
    ("sample.cpp", "cpp"),
    ("sample.cs", "csharp"),
    ("sample.css", "css"),
    ("sample.go", "go"),
    ("sample.html", "html"),
    ("sample.java", "java"),
    ("sample.js", "javascript"),
    ("sample.json", "json"),
    ("sample.jsx", "jsx"),
    ("sample.kt", "kotlin"),
    ("sample.lua", "lua"),
    ("sample.mk", "make"),
    ("sample.md", "markdown"),
    ("sample.php", "php"),
    ("sample.py", "python"),
    ("sample.rb", "ruby"),
    ("sample.rs", "rust"),
    ("sample.sh", "shellscript"),
    ("sample.sql", "sql"),
    ("sample.swift", "swift"),
    ("sample.ts", "typescript"),
    ("sample.tsx", "tsx"),
    ("sample.yaml", "yaml")
]

private let shippedInjectionAliases = [
    "css",
    "html",
    "javascript",
    "markdown_inline",
    "sql",
    "swift",
    "toml",
    "yaml"
]
