// DevysSyntax.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// DevysSyntax provides Shiki-compatible syntax highlighting using TextMate grammars.
///
/// ## Overview
/// This package implements a native Swift TextMate tokenizer that replicates
/// Shiki's exact syntax highlighting across all surfaces in Devys:
///
/// 1. **File Viewer** (M1) — Read-only file preview with highlighting
/// 2. **Agent Chat** (M2) — Code blocks in Claude/Codex responses
/// 3. **Git Diffs** (M3) — Syntax-highlighted diff lines
/// 4. **Code Editor** (M4) — Full editor integration with incremental tokenization
/// 5. **Terminal** (M5) — Theme sync (ANSI palette from Shiki theme)
///
/// ## Architecture
/// The package uses a dual-layer system similar to VS Code:
/// - **TextMate** (Oniguruma regex) — Visual accuracy, theme ecosystem, syntax coloring
/// - **TreeSitter** (incremental parsing) — Code intelligence (separate package)
///
/// ## Bundled Resources
/// - 17 TextMate grammar JSON files
/// - 13 Shiki theme JSON files
public enum DevysSyntax {
    /// Current version of the DevysSyntax package.
    public static let version = "1.0.0"
    
    /// Supported language identifiers.
    public static let supportedLanguages: Set<String> = [
        "swift", "python", "javascript", "typescript", "tsx", "jsx",
        "html", "css", "json", "markdown", "ruby", "rust", "c", "cpp",
        "go", "php", "shellscript"
    ]
    
    /// Available theme names.
    public static let availableThemes: [String] = [
        // Dark themes
        "github-dark",
        "github-dark-dimmed",
        "vitesse-dark",
        "one-dark-pro",
        "tokyo-night",
        "dracula",
        "nord",
        "monokai",
        "catppuccin-mocha",
        // Light themes
        "github-light",
        "vitesse-light",
        "one-light",
        "catppuccin-latte"
    ]
}
