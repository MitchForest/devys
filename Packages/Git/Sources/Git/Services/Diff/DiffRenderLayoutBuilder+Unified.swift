// DiffRenderLayoutBuilder+Unified.swift

import Foundation
import CoreGraphics

extension DiffRenderLayoutBuilder {
    static func buildUnified(
        diff: ParsedDiff,
        context: DiffLayoutContext,
        lineHeight: CGFloat
    ) -> UnifiedDiffLayout {
        var rows: [UnifiedDiffRow] = []
        var headers: [DiffHunkHeaderLayout] = []
        var rowIndex = 0

        for (hunkIndex, hunk) in diff.hunks.enumerated() {
            let headerRow = UnifiedDiffRow(
                kind: .hunkHeader,
                lineType: .header,
                oldLineNumber: nil,
                newLineNumber: nil,
                content: hunk.header,
                wordChanges: nil
            )
            rows.append(headerRow)
            headers.append(DiffHunkHeaderLayout(hunkIndex: hunkIndex, rowIndex: rowIndex, hunk: hunk))
            rowIndex += 1

            if !context.configuration.showsHunkHeaders {
                rows.append(UnifiedDiffRow(
                    kind: .line,
                    lineType: .context,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    content: "",
                    wordChanges: nil
                ))
                rowIndex += 1
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
            maxLineNumberDigits: context.maxLineNumberDigits
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
                    kind: .line,
                    lineType: line.type,
                    oldLineNumber: line.oldLineNumber,
                    newLineNumber: line.newLineNumber,
                    content: content,
                    wordChanges: convertedChanges
                )
            ]
        }

        let maxChars = max(1, maxContentCharsForUnified(context: context))
        let segments = wrapContent(content, wordChanges: convertedChanges, maxChars: maxChars)

        return segments.enumerated().map { index, segment in
            UnifiedDiffRow(
                kind: .line,
                lineType: line.type,
                oldLineNumber: index == 0 ? line.oldLineNumber : nil,
                newLineNumber: index == 0 ? line.newLineNumber : nil,
                content: segment.content,
                wordChanges: segment.wordChanges
            )
        }
    }
}
