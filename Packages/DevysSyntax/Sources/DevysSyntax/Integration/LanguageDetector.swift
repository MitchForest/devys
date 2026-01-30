// LanguageDetector.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Detects the language of a file based on its extension or content.
public enum LanguageDetector {
    /// Maps file extensions to language identifiers.
    private static let extensionMap: [String: String] = [
        // High priority (most common)
        "swift": "swift",
        "py": "python",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "ts": "typescript",
        "mts": "typescript",
        "cts": "typescript",
        "tsx": "tsx",
        "jsx": "jsx",
        "html": "html",
        "htm": "html",
        "css": "css",
        "scss": "scss",
        "sass": "sass",
        "json": "json",
        "jsonc": "json",
        "md": "markdown",
        "markdown": "markdown",
        
        // Medium priority
        "rb": "ruby",
        "rs": "rust",
        "c": "c",
        "h": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "cxx": "cpp",
        "hpp": "cpp",
        "hxx": "cpp",
        "go": "go",
        "php": "php",
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        
        // Other
        "yaml": "yaml",
        "yml": "yaml",
        "toml": "toml",
        "xml": "xml",
        "sh": "shellscript",
        "bash": "shellscript",
        "zsh": "shellscript",
        "fish": "shellscript",
        "sql": "sql",
        "graphql": "graphql",
        "gql": "graphql",
        "vue": "vue",
        "svelte": "svelte"
    ]
    
    /// Detects the language identifier from a file path.
    /// - Parameter filePath: The file path or URL path.
    /// - Returns: The detected language identifier, or "plaintext" if unknown.
    public static func detect(from filePath: String?) -> String {
        guard let path = filePath else { return "plaintext" }
        
        let filename = (path as NSString).lastPathComponent.lowercased()
        
        // Check for special filenames
        if let special = detectSpecialFilename(filename) {
            return special
        }
        
        let ext = (path as NSString).pathExtension.lowercased()
        return extensionMap[ext] ?? "plaintext"
    }
    
    /// Detects the language identifier from a URL.
    /// - Parameter url: The file URL.
    /// - Returns: The detected language identifier, or "plaintext" if unknown.
    public static func detect(from url: URL) -> String {
        detect(from: url.path)
    }
    
    /// Checks for special filenames that indicate a specific language.
    private static func detectSpecialFilename(_ filename: String) -> String? {
        switch filename {
        case "dockerfile": return "dockerfile"
        case "makefile", "gnumakefile": return "makefile"
        case "rakefile", "gemfile", "podfile", "fastfile": return "ruby"
        case "cmakelists.txt": return "cmake"
        case ".gitignore", ".gitattributes", ".gitmodules": return "gitignore"
        case ".env", ".env.local", ".env.development", ".env.production": return "dotenv"
        case "package.json", "tsconfig.json", "jsconfig.json": return "json"
        case "cargo.toml", "pyproject.toml": return "toml"
        case ".swiftlint.yml", ".eslintrc.yml": return "yaml"
        default: return nil
        }
    }
    
    /// Returns the display name for a language identifier.
    /// - Parameter languageId: The language identifier.
    /// - Returns: Human-readable language name.
    public static func displayName(for languageId: String) -> String {
        switch languageId {
        case "swift": return "Swift"
        case "python": return "Python"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        case "tsx": return "TSX"
        case "jsx": return "JSX"
        case "html": return "HTML"
        case "css": return "CSS"
        case "scss": return "SCSS"
        case "json": return "JSON"
        case "markdown": return "Markdown"
        case "ruby": return "Ruby"
        case "rust": return "Rust"
        case "c": return "C"
        case "cpp": return "C++"
        case "go": return "Go"
        case "php": return "PHP"
        case "java": return "Java"
        case "kotlin": return "Kotlin"
        case "yaml": return "YAML"
        case "toml": return "TOML"
        case "xml": return "XML"
        case "shellscript": return "Shell"
        case "sql": return "SQL"
        case "dockerfile": return "Dockerfile"
        case "plaintext": return "Plain Text"
        default: return languageId.capitalized
        }
    }
}
