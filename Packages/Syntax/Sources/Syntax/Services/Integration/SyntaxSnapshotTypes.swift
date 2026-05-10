// SyntaxSnapshotTypes.swift
// Shared syntax request and immutable snapshot types.

import Foundation
import Text

public struct SyntaxDocumentUpdate: Sendable {
    public let oldSnapshot: DocumentSnapshot
    public let newSnapshot: DocumentSnapshot
    public let transaction: EditTransaction

    public init(
        oldSnapshot: DocumentSnapshot,
        newSnapshot: DocumentSnapshot,
        transaction: EditTransaction
    ) {
        self.oldSnapshot = oldSnapshot
        self.newSnapshot = newSnapshot
        self.transaction = transaction
    }
}

@MainActor
public protocol SyntaxHandle: AnyObject {
    func currentSnapshot() -> SyntaxSnapshot
    func schedule(_ request: SyntaxRequest)
    func noteVisibleRange(_ range: SourceLineRange)
}

public enum SyntaxBacklogPolicy: Sendable, Equatable {
    case fullDocument
    case visibleWindow(maxLineCount: Int)
}

public struct SyntaxRequest: Sendable, Equatable {
    public let preferredRange: SourceLineRange
    public let batchSize: Int
    public let backlogPolicy: SyntaxBacklogPolicy

    public init(
        preferredRange: SourceLineRange,
        batchSize: Int,
        backlogPolicy: SyntaxBacklogPolicy = .fullDocument
    ) {
        self.preferredRange = preferredRange
        self.batchSize = batchSize
        self.backlogPolicy = backlogPolicy
    }
}

public struct SyntaxWarmCacheIdentity: Sendable, Hashable, Equatable {
    public let contentFingerprint: UInt64
    public let mutationGeneration: UInt64

    public init(
        contentFingerprint: UInt64,
        mutationGeneration: UInt64
    ) {
        self.contentFingerprint = contentFingerprint
        self.mutationGeneration = mutationGeneration
    }
}

public enum HighlightStatus: Sendable, Equatable {
    case actual
    case stale
    case intentionallyLimited

    public var isRenderable: Bool {
        true
    }

    public var countsAsActual: Bool {
        switch self {
        case .actual, .intentionallyLimited:
            true
        case .stale:
            false
        }
    }
}

public struct SyntaxHighlightToken: Sendable, Equatable {
    public let range: Range<Int>
    public let foregroundColor: String
    public let backgroundColor: String?
    public let fontStyle: FontStyle

    public init(
        range: Range<Int>,
        foregroundColor: String,
        backgroundColor: String? = nil,
        fontStyle: FontStyle = []
    ) {
        self.range = range
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.fontStyle = fontStyle
    }
}

public struct SyntaxHighlightedLine: Sendable, Equatable {
    public let lineIndex: Int
    public let text: String
    public let tokens: [SyntaxHighlightToken]
    public let status: HighlightStatus

    func withStatus(_ status: HighlightStatus) -> SyntaxHighlightedLine {
        SyntaxHighlightedLine(
            lineIndex: lineIndex,
            text: text,
            tokens: tokens,
            status: status
        )
    }
}

public struct SyntaxSnapshot: Sendable, Equatable {
    public let revision: UInt64
    public let lineCount: Int
    public let visibleRange: SourceLineRange?

    private let linesByIndex: [Int: SyntaxHighlightedLine]

    init(
        revision: UInt64,
        lineCount: Int,
        visibleRange: SourceLineRange?,
        linesByIndex: [Int: SyntaxHighlightedLine]
    ) {
        self.revision = revision
        self.lineCount = lineCount
        self.visibleRange = visibleRange
        self.linesByIndex = linesByIndex
    }

    public func line(_ index: Int) -> SyntaxHighlightedLine? {
        linesByIndex[index]
    }

    public func lines(in range: Range<Int>) -> [Int: SyntaxHighlightedLine] {
        linesByIndex.filter { range.contains($0.key) }
    }

    public func hasRenderableHighlights(in range: Range<Int>) -> Bool {
        normalizedRange(range).allSatisfy { lineIndex in
            line(lineIndex)?.status.isRenderable == true
        }
    }

    public func hasActualHighlights(in range: Range<Int>) -> Bool {
        normalizedRange(range).allSatisfy { lineIndex in
            line(lineIndex)?.status.countsAsActual == true
        }
    }

    public func actualSnapshotCount(in range: Range<Int>) -> Int {
        normalizedRange(range).reduce(into: 0) { count, lineIndex in
            if line(lineIndex)?.status.countsAsActual == true {
                count += 1
            }
        }
    }

    public func hasPendingHighlights(in range: Range<Int>) -> Bool {
        normalizedRange(range).contains { lineIndex in
            guard let line = line(lineIndex) else { return true }
            return !line.status.countsAsActual
        }
    }

    public var hasPendingWork: Bool {
        hasPendingHighlights(in: 0..<lineCount)
    }

    var storedLines: [Int: SyntaxHighlightedLine] {
        linesByIndex
    }

    private func normalizedRange(_ range: Range<Int>) -> Range<Int> {
        let lowerBound = max(0, min(range.lowerBound, lineCount))
        let upperBound = max(lowerBound, min(range.upperBound, lineCount))
        return lowerBound..<upperBound
    }
}
