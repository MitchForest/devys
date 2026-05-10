// DiffRenderLayoutBuilder.swift
// Diff layout construction entry point.

import Foundation
import CoreGraphics
import Syntax

struct DiffLayoutContext {
    let configuration: DiffRenderConfiguration
    let cellWidth: CGFloat
    let availableWidth: CGFloat
    let maxLineNumberDigits: Int
    let splitRatio: CGFloat
    let sourceDocuments: DiffSourceDocuments
}

enum DiffChromeMetrics {
    static let hunkActionBarHeight: CGFloat = 30

    static func hiddenHunkSpacerRowCount(lineHeight: CGFloat) -> Int {
        let normalizedLineHeight = max(1, lineHeight)
        let reservedRows = Int(ceil(hunkActionBarHeight / normalizedLineHeight))
        return max(0, reservedRows - 1)
    }
}

enum DiffRenderLayoutBuilder {
    static func build(
        snapshot: DiffSnapshot,
        mode: DiffViewMode,
        configuration: DiffRenderConfiguration,
        lineHeight: CGFloat,
        cellWidth: CGFloat,
        availableWidth: CGFloat,
        splitRatio: CGFloat = 0.5
    ) -> DiffRenderLayout {
        _ = SyntaxRuntimeDiagnostics.recordDiffProjectionWorkDuringRender(
            operation: "DiffRenderLayoutBuilder.build",
            metadata: "mode=\(mode)"
        )
        let maxDigits = max(1, digits(for: maxLineNumber(in: snapshot)))
        let context = DiffLayoutContext(
            configuration: configuration,
            cellWidth: cellWidth,
            availableWidth: availableWidth,
            maxLineNumberDigits: maxDigits,
            splitRatio: splitRatio,
            sourceDocuments: snapshot.sourceDocuments
        )

        switch mode {
        case .unified:
            return .unified(buildUnified(snapshot: snapshot, context: context, lineHeight: lineHeight))
        case .split:
            return .split(buildSplit(snapshot: snapshot, context: context, lineHeight: lineHeight))
        }
    }
}
