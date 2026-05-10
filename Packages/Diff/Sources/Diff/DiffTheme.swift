// DiffTheme.swift
// Theme resolution for Metal diff rendering.

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif
import Syntax
import Rendering
import UI

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
        let resolved = ThemeRegistry.resolvedTheme(name: CodeViewDesign.dark.syntaxThemeName)
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
    let colors: [String: String]
    let bgHex: String
    let fgHex: String

    init(theme: SyntaxTheme) {
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
        hex("editorLineNumber.foreground")
    }

    private var gutterBackground: SIMD4<Float> {
        hex("editorGutter.background")
    }

    private var addedForeground: SIMD4<Float> {
        hex("gitDecoration.addedResourceForeground")
    }

    private var removedForeground: SIMD4<Float> {
        hex("gitDecoration.deletedResourceForeground")
    }

    private var addedLineBackground: SIMD4<Float> {
        hex("diffEditor.insertedLineBackground")
    }

    private var removedLineBackground: SIMD4<Float> {
        hex("diffEditor.removedLineBackground")
    }

    private var addedTextBackground: SIMD4<Float> {
        hex("diffEditor.insertedTextBackground")
    }

    private var removedTextBackground: SIMD4<Float> {
        hex("diffEditor.removedTextBackground")
    }

    private var addedGutterBackground: SIMD4<Float> {
        hex("diffEditorGutter.insertedLineBackground")
    }

    private var removedGutterBackground: SIMD4<Float> {
        hex("diffEditorGutter.removedLineBackground")
    }

    private var hunkHeaderBackground: SIMD4<Float> {
        hex("editor.lineHighlightBackground")
    }

    private var hunkHeaderForeground: SIMD4<Float> {
        hexToLinearColor(fgHex)
    }

    private var border: SIMD4<Float> {
        hex("diffEditor.border")
    }

    private func hex(_ key: String) -> SIMD4<Float> {
        guard let value = colors[key] else {
            preconditionFailure("Diff theme is missing required color '\(key)'")
        }
        return hexToLinearColor(value)
    }
}
