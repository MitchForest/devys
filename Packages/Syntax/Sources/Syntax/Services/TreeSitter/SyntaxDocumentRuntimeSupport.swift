import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Text

enum SyntaxDocumentRuntimeSupport {
    static func loadInitialContent(
        into rootLayer: LanguageLayer,
        snapshot: DocumentSnapshot
    ) throws {
        let eofPoint = point(atUTF16Offset: snapshot.utf16Length, in: snapshot)
        let content = makeLayerContentSnapshot(from: snapshot).content
        let edit = InputEdit(
            startByte: 0,
            oldEndByte: 0,
            newEndByte: snapshot.utf16Length * 2,
            startPoint: .zero,
            oldEndPoint: .zero,
            newEndPoint: eofPoint
        )

        _ = rootLayer.didChangeContent(content, using: edit, resolveSublayers: false)

        guard rootLayer.snapshot() != nil else {
            throw SyntaxDocumentRuntimeError.parseFailed(languageName: rootLayer.languageName)
        }
    }

    static func makeLayerContentSnapshot(
        from snapshot: DocumentSnapshot
    ) -> LanguageLayer.ContentSnapshot {
        let utf16CodeUnits = Array(documentText(from: snapshot).utf16)
        return LanguageLayer.ContentSnapshot(
            readHandler: { byteIndex, _ in
                readData(
                    atByteIndex: byteIndex,
                    utf16CodeUnits: utf16CodeUnits,
                    chunkUTF16Length: 1024
                )
            },
            textProvider: { range, _ in
                text(inUTF16Range: range, utf16CodeUnits: utf16CodeUnits)
            }
        )
    }

    static func documentText(from snapshot: DocumentSnapshot) -> String {
        snapshot.slice(TextByteRange(0, snapshot.utf8Length)).text
    }

    static func makeInputEdit(
        for edit: TextEdit,
        in snapshot: DocumentSnapshot
    ) throws -> InputEdit {
        let startUTF16 = utf16Offset(forUTF8Offset: edit.range.lowerBound, in: snapshot)
        let oldEndUTF16 = utf16Offset(forUTF8Offset: edit.range.upperBound, in: snapshot)

        let startPoint = point(atUTF16Offset: startUTF16, in: snapshot)
        let oldEndPoint = point(atUTF16Offset: oldEndUTF16, in: snapshot)
        let newEndPoint = advancedPoint(startPoint, by: edit.replacement)

        return InputEdit(
            startByte: utf16ByteOffset(forUTF16Offset: startUTF16),
            oldEndByte: utf16ByteOffset(forUTF16Offset: oldEndUTF16),
            newEndByte: utf16ByteOffset(forUTF16Offset: startUTF16 + edit.replacement.utf16.count),
            startPoint: startPoint,
            oldEndPoint: oldEndPoint,
            newEndPoint: newEndPoint
        )
    }

    static func changedRanges(
        fromUTF16InvalidatedSet affectedSet: IndexSet,
        snapshot: DocumentSnapshot
    ) -> [SyntaxChangedRange] {
        let ranges = affectedSet.rangeView.compactMap { range -> SyntaxChangedRange? in
            let lowerBound = max(0, min(range.lowerBound, snapshot.utf16Length))
            let upperBound = max(lowerBound, min(range.upperBound, snapshot.utf16Length))
            guard upperBound > lowerBound else { return nil }

            let startPoint = point(atUTF16Offset: lowerBound, in: snapshot)
            let endPoint = point(atUTF16Offset: upperBound, in: snapshot)
            let startLine = Int(startPoint.row)
            let upperLine = min(
                max(startLine + 1, Int(endPoint.row) + 1),
                max(snapshot.lineCount, 1)
            )

            return SyntaxChangedRange(
                utf16Range: lowerBound..<upperBound,
                byteRange: (lowerBound * 2)..<(upperBound * 2),
                pointRange: startPoint..<endPoint,
                lineRange: SourceLineRange(startLine, upperLine)
            )
        }

        if ranges.isEmpty {
            return [fullDocumentChangedRange(for: snapshot)]
        }

        return ranges
    }

    static func fullDocumentChangedRange(
        for snapshot: DocumentSnapshot
    ) -> SyntaxChangedRange {
        guard snapshot.lineCount > 0 else {
            return SyntaxChangedRange(
                utf16Range: 0..<snapshot.utf16Length,
                byteRange: 0..<(snapshot.utf16Length * 2),
                pointRange: Point.zero..<Point.zero,
                lineRange: .empty
            )
        }

        let endPoint = point(atUTF16Offset: snapshot.utf16Length, in: snapshot)
        return SyntaxChangedRange(
            utf16Range: 0..<snapshot.utf16Length,
            byteRange: 0..<(snapshot.utf16Length * 2),
            pointRange: .zero..<endPoint,
            lineRange: SourceLineRange(0, snapshot.lineCount)
        )
    }

