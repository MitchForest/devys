import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Text

public enum SyntaxParseStrategy: String, Sendable, Equatable {
    case initial
    case incremental
    case full
    case noChanges
}

public struct SyntaxChangedRange: Sendable, Hashable, Equatable {
    public let utf16Range: Range<Int>
    public let byteRange: Range<Int>
    public let pointRange: Range<Point>
    public let lineRange: SourceLineRange

    public init(
        utf16Range: Range<Int>,
        byteRange: Range<Int>,
        pointRange: Range<Point>,
        lineRange: SourceLineRange
    ) {
        self.utf16Range = utf16Range
        self.byteRange = byteRange
        self.pointRange = pointRange
        self.lineRange = lineRange
    }
}

public struct SyntaxInvalidationSet: Sendable, Equatable {
    public let lineRanges: [SourceLineRange]

    public init(lineRanges: [SourceLineRange]) {
        self.lineRanges = Self.normalize(lineRanges)
    }

    public var isEmpty: Bool {
        lineRanges.isEmpty
    }

    public func contains(lineIndex: Int) -> Bool {
        lineRanges.contains { range in
            range.lowerBound <= lineIndex && lineIndex < range.upperBound
        }
    }

    public func subtracting(_ range: Range<Int>) -> SyntaxInvalidationSet {
        guard !range.isEmpty else { return self }

        var remaining: [SourceLineRange] = []
        for candidate in lineRanges {
            if range.upperBound <= candidate.lowerBound || candidate.upperBound <= range.lowerBound {
                remaining.append(candidate)
                continue
            }

            if candidate.lowerBound < range.lowerBound {
                remaining.append(
                    SourceLineRange(candidate.lowerBound, min(candidate.upperBound, range.lowerBound))
                )
            }

            if range.upperBound < candidate.upperBound {
                remaining.append(
                    SourceLineRange(max(candidate.lowerBound, range.upperBound), candidate.upperBound)
                )
            }
        }

        return SyntaxInvalidationSet(lineRanges: remaining)
    }

    public static func fromChangedRanges(
        _ changedRanges: [SyntaxChangedRange],
        lineCount: Int,
        policy: SyntaxInvalidationPolicy
    ) -> SyntaxInvalidationSet {
        let maxLineCount = max(lineCount, 1)

        return SyntaxInvalidationSet(
            lineRanges: changedRanges.map { changedRange in
                let lowerBound = max(
                    0,
                    changedRange.lineRange.lowerBound - policy.leadingContextLines
                )
                let upperBound = min(
                    maxLineCount,
                    changedRange.lineRange.upperBound + policy.trailingContextLines
                )

                return SourceLineRange(lowerBound, max(lowerBound, upperBound))
            }
        )
    }

    public static func fromEdits(
        _ edits: [TextEdit],
        oldSnapshot: DocumentSnapshot,
        newSnapshot: DocumentSnapshot,
        policy: SyntaxInvalidationPolicy
    ) -> SyntaxInvalidationSet {
        let maxLineCount = max(newSnapshot.lineCount, 1)

        return SyntaxInvalidationSet(
            lineRanges: edits.map { edit in
                let startLine = oldSnapshot.point(
                    at: edit.range.lowerBound,
                    encoding: .utf8
                ).line
                let oldEndLine = oldSnapshot.point(
                    at: edit.range.upperBound,
                    encoding: .utf8
                ).line
                let insertedNewlineCount = edit.replacement.reduce(into: 0) { count, character in
                    if character == "\n" {
                        count += 1
                    }
                }
                let editUpperBound = max(
                    oldEndLine + 1,
                    startLine + insertedNewlineCount + 1
                )
                let lowerBound = max(0, startLine - policy.leadingContextLines)
                let upperBound = min(
                    maxLineCount,
                    max(lowerBound + 1, editUpperBound + policy.trailingContextLines)
                )

                return SourceLineRange(lowerBound, upperBound)
            }
        )
    }

