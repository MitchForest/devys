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

        try SyntaxDocumentRuntimeSupport.loadInitialContent(into: rootLayer, snapshot: documentSnapshot)
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
        try SyntaxDocumentRuntimeSupport.loadInitialContent(into: rootLayer, snapshot: documentSnapshot)

        self.rootLayer = rootLayer
        self.documentSnapshot = documentSnapshot
        syntaxRevision &+= 1

        let fullRange = SyntaxDocumentRuntimeSupport.fullDocumentChangedRange(for: documentSnapshot)
        return SyntaxDocumentParseResult(
            documentVersion: documentSnapshot.version,
            syntaxRevision: syntaxRevision,
            strategy: .full,
            changedRanges: [fullRange],
            invalidation: SyntaxDocumentRuntimeSupport.makeInvalidationFromRanges(
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
        let workingDocument = TextDocument(content: SyntaxDocumentRuntimeSupport.documentText(from: oldSnapshot))

        for edit in transaction.edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            let beforeSnapshot = workingDocument.snapshot()
            _ = workingDocument.apply(EditTransaction(edits: [edit]))
            let afterSnapshot = workingDocument.snapshot()
            let inputEdit = try SyntaxDocumentRuntimeSupport.makeInputEdit(for: edit, in: beforeSnapshot)
            let content = SyntaxDocumentRuntimeSupport.makeLayerContentSnapshot(from: afterSnapshot).content
            let invalidated = rootLayer.didChangeContent(
                content,
                using: inputEdit,
                resolveSublayers: false
            )
            affectedSet.formUnion(invalidated)
        }

        documentSnapshot = newSnapshot
        syntaxRevision &+= 1

        let changedRanges = SyntaxDocumentRuntimeSupport.changedRanges(
            fromUTF16InvalidatedSet: affectedSet,
            snapshot: newSnapshot
        )
        return SyntaxDocumentParseResult(
            documentVersion: newSnapshot.version,
            syntaxRevision: syntaxRevision,
            strategy: .incremental,
            changedRanges: changedRanges,
            invalidation: SyntaxDocumentRuntimeSupport.makeInvalidationFromUTF16Set(
                affectedSet,
                snapshot: newSnapshot,
                policy: invalidationPolicy
            )
        )
    }

    private func resolveSublayers(
        in lineRange: Range<Int>
    ) throws {
        let utf16Set = SyntaxDocumentRuntimeSupport.utf16Set(
            for: lineRange,
            in: documentSnapshot
        )
        guard utf16Set.isEmpty == false else { return }

        let content = SyntaxDocumentRuntimeSupport.makeLayerContentSnapshot(from: documentSnapshot).content
        _ = try rootLayer.resolveSublayers(with: content, in: utf16Set)
    }
}
