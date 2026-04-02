// DiffRenderLayoutBuilder+Split.swift

import Foundation
import CoreGraphics

extension DiffRenderLayoutBuilder {
    static func buildSplit(
        diff: ParsedDiff,
        context: DiffLayoutContext,
        lineHeight: CGFloat
    ) -> SplitDiffLayout {
        var rows: [SplitDiffRow] = []
        var headers: [DiffHunkHeaderLayout] = []
        var rowIndex = 0

        for (hunkIndex, hunk) in diff.hunks.enumerated() {
            let headerRow = SplitDiffRow(kind: .hunkHeader, left: nil, right: nil)
            rows.append(headerRow)
            headers.append(DiffHunkHeaderLayout(hunkIndex: hunkIndex, rowIndex: rowIndex, hunk: hunk))
            rowIndex += 1

            if !context.configuration.showsHunkHeaders {
                rows.append(SplitDiffRow(kind: .line, left: nil, right: nil))
                rowIndex += 1
            }

            let lineRows = splitLineRows(hunk: hunk, context: context)
            for lineRow in lineRows {
                rows.append(lineRow)
                rowIndex += 1
            }
        }

        let contentWidth = contentWidthForSplit(context: context, rows: rows)
        let contentHeight = CGFloat(rows.count) * lineHeight

        return SplitDiffLayout(
            rows: rows,
            hunkHeaders: headers,
            contentSize: CGSize(width: contentWidth, height: contentHeight),
            maxLineNumberDigits: context.maxLineNumberDigits
        )
    }

    static func splitLineRows(hunk: DiffHunk, context: DiffLayoutContext) -> [SplitDiffRow] {
        var rows: [SplitDiffRow] = []
        var removed: [DiffLine] = []
        var added: [DiffLine] = []

        for line in hunk.lines where line.type != .header {
            switch line.type {
            case .context, .noNewline:
                rows.append(contentsOf: flushSplitPairs(
                    removed: &removed,
                    added: &added,
                    context: context
                ))

                let side = SplitDiffSide(
                    lineNumber: line.oldLineNumber,
                    lineType: line.type,
                    content: line.content,
                    wordChanges: nil
                )
                let other = SplitDiffSide(
                    lineNumber: line.newLineNumber,
                    lineType: line.type,
                    content: line.content,
                    wordChanges: nil
                )
                rows.append(contentsOf: splitRows(left: side, right: other, context: context))

            case .removed:
                removed.append(line)

            case .added:
                added.append(line)

            case .header:
                break
            }
        }

        rows.append(contentsOf: flushSplitPairs(removed: &removed, added: &added, context: context))
        return rows
    }

    static func flushSplitPairs(
        removed: inout [DiffLine],
        added: inout [DiffLine],
        context: DiffLayoutContext
    ) -> [SplitDiffRow] {
        var rows: [SplitDiffRow] = []
        let maxCount = max(removed.count, added.count)

        for index in 0..<maxCount {
            let oldLine = index < removed.count ? removed[index] : nil
            let newLine = index < added.count ? added[index] : nil

            var oldChanges: [DiffWordChange]?
            var newChanges: [DiffWordChange]?

            if let oldLine, let newLine, context.configuration.showWordDiff {
                let (old, new) = WordDiff.diff(old: oldLine.content, new: newLine.content)
                oldChanges = toWordChanges(old, in: oldLine.content)
                newChanges = toWordChanges(new, in: newLine.content)
            }

            let left = oldLine.map {
                SplitDiffSide(
                    lineNumber: $0.oldLineNumber,
                    lineType: .removed,
                    content: $0.content,
                    wordChanges: oldChanges
                )
            }
            let right = newLine.map {
                SplitDiffSide(
                    lineNumber: $0.newLineNumber,
                    lineType: .added,
                    content: $0.content,
                    wordChanges: newChanges
                )
            }

            rows.append(contentsOf: splitRows(left: left, right: right, context: context))
        }

        removed.removeAll()
        added.removeAll()
        return rows
    }

    static func splitRows(
        left: SplitDiffSide?,
        right: SplitDiffSide?,
        context: DiffLayoutContext
    ) -> [SplitDiffRow] {
        guard context.configuration.wrapLines else {
            return [SplitDiffRow(kind: .line, left: left, right: right)]
        }

        let smallerRatio = min(context.splitRatio, 1 - context.splitRatio)
        let maxChars = max(1, maxContentCharsForSplit(context: context, splitRatio: smallerRatio))

        let leftSegments = wrapSide(left, maxChars: maxChars)
        let rightSegments = wrapSide(right, maxChars: maxChars)
        let segmentCount = max(leftSegments.count, rightSegments.count)

        var rows: [SplitDiffRow] = []
        for index in 0..<segmentCount {
            let leftSegment = index < leftSegments.count ? leftSegments[index] : nil
            let rightSegment = index < rightSegments.count ? rightSegments[index] : nil

            rows.append(SplitDiffRow(kind: .line, left: leftSegment, right: rightSegment))
        }

        return rows
    }

    static func wrapSide(_ side: SplitDiffSide?, maxChars: Int) -> [SplitDiffSide] {
        guard let side else { return [] }

        let segments = wrapContent(side.content, wordChanges: side.wordChanges, maxChars: maxChars)
        return segments.enumerated().map { index, segment in
            SplitDiffSide(
                lineNumber: index == 0 ? side.lineNumber : nil,
                lineType: side.lineType,
                content: segment.content,
                wordChanges: segment.wordChanges
            )
        }
    }
}