    private static func normalize(_ lineRanges: [SourceLineRange]) -> [SourceLineRange] {
        let sortedRanges = lineRanges.sorted { lhs, rhs in
            if lhs.lowerBound == rhs.lowerBound {
                return lhs.upperBound < rhs.upperBound
            }

            return lhs.lowerBound < rhs.lowerBound
        }

        var merged: [SourceLineRange] = []

        for range in sortedRanges {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            if range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = SourceLineRange(
                    last.lowerBound,
                    max(last.upperBound, range.upperBound)
                )
            } else {
                merged.append(range)
            }
        }

        return merged
    }
}

public struct SyntaxInvalidationPolicy: Sendable, Equatable {
    public let leadingContextLines: Int
    public let trailingContextLines: Int

    public static let boundedProjection = SyntaxInvalidationPolicy(
        leadingContextLines: 1,
        trailingContextLines: 1
    )

    public init(
        leadingContextLines: Int,
        trailingContextLines: Int
    ) {
        self.leadingContextLines = max(0, leadingContextLines)
        self.trailingContextLines = max(0, trailingContextLines)
    }
}

public struct SyntaxDocumentState: Sendable {
    public let documentVersion: DocumentVersion
    public let syntaxRevision: UInt64
    public let tree: Tree
    public let lineCount: Int
    public let layerTreeSnapshot: LanguageLayerTreeSnapshot

    public init(
        documentVersion: DocumentVersion,
        syntaxRevision: UInt64,
        tree: Tree,
        lineCount: Int,
        layerTreeSnapshot: LanguageLayerTreeSnapshot
    ) {
        self.documentVersion = documentVersion
        self.syntaxRevision = syntaxRevision
        self.tree = tree
        self.lineCount = lineCount
        self.layerTreeSnapshot = layerTreeSnapshot
    }
}

public struct SyntaxDocumentParseResult: Sendable, Equatable {
    public let documentVersion: DocumentVersion
    public let syntaxRevision: UInt64
    public let strategy: SyntaxParseStrategy
    public let changedRanges: [SyntaxChangedRange]
    public let invalidation: SyntaxInvalidationSet

    public init(
        documentVersion: DocumentVersion,
        syntaxRevision: UInt64,
        strategy: SyntaxParseStrategy,
        changedRanges: [SyntaxChangedRange],
        invalidation: SyntaxInvalidationSet
    ) {
        self.documentVersion = documentVersion
        self.syntaxRevision = syntaxRevision
        self.strategy = strategy
        self.changedRanges = changedRanges
        self.invalidation = invalidation
    }
}

public enum SyntaxDocumentRuntimeError: Error, LocalizedError, Sendable {
    case parseFailed(languageName: String)
    case snapshotVersionMismatch(expected: DocumentVersion, actual: DocumentVersion)

    public var errorDescription: String? {
        switch self {
        case let .parseFailed(languageName):
            "Tree-sitter failed to parse document for language '\(languageName)'."
        case let .snapshotVersionMismatch(expected, actual):
            """
            Tree-sitter runtime snapshot version mismatch. Expected document version \
            \(expected.rawValue), received \(actual.rawValue).
            """
        }
    }
}

