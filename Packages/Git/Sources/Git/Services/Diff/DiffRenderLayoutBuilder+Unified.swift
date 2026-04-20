// DiffRenderLayoutBuilder+Unified.swift

import Foundation
import CoreGraphics

extension DiffRenderLayoutBuilder {
    static func buildUnified(
        snapshot: DiffSnapshot,
        context: DiffLayoutContext,
        lineHeight: CGFloat
    ) -> UnifiedDiffLayout {
        var rows: [UnifiedDiffRow] = []
        var headers: [DiffHunkHeaderLayout] = []
        var rowIndex = 0

        for (hunkIndex, hunk) in snapshot.hunks.enumerated() {
            let headerRow = UnifiedDiffRow(
                id: "unified-hunk-header-\(hunk.id)",
                kind: .hunkHeader,
                lineType: .header,
                oldLineNumber: nil,
                newLineNumber: nil,
                content: hunk.header,
                wordChanges: nil,
                highlightSegment: nil
            )
            rows.append(headerRow)
            headers.append(DiffHunkHeaderLayout(hunkIndex: hunkIndex, rowIndex: rowIndex, hunk: hunk))
            rowIndex += 1

            if !context.configuration.showsHunkHeaders {
                for spacerIndex in 0..<DiffChromeMetrics.hiddenHunkSpacerRowCount(lineHeight: lineHeight) {
                    rows.append(UnifiedDiffRow(
                        id: "unified-hunk-spacer-\(hunk.id)-\(spacerIndex)",
                        kind: .line,
                        lineType: .context,
                        oldLineNumber: nil,
                        newLineNumber: nil,
                        content: "",
                        wordChanges: nil,
                        highlightSegment: nil
                    ))
                    rowIndex += 1
                }
            }

            let lineRows = unifiedLineRows(hunk: hunk, context: context)
            for lineRow in lineRows {
                rows.append(lineRow)
                rowIndex += 1
            }
        }

        let contentWidth = contentWidthForUnified(context: context, rows: rows)
        let contentHeight = CGFloat(rows.count) * lineHeight

        return UnifiedDiffLayout(
            rows: rows,
            hunkHeaders: headers,
            contentSize: CGSize(width: contentWidth, height: contentHeight),
            maxLineNumberDigits: context.maxLineNumberDigits,
            sourceDocuments: context.sourceDocuments
        )
    }

    static func unifiedLineRows(hunk: DiffHunk, context: DiffLayoutContext) -> [UnifiedDiffRow] {
        var rows: [UnifiedDiffRow] = []
        var pendingRemoved: [DiffLine] = []

        for line in hunk.lines where line.type != .header {
            switch line.type {
            case .removed:
                pendingRemoved.append(line)

            case .added:
                if let removed = pendingRemoved.first {
                    let wordChanges = context.configuration.showWordDiff
                        ? WordDiff.diff(old: removed.content, new: line.content)
                        : (oldChanges: [], newChanges: [])

                    rows.append(contentsOf: unifiedRows(
                        line: removed,
                        wordChanges: context.configuration.showWordDiff ? wordChanges.oldChanges : nil,
                        context: context
                    ))
                    rows.append(contentsOf: unifiedRows(
                        line: line,
                        wordChanges: context.configuration.showWordDiff ? wordChanges.newChanges : nil,
                        context: context
                    ))
                    pendingRemoved.removeFirst()
                } else {
                    rows.append(contentsOf: unifiedRows(line: line, wordChanges: nil, context: context))
                }

            case .context, .noNewline:
                for removed in pendingRemoved {
                    rows.append(contentsOf: unifiedRows(line: removed, wordChanges: nil, context: context))
                }
                pendingRemoved.removeAll()
                rows.append(contentsOf: unifiedRows(line: line, wordChanges: nil, context: context))

            case .header:
                break
            }
        }

        for removed in pendingRemoved {
            rows.append(contentsOf: unifiedRows(line: removed, wordChanges: nil, context: context))
        }

        return rows
    }

    static func unifiedRows(
        line: DiffLine,
        wordChanges: [WordDiff.Change]?,
        context: DiffLayoutContext
    ) -> [UnifiedDiffRow] {
        let content = line.content
        let convertedChanges = wordChanges.map { toWordChanges($0, in: content) }

        guard context.configuration.wrapLines else {
            return [
                UnifiedDiffRow(
                    id: "unified-\(line.id)-0",
                    kind: .line,
                    lineType: line.type,
                    oldLineNumber: line.oldLineNumber,
                    newLineNumber: line.newLineNumber,
                    content: content,
                    wordChanges: convertedChanges,
                    highlightSegment: unifiedHighlightSegment(
                        for: line,
                        utf16Range: 0..<content.utf16.count,
                        context: context
                    )
                )
            ]
        }

        let maxChars = max(1, maxContentCharsForUnified(context: context))
        let segments = wrapContent(content, wordChanges: convertedChanges, maxChars: maxChars)

        return segments.enumerated().map { index, segment in
            UnifiedDiffRow(
                id: "unified-\(line.id)-\(index)",
                kind: .line,
                lineType: line.type,
                oldLineNumber: index == 0 ? line.oldLineNumber : nil,
                newLineNumber: index == 0 ? line.newLineNumber : nil,
                content: segment.content,
                wordChanges: segment.wordChanges,
                highlightSegment: unifiedHighlightSegment(
                    for: line,
                    utf16Range: segment.utf16Range,
                    context: context
                )
            )
        }
    }

    static func unifiedHighlightSegment(
        for line: DiffLine,
        utf16Range: Range<Int>,
        context: DiffLayoutContext
    ) -> DiffHighlightSegment? {
        guard let indices = context.sourceDocuments.lineMappings[line.id] else { return nil }

        let side: DiffSourceSide
        let sourceLineIndex: Int

        switch line.type {
        case .removed:
            guard let baseIndex = indices.base else { return nil }
            side = .base
            sourceLineIndex = baseIndex

        case .added, .context:
            guard let modifiedIndex = indices.modified else { return nil }
            side = .modified
            sourceLineIndex = modifiedIndex

        case .noNewline, .header:
            return nil
        }

        return DiffHighlightSegment(
            side: side,
            sourceLineID: line.id,
            sourceLineIndex: sourceLineIndex,
            utf16Range: utf16Range
        )
    }
}
