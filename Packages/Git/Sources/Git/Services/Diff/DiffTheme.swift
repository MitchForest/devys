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

struct DiffTheme: Sendable {
    let background: SIMD4<Float>
    let foreground: SIMD4<Float>
    let lineNumber: SIMD4<Float>
    let gutterBackground: SIMD4<Float>
    let addedLineBackground: SIMD4<Float>
    let removedLineBackground: SIMD4<Float>
    let addedTextBackground: SIMD4<Float>
    let removedTextBackground: SIMD4<Float>
    let addedGutterBackground: SIMD4<Float>
    let removedGutterBackground: SIMD4<Float>
    let hunkHeaderBackground: SIMD4<Float>
    let hunkHeaderForeground: SIMD4<Float>
    let border: SIMD4<Float>

    init(theme: ShikiTheme) {
        let resolved = DiffTheme.resolveColors(from: theme)
        background = resolved.background
        foreground = resolved.foreground
        lineNumber = resolved.lineNumber
        gutterBackground = resolved.gutterBackground
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

    init(isDark: Bool) {
        let bgHex = isDark ? "#1e1e1e" : "#ffffff"
        let fgHex = isDark ? "#d4d4d4" : "#333333"

        background = hexToLinearColor(bgHex)
        foreground = hexToLinearColor(fgHex)
        lineNumber = hexToLinearColor(isDark ? "#636363" : "#9e9e9e")
        gutterBackground = hexToLinearColor(bgHex)
        addedLineBackground = hexToLinearColor(isDark ? "#2e7d3230" : "#2e7d3222")
        removedLineBackground = hexToLinearColor(isDark ? "#c6282830" : "#c6282822")
        addedTextBackground = hexToLinearColor(isDark ? "#2e7d3266" : "#2e7d3344")
        removedTextBackground = hexToLinearColor(isDark ? "#c6282866" : "#c6283344")
        addedGutterBackground = hexToLinearColor(isDark ? "#2e7d3238" : "#2e7d3328")
        removedGutterBackground = hexToLinearColor(isDark ? "#c6282838" : "#c6283328")
        hunkHeaderBackground = hexToLinearColor(isDark ? "#2a2a2a" : "#f2f2f2")
        hunkHeaderForeground = hexToLinearColor(fgHex)
        border = hexToLinearColor(isDark ? "#30363d" : "#d0d7de")
    }

    init(devysTheme: DevysTheme) {
        background = linearColor(from: devysTheme.base)
        foreground = linearColor(from: devysTheme.text)
        lineNumber = linearColor(from: devysTheme.textTertiary)
        gutterBackground = linearColor(from: devysTheme.surface)

        addedLineBackground = linearColor(from: DevysColors.success, alpha: 0.14)
        removedLineBackground = linearColor(from: DevysColors.error, alpha: 0.14)
        addedTextBackground = linearColor(from: DevysColors.success, alpha: 0.3)
        removedTextBackground = linearColor(from: DevysColors.error, alpha: 0.3)
        addedGutterBackground = linearColor(from: DevysColors.success, alpha: 0.2)
        removedGutterBackground = linearColor(from: DevysColors.error, alpha: 0.2)

        hunkHeaderBackground = linearColor(from: devysTheme.elevated)
        hunkHeaderForeground = linearColor(from: devysTheme.text)

        border = linearColor(from: devysTheme.border)
    }

    @MainActor
    static func current() -> DiffTheme {
        let registry = ThemeRegistry()
        if let theme = registry.currentTheme {
            return DiffTheme(theme: theme)
        }
        registry.loadTheme(name: "github-dark")
        if let theme = registry.currentTheme {
            return DiffTheme(theme: theme)
        }
        return DiffTheme(isDark: true)
    }
}


private struct ResolvedDiffColors {
    let background: SIMD4<Float>
    let foreground: SIMD4<Float>
    let lineNumber: SIMD4<Float>
    let gutterBackground: SIMD4<Float>
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
    static func resolveColors(from theme: ShikiTheme) -> ResolvedDiffColors {
        DiffThemePalette(theme: theme).resolve()
    }
}

private struct DiffThemePalette {
    let isDark: Bool
    let colors: [String: String]
    let bgHex: String
    let fgHex: String

    init(theme: ShikiTheme) {
        isDark = theme.isDark
        colors = theme.colors ?? [:]
        bgHex = theme.editorBackground ?? (theme.isDark ? "#1e1e1e" : "#ffffff")
        fgHex = theme.editorForeground ?? (theme.isDark ? "#d4d4d4" : "#333333")
    }

    func resolve() -> ResolvedDiffColors {
        ResolvedDiffColors(
            background: hexToLinearColor(bgHex),
            foreground: hexToLinearColor(fgHex),
            lineNumber: hex("editorLineNumber.foreground", isDark ? "#636363" : "#9e9e9e"),
            gutterBackground: hex("editorGutter.background", bgHex),
            addedLineBackground: hexAny(
                ["diffEditor.insertedLineBackground", "diffEditor.insertedTextBackground"],
                isDark ? "#2e7d3230" : "#2e7d3222"
            ),
            removedLineBackground: hexAny(
                [
                    "diffEditor.removedLineBackground",
                    "diffEditor.deletedLineBackground",
                    "diffEditor.removedTextBackground",
                    "diffEditor.deletedTextBackground"
                ],
                isDark ? "#c6282830" : "#c6282822"
            ),
            addedTextBackground: hexAny(
                ["diffEditor.insertedTextBackground", "diffEditor.insertedLineBackground"],
                isDark ? "#2e7d3266" : "#2e7d3344"
            ),
            removedTextBackground: hexAny(
                [
                    "diffEditor.removedTextBackground",
                    "diffEditor.deletedTextBackground",
                    "diffEditor.removedLineBackground",
                    "diffEditor.deletedLineBackground"
                ],
                isDark ? "#c6282866" : "#c6283344"
            ),
            addedGutterBackground: hexAny(
                ["diffEditorGutter.insertedLineBackground", "diffEditor.insertedLineBackground"],
                isDark ? "#2e7d3238" : "#2e7d3328"
            ),
            removedGutterBackground: hexAny(
                [
                    "diffEditorGutter.removedLineBackground",
                    "diffEditorGutter.deletedLineBackground",
                    "diffEditor.removedLineBackground",
                    "diffEditor.deletedLineBackground"
                ],
                isDark ? "#c6282838" : "#c6283328"
            ),
            hunkHeaderBackground: hex("editor.lineHighlightBackground", isDark ? "#2a2a2a" : "#f2f2f2"),
            hunkHeaderForeground: hex("editor.foreground", fgHex),
            border: hex("diffEditor.border", isDark ? "#30363d" : "#d0d7de")
        )
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

private func linearColor(from color: Color, alpha: CGFloat? = nil) -> SIMD4<Float> {
    #if os(macOS)
    let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
    let outAlpha = Float(alpha ?? a)
    return SIMD4<Float>(
        srgbToLinear(Float(r)),
        srgbToLinear(Float(g)),
        srgbToLinear(Float(b)),
        outAlpha
    )
    #else
    return SIMD4<Float>(0, 0, 0, 1)
    #endif
}