    static func makeInvalidationFromRanges(
        changedRanges: [SyntaxChangedRange],
        lineCount: Int,
        policy: SyntaxInvalidationPolicy
    ) -> SyntaxInvalidationSet {
        SyntaxInvalidationSet.fromChangedRanges(
            changedRanges,
            lineCount: lineCount,
            policy: policy
        )
    }

    static func makeInvalidationFromUTF16Set(
        _ affectedSet: IndexSet,
        snapshot: DocumentSnapshot,
        policy: SyntaxInvalidationPolicy
    ) -> SyntaxInvalidationSet {
        makeInvalidationFromRanges(
            changedRanges: changedRanges(
                fromUTF16InvalidatedSet: affectedSet,
                snapshot: snapshot
            ),
            lineCount: snapshot.lineCount,
            policy: policy
        )
    }

    static func utf16Set(
        for lineRange: Range<Int>,
        in snapshot: DocumentSnapshot
    ) -> IndexSet {
        guard snapshot.lineCount > 0 else { return IndexSet() }

        let lowerBound = max(0, min(lineRange.lowerBound, snapshot.lineCount))
        let upperBound = max(lowerBound, min(lineRange.upperBound, snapshot.lineCount))
        guard lowerBound < upperBound else { return IndexSet() }

        let startOffset = snapshot.offset(
            of: TextPoint(line: lowerBound, column: 0),
            encoding: .utf16
        )
        let endOffset = endUTF16Offset(for: upperBound, snapshot: snapshot)
        return IndexSet(integersIn: startOffset..<max(startOffset, endOffset))
    }

    private static func readData(
        atByteIndex byteIndex: Int,
        utf16CodeUnits: [UInt16],
        chunkUTF16Length: Int
    ) -> Data? {
        let startUTF16 = max(0, byteIndex / 2)
        guard startUTF16 < utf16CodeUnits.count else { return nil }

        let endUTF16 = min(utf16CodeUnits.count, startUTF16 + chunkUTF16Length)
        guard endUTF16 > startUTF16 else { return nil }

        let chunk = Array(utf16CodeUnits[startUTF16..<endUTF16])
        return chunk.withUnsafeBytes { buffer in
            Data(buffer)
        }
    }

    private static func text(
        inUTF16Range range: NSRange,
        utf16CodeUnits: [UInt16]
    ) -> String? {
        let lowerBound = max(0, min(range.location, utf16CodeUnits.count))
        let upperBound = max(
            lowerBound,
            min(range.location + range.length, utf16CodeUnits.count)
        )
        guard upperBound > lowerBound else { return "" }

        return String(decoding: utf16CodeUnits[lowerBound..<upperBound], as: UTF16.self)
    }

    private static func utf16Offset(
        forUTF8Offset utf8Offset: Int,
        in snapshot: DocumentSnapshot
    ) -> Int {
        snapshot
            .slice(TextByteRange(0, utf8Offset))
            .text
            .utf16
            .count
    }

    private static func utf16ByteOffset(forUTF16Offset utf16Offset: Int) -> Int {
        utf16Offset * 2
    }

    private static func point(
        atUTF16Offset utf16Offset: Int,
        in snapshot: DocumentSnapshot
    ) -> Point {
        let textPoint = snapshot.point(at: utf16Offset, encoding: .utf16)
        return Point(row: textPoint.line, column: textPoint.column)
    }

    private static func advancedPoint(
        _ point: Point,
        by insertedText: String
    ) -> Point {
        let segments = insertedText.split(separator: "\n", omittingEmptySubsequences: false)
        guard let lastSegment = segments.last else {
            return point
        }

        if segments.count == 1 {
            return Point(
                row: Int(point.row),
                column: Int(point.column) + lastSegment.utf16.count
            )
        }

        return Point(
            row: Int(point.row) + segments.count - 1,
            column: lastSegment.utf16.count
        )
    }

    private static func endUTF16Offset(
        for upperBound: Int,
        snapshot: DocumentSnapshot
    ) -> Int {
        if upperBound >= snapshot.lineCount {
            return snapshot.utf16Length
        }

        return snapshot.offset(
            of: TextPoint(line: upperBound, column: 0),
            encoding: .utf16
        )
    }

}
