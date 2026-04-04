// DiffTheme.swift
// Theme resolution for Metal diff rendering.

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif
import Syntax
import Rendering

struct DiffTheme: Sendable, Equatable {
    let background: SIMD4<Float>
    let foreground: SIMD4<Float>
    let lineNumber: SIMD4<Float>
    let gutterBackground: SIMD4<Float>
    let addedForeground: SIMD4<Float>
    let removedForeground: SIMD4<Float>
    let addedLineBackground: SIMD4<Float>
    let removedLineBackground: SIMD4<Float>
    let addedTextBackground: SIMD4<Float>
    let removedTextBackground: SIMD4<Float>
    let addedGutterBackground: SIMD4<Float>
    let removedGutterBackground: SIMD4<Float>
    let hunkHeaderBackground: SIMD4<Float>
    let hunkHeaderForeground: SIMD4<Float>
    let border: SIMD4<Float>

    init(theme: SyntaxTheme) {
        let resolved = DiffTheme.resolveColors(from: theme)
        background = resolved.background
        foreground = resolved.foreground
        lineNumber = resolved.lineNumber
        gutterBackground = resolved.gutterBackground
        addedForeground = resolved.addedForeground
        removedForeground = resolved.removedForeground
        addedLineBackground = resolved.addedLineBackground
        removedLineBackground = resolved.removedLineBackground
        addedTextBackground = resolved.addedTextBackground
        removedTextBackground = resolved.removedTextBackground
        addedGutterBackground = resolved.addedGutterBackground
        removedGutterBackground = resolved.removedGutterBackground
        hunkHeaderBackground = resolved.hunkHeaderBackground
        hunkHeaderForeground = resolved.hunkHeaderForeground
        border = resolved.border
    }

    @MainActor
    static func current() -> DiffTheme {
        let resolved = ThemeRegistry.resolvedTheme(name: ThemeRegistry.preferredThemeName)
        return DiffTheme(theme: resolved.theme)
    }
}


private struct ResolvedDiffColors {
    let background: SIMD4<Float>
    let foreground: SIMD4<Float>
    let lineNumber: SIMD4<Float>
    let gutterBackground: SIMD4<Float>
    let addedForeground: SIMD4<Float>
    let removedForeground: SIMD4<Float>
    let addedLineBackground: SIMD4<Float>
    let removedLineBackground: SIMD4<Float>
    let addedTextBackground: SIMD4<Float>
    let removedTextBackground: SIMD4<Float>
    let addedGutterBackground: SIMD4<Float>
    let removedGutterBackground: SIMD4<Float>
    let hunkHeaderBackground: SIMD4<Float>
    let hunkHeaderForeground: SIMD4<Float>
    let border: SIMD4<Float>
}

private extension DiffTheme {
    static func resolveColors(from theme: SyntaxTheme) -> ResolvedDiffColors {
        DiffThemePalette(theme: theme).resolve()
    }
}

private struct DiffThemePalette {
    let isDark: Bool
    let colors: [String: String]
    let bgHex: String
    let fgHex: String

    init(theme: SyntaxTheme) {
        isDark = theme.isDark
        colors = theme.colors
        bgHex = theme.editorBackground
        fgHex = theme.editorForeground
    }

    func resolve() -> ResolvedDiffColors {
        ResolvedDiffColors(
            background: background,
            foreground: foreground,
            lineNumber: lineNumber,
            gutterBackground: gutterBackground,
            addedForeground: addedForeground,
            removedForeground: removedForeground,
            addedLineBackground: addedLineBackground,
            removedLineBackground: removedLineBackground,
            addedTextBackground: addedTextBackground,
            removedTextBackground: removedTextBackground,
            addedGutterBackground: addedGutterBackground,
            removedGutterBackground: removedGutterBackground,
            hunkHeaderBackground: hunkHeaderBackground,
            hunkHeaderForeground: hunkHeaderForeground,
            border: border
        )
    }

    private var background: SIMD4<Float> {
        hexToLinearColor(bgHex)
    }

    private var foreground: SIMD4<Float> {
        hexToLinearColor(fgHex)
    }

    private var lineNumber: SIMD4<Float> {
        hex("editorLineNumber.foreground", isDark ? "#636363" : "#9e9e9e")
    }

    private var gutterBackground: SIMD4<Float> {
        hex("editorGutter.background", bgHex)
    }

    private var addedForeground: SIMD4<Float> {
        hexAny(["gitDecoration.addedResourceForeground"], isDark ? "#7FCB9B" : "#166534")
    }

    private var removedForeground: SIMD4<Float> {
        hexAny(["gitDecoration.deletedResourceForeground"], isDark ? "#F19999" : "#A33A3A")
    }

    private var addedLineBackground: SIMD4<Float> {
        hexAny(
            ["diffEditor.insertedLineBackground", "diffEditor.insertedTextBackground"],
            isDark ? "#2e7d3230" : "#2e7d3222"
        )
    }

    private var removedLineBackground: SIMD4<Float> {
        hexAny(
            deletedLineKeys,
            isDark ? "#c6282830" : "#c6282822"
        )
    }

    private var addedTextBackground: SIMD4<Float> {
        hexAny(
            ["diffEditor.insertedTextBackground", "diffEditor.insertedLineBackground"],
            isDark ? "#2e7d3266" : "#2e7d3344"
        )
    }

    private var removedTextBackground: SIMD4<Float> {
        hexAny(
            deletedTextKeys,
            isDark ? "#c6282866" : "#c6283344"
        )
    }

    private var addedGutterBackground: SIMD4<Float> {
        hexAny(
            ["diffEditorGutter.insertedLineBackground", "diffEditor.insertedLineBackground"],
            isDark ? "#2e7d3238" : "#2e7d3328"
        )
    }

    private var removedGutterBackground: SIMD4<Float> {
        hexAny(
            deletedGutterKeys,
            isDark ? "#c6282838" : "#c6283328"
        )
    }

    private var hunkHeaderBackground: SIMD4<Float> {
        hex("editor.lineHighlightBackground", isDark ? "#2a2a2a" : "#f2f2f2")
    }

    private var hunkHeaderForeground: SIMD4<Float> {
        hex("editor.foreground", fgHex)
    }

    private var border: SIMD4<Float> {
        hex("diffEditor.border", isDark ? "#30363d" : "#d0d7de")
    }

    private var deletedLineKeys: [String] {
        [
            "diffEditor.removedLineBackground",
            "diffEditor.deletedLineBackground",
            "diffEditor.removedTextBackground",
            "diffEditor.deletedTextBackground"
        ]
    }

    private var deletedTextKeys: [String] {
        [
            "diffEditor.removedTextBackground",
            "diffEditor.deletedTextBackground",
            "diffEditor.removedLineBackground",
            "diffEditor.deletedLineBackground"
        ]
    }

    private var deletedGutterKeys: [String] {
        [
            "diffEditorGutter.removedLineBackground",
            "diffEditorGutter.deletedLineBackground",
            "diffEditor.removedLineBackground",
            "diffEditor.deletedLineBackground"
        ]
    }

    private func hex(_ key: String, _ fallback: String) -> SIMD4<Float> {
        hexToLinearColor(colors[key] ?? fallback)
    }

    private func hexAny(_ keys: [String], _ fallback: String) -> SIMD4<Float> {
        for key in keys {
            if let value = colors[key] {
                return hexToLinearColor(value)
            }
        }
        return hexToLinearColor(fallback)
    }
}
