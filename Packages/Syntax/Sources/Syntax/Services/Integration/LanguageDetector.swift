// LanguageDetector.swift
// Syntax language detection
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
        "cs": "csharp",
        "lua": "lua",
        "kt": "kotlin",
        "kts": "kotlin",
        
        // Other
        "yaml": "yaml",
        "yml": "yaml",
        "toml": "toml",
        "xml": "xml",
        "sh": "shellscript",
        "mk": "make",
        "bash": "shellscript",
        "zsh": "shellscript",
        "fish": "shellscript",
        "sql": "sql",
        "graphql": "graphql",
        "gql": "graphql",
        "vue": "vue",
        "svelte": "svelte"
    ]

    private static let specialFilenameMap: [String: String] = [
        "dockerfile": "dockerfile",
        "makefile": "make",
        "gnumakefile": "make",
        "rakefile": "ruby",
        "gemfile": "ruby",
        "podfile": "ruby",
        "fastfile": "ruby",
        "cmakelists.txt": "cmake",
        ".gitignore": "gitignore",
        ".gitattributes": "gitignore",
        ".gitmodules": "gitignore",
        ".env": "dotenv",
        ".env.local": "dotenv",
        ".env.development": "dotenv",
        ".env.production": "dotenv",
        "package.json": "json",
        "tsconfig.json": "json",
        "jsconfig.json": "json",
        "cargo.toml": "toml",
        "pyproject.toml": "toml",
        ".swiftlint.yml": "yaml",
        ".eslintrc.yml": "yaml"
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
        specialFilenameMap[filename]
    }
    
}
