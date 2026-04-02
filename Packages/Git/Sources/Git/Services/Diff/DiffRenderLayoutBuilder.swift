// DiffRenderLayoutBuilder.swift
// Diff layout construction entry point.

import Foundation
import CoreGraphics

struct DiffLayoutContext {
    let configuration: DiffRenderConfiguration
    let cellWidth: CGFloat
    let availableWidth: CGFloat
    let maxLineNumberDigits: Int
    let splitRatio: CGFloat
}

enum DiffRenderLayoutBuilder {
    static func build(
        diff: ParsedDiff,
        mode: DiffViewMode,
        configuration: DiffRenderConfiguration,
        lineHeight: CGFloat,
        cellWidth: CGFloat,
        availableWidth: CGFloat,
        splitRatio: CGFloat = 0.5
    ) -> DiffRenderLayout {
        let maxDigits = max(1, digits(for: maxLineNumber(in: diff)))
        let context = DiffLayoutContext(
            configuration: configuration,
            cellWidth: cellWidth,
            availableWidth: availableWidth,
            maxLineNumberDigits: maxDigits,
            splitRatio: splitRatio
        )

        switch mode {
        case .unified:
            return .unified(buildUnified(diff: diff, context: context, lineHeight: lineHeight))
        case .split:
            return .split(buildSplit(diff: diff, context: context, lineHeight: lineHeight))
        }
    }
}
