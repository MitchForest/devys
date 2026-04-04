// DiffRenderLayout.swift
// Layout models for Metal diff rendering.

import Foundation
import CoreGraphics

struct DiffWordChange: Sendable, Equatable {
    let range: Range<Int>
    let type: WordDiff.ChangeType
}

enum DiffSourceSide: String, Sendable, Equatable {
    case base
    case modified
}

struct DiffHighlightSegment: Sendable, Equatable {
    let side: DiffSourceSide
    let sourceLineID: DiffIdentity
    let sourceLineIndex: Int
    let utf16Range: Range<Int>
}

struct DiffHunkHeaderLayout: Identifiable, Sendable {
    let id: String
    let hunkIndex: Int
    let rowIndex: Int
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int

    init(hunkIndex: Int, rowIndex: Int, hunk: DiffHunk) {
        self.id = "hunk-header-\(hunk.id)"
        self.hunkIndex = hunkIndex
        self.rowIndex = rowIndex
        self.oldStart = hunk.oldStart
        self.oldCount = hunk.oldCount
        self.newStart = hunk.newStart
        self.newCount = hunk.newCount
    }
}

struct UnifiedDiffRow: Identifiable, Sendable {
    enum Kind: Sendable {
        case hunkHeader
        case line
    }

    let id: String
    let kind: Kind
    let lineType: DiffLine.LineType
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let content: String
    let wordChanges: [DiffWordChange]?
    let highlightSegment: DiffHighlightSegment?
}

struct SplitDiffSide: Sendable {
    let sourceLineID: DiffIdentity?
    let lineNumber: Int?
    let lineType: DiffLine.LineType
    let content: String
    let wordChanges: [DiffWordChange]?
    let highlightSegment: DiffHighlightSegment?
}

struct SplitDiffRow: Identifiable, Sendable {
    enum Kind: Sendable {
        case hunkHeader
        case line
    }

    let id: String
    let kind: Kind
    let left: SplitDiffSide?
    let right: SplitDiffSide?
}

struct UnifiedDiffLayout: Sendable {
    let rows: [UnifiedDiffRow]
    let hunkHeaders: [DiffHunkHeaderLayout]
    let contentSize: CGSize
    let maxLineNumberDigits: Int
    let sourceDocuments: DiffSourceDocuments
}

struct SplitDiffLayout: Sendable {
    let rows: [SplitDiffRow]
    let hunkHeaders: [DiffHunkHeaderLayout]
    let contentSize: CGSize
    let maxLineNumberDigits: Int
    let sourceDocuments: DiffSourceDocuments
}

enum DiffRenderLayout: Sendable {
    case unified(UnifiedDiffLayout)
    case split(SplitDiffLayout)

    var contentSize: CGSize {
        switch self {
        case .unified(let layout):
            return layout.contentSize
        case .split(let layout):
            return layout.contentSize
        }
    }

    var hunkHeaders: [DiffHunkHeaderLayout] {
        switch self {
        case .unified(let layout):
            return layout.hunkHeaders
        case .split(let layout):
            return layout.hunkHeaders
        }
    }

    var maxLineNumberDigits: Int {
        switch self {
        case .unified(let layout):
            return layout.maxLineNumberDigits
        case .split(let layout):
            return layout.maxLineNumberDigits
        }
    }

    var sourceDocuments: DiffSourceDocuments {
        switch self {
        case .unified(let layout):
            return layout.sourceDocuments
        case .split(let layout):
            return layout.sourceDocuments
        }
    }
}
