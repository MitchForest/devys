// DiffRenderLayoutBuilder+Metrics.swift

import Foundation
import CoreGraphics

extension DiffRenderLayoutBuilder {
    static func digits(for value: Int) -> Int {
        guard value > 0 else { return 1 }
        return Int(floor(log10(Double(value)))) + 1
    }

    static func maxLineNumber(in diff: ParsedDiff) -> Int {
        var maxValue = 0
        for hunk in diff.hunks {
            for line in hunk.lines {
                if let old = line.oldLineNumber { maxValue = max(maxValue, old) }
                if let new = line.newLineNumber { maxValue = max(maxValue, new) }
            }
        }
        return maxValue
    }

    static func maxContentCharsForUnified(context: DiffLayoutContext) -> Int {
        let numberWidth = context.configuration.showLineNumbers
            ? (CGFloat(context.maxLineNumberDigits) * context.cellWidth + 8) * 2
            : 0
        let prefixWidth = context.configuration.showPrefix ? context.cellWidth * 2 : 0
        let padding: CGFloat = 8
        let contentWidth = max(1, context.availableWidth - numberWidth - prefixWidth - padding)
        return max(1, Int(floor(contentWidth / context.cellWidth)))
    }

    static func maxContentCharsForSplit(context: DiffLayoutContext, splitRatio: CGFloat? = nil) -> Int {
        let dividerWidth: CGFloat = 1
        let ratio = splitRatio ?? context.splitRatio
        let sideWidth = max(1, (context.availableWidth - dividerWidth) * ratio)
        let numberWidth = context.configuration.showLineNumbers
            ? CGFloat(context.maxLineNumberDigits) * context.cellWidth + 8
            : 0
        let padding: CGFloat = 8
        let contentWidth = max(1, sideWidth - numberWidth - padding)
        return max(1, Int(floor(contentWidth / context.cellWidth)))
    }

    static func contentWidthForUnified(
        context: DiffLayoutContext,
        rows: [UnifiedDiffRow]
    ) -> CGFloat {
        let baseWidth = context.configuration.showLineNumbers
            ? (CGFloat(context.maxLineNumberDigits) * context.cellWidth + 8) * 2
            : 0
        let prefixWidth = context.configuration.showPrefix ? context.cellWidth * 2 : 0
        let padding: CGFloat = 8
        let longest = rows
            .filter { $0.kind == .line }
            .map { CGFloat($0.content.count) * context.cellWidth }
            .max() ?? 0
        let contentWidth = baseWidth + prefixWidth + padding + longest
        return max(context.availableWidth, contentWidth)
    }

    static func contentWidthForSplit(
        context: DiffLayoutContext,
        rows: [SplitDiffRow]
    ) -> CGFloat {
        let numberWidth = context.configuration.showLineNumbers
            ? CGFloat(context.maxLineNumberDigits) * context.cellWidth + 8
            : 0
        let padding: CGFloat = 8
        let longestLeft = rows
            .compactMap { $0.left?.content.count }
            .map { CGFloat($0) * context.cellWidth }
            .max() ?? 0
        let longestRight = rows
            .compactMap { $0.right?.content.count }
            .map { CGFloat($0) * context.cellWidth }
            .max() ?? 0

        let sideWidth = max(longestLeft, longestRight) + numberWidth + padding
        let dividerWidth: CGFloat = 1
        let contentWidth = sideWidth * 2 + dividerWidth
        return max(context.availableWidth, contentWidth)
    }
}