public actor SyntaxDocumentRuntime {
    private static let parserChunkUTF16Length = 1024

    private let languageConfiguration: LanguageConfiguration
    private let invalidationPolicy: SyntaxInvalidationPolicy
    private let languageLayerConfiguration: LanguageLayer.Configuration

    private var documentSnapshot: DocumentSnapshot
    private var rootLayer: LanguageLayer
    private var syntaxRevision: UInt64 = 0

    public init(
        documentSnapshot: DocumentSnapshot,
        languageConfiguration: LanguageConfiguration,
        injectedLanguageProvider: @escaping @Sendable (String) -> LanguageConfiguration? = {
            TreeSitterLanguageRegistry.configuration(forInjectionName: $0)
        },
        invalidationPolicy: SyntaxInvalidationPolicy = .boundedProjection
    ) throws {
        let layerConfiguration = LanguageLayer.Configuration(
            languageProvider: injectedLanguageProvider
        )
        let rootLayer = try LanguageLayer(
            languageConfig: languageConfiguration,
            configuration: layerConfiguration
        )

        self.languageConfiguration = languageConfiguration
        self.invalidationPolicy = invalidationPolicy
        self.languageLayerConfiguration = layerConfiguration
        self.documentSnapshot = documentSnapshot
        self.rootLayer = rootLayer

        try Self.loadInitialContent(into: rootLayer, snapshot: documentSnapshot)
    }

    public func currentState(
        resolving lineRange: Range<Int>? = nil
    ) -> SyntaxDocumentState {
        if let lineRange {
            try? resolveSublayers(in: lineRange)
        }

        guard let layerTreeSnapshot = rootLayer.snapshot() else {
            preconditionFailure("LanguageLayer snapshot unavailable for \(languageConfiguration.name)")
        }

        return SyntaxDocumentState(
            documentVersion: documentSnapshot.version,
            syntaxRevision: syntaxRevision,
            tree: layerTreeSnapshot.rootSnapshot.tree,
            lineCount: documentSnapshot.lineCount,
            layerTreeSnapshot: layerTreeSnapshot
        )
    }

    public func replaceDocument(
        with documentSnapshot: DocumentSnapshot
    ) throws -> SyntaxDocumentParseResult {
        let rootLayer = try LanguageLayer(
            languageConfig: languageConfiguration,
            configuration: languageLayerConfiguration
        )
        try Self.loadInitialContent(into: rootLayer, snapshot: documentSnapshot)

        self.rootLayer = rootLayer
        self.documentSnapshot = documentSnapshot
        syntaxRevision &+= 1

        let fullRange = Self.fullDocumentChangedRange(for: documentSnapshot)
        return SyntaxDocumentParseResult(
            documentVersion: documentSnapshot.version,
            syntaxRevision: syntaxRevision,
            strategy: .full,
            changedRanges: [fullRange],
            invalidation: Self.makeInvalidationFromRanges(
                changedRanges: [fullRange],
                lineCount: documentSnapshot.lineCount,
                policy: invalidationPolicy
            )
        )
    }

    public func reparse(
        oldSnapshot: DocumentSnapshot,
        newSnapshot: DocumentSnapshot,
        transaction: EditTransaction
    ) throws -> SyntaxDocumentParseResult {
        guard oldSnapshot.version == documentSnapshot.version else {
            throw SyntaxDocumentRuntimeError.snapshotVersionMismatch(
                expected: documentSnapshot.version,
                actual: oldSnapshot.version
            )
        }

        guard !transaction.edits.isEmpty else {
            if newSnapshot.version != oldSnapshot.version {
                return try replaceDocument(with: newSnapshot)
            }

            return SyntaxDocumentParseResult(
                documentVersion: newSnapshot.version,
                syntaxRevision: syntaxRevision,
                strategy: .noChanges,
                changedRanges: [],
                invalidation: SyntaxInvalidationSet(lineRanges: [])
            )
        }

        var affectedSet = IndexSet()
        let workingDocument = TextDocument(content: Self.documentText(from: oldSnapshot))

        for edit in transaction.edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            let beforeSnapshot = workingDocument.snapshot()
            _ = workingDocument.apply(EditTransaction(edits: [edit]))
            let afterSnapshot = workingDocument.snapshot()
            let inputEdit = try Self.makeInputEdit(for: edit, in: beforeSnapshot)
            let content = Self.makeLayerContentSnapshot(from: afterSnapshot).content
            let invalidated = rootLayer.didChangeContent(
                content,
                using: inputEdit,
                resolveSublayers: false
            )
            affectedSet.formUnion(invalidated)
        }

        documentSnapshot = newSnapshot
        syntaxRevision &+= 1

        let changedRanges = Self.changedRanges(
            fromUTF16InvalidatedSet: affectedSet,
            snapshot: newSnapshot
        )
        return SyntaxDocumentParseResult(
            documentVersion: newSnapshot.version,
            syntaxRevision: syntaxRevision,
            strategy: .incremental,
            changedRanges: changedRanges,
            invalidation: Self.makeInvalidationFromUTF16Set(
                affectedSet,
                snapshot: newSnapshot,
                policy: invalidationPolicy
            )
        )
    }

    private func resolveSublayers(
        in lineRange: Range<Int>
    ) throws {
        let utf16Set = Self.utf16Set(
            for: lineRange,
            in: documentSnapshot
        )
        guard utf16Set.isEmpty == false else { return }

        let content = Self.makeLayerContentSnapshot(from: documentSnapshot).content
        _ = try rootLayer.resolveSublayers(with: content, in: utf16Set)
    }

    private static func loadInitialContent(
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

    private static func makeLayerContentSnapshot(
        from snapshot: DocumentSnapshot
    ) -> LanguageLayer.ContentSnapshot {
        LanguageLayer.ContentSnapshot(
            readHandler: { byteIndex, _ in
                readData(
                    atByteIndex: byteIndex,
                    in: snapshot,
                    chunkUTF16Length: parserChunkUTF16Length
                )
            },
            textProvider: { range, _ in
                text(inUTF16Range: range, snapshot: snapshot)
            }
        )
    }

    private static func readData(
        atByteIndex byteIndex: Int,
        in snapshot: DocumentSnapshot,
        chunkUTF16Length: Int
    ) -> Data? {
        let startUTF16 = max(0, byteIndex / 2)
        guard startUTF16 < snapshot.utf16Length else { return nil }

        let endUTF16 = min(snapshot.utf16Length, startUTF16 + chunkUTF16Length)
        guard endUTF16 > startUTF16 else { return nil }

        return text(inUTF16Range: NSRange(startUTF16..<endUTF16), snapshot: snapshot)?
            .data(using: nativeUTF16Encoding)
    }

    private static func text(
        inUTF16Range range: NSRange,
        snapshot: DocumentSnapshot
    ) -> String? {
        let lowerBound = max(0, min(range.location, snapshot.utf16Length))
        let upperBound = max(
            lowerBound,
            min(range.location + range.length, snapshot.utf16Length)
        )
        guard upperBound > lowerBound else { return "" }

        let startPoint = snapshot.point(at: lowerBound, encoding: .utf16)
        let endPoint = snapshot.point(at: upperBound, encoding: .utf16)
        let startUTF8 = snapshot.offset(of: startPoint, encoding: .utf8)
        let endUTF8 = snapshot.offset(of: endPoint, encoding: .utf8)

        return snapshot.slice(TextByteRange(startUTF8, endUTF8)).text
    }

    private static func documentText(from snapshot: DocumentSnapshot) -> String {
        snapshot.slice(TextByteRange(0, snapshot.utf8Length)).text
    }

    private static func makeInputEdit(
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

    private static func changedRanges(
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

    private static func fullDocumentChangedRange(
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

    private static func makeInvalidationFromRanges(
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

    private static func makeInvalidationFromUTF16Set(
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

    private static func utf16Set(
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
        let endOffset: Int = if upperBound >= snapshot.lineCount {
            snapshot.utf16Length
        } else {
            snapshot.offset(
                of: TextPoint(line: upperBound, column: 0),
                encoding: .utf16
            )
        }

        return IndexSet(integersIn: startOffset..<max(startOffset, endOffset))
    }

    private static var nativeUTF16Encoding: String.Encoding {
#if _endian(little)
        .utf16LittleEndian
#else
        .utf16BigEndian
#endif
    }
}
