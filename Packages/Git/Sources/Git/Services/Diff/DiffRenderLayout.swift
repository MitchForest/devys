// DiffRenderLayout.swift
// Layout models for Metal diff rendering.

import Foundation
import CoreGraphics

struct DiffWordChange: Sendable, Equatable {
    let range: Range<Int>
    let type: WordDiff.ChangeType
}

struct DiffHunkHeaderLayout: Identifiable, Sendable {
    let id: UUID
    let hunkIndex: Int
    let rowIndex: Int
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int

    init(hunkIndex: Int, rowIndex: Int, hunk: DiffHunk) {
        self.id = hunk.id
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

    let id: UUID
    let kind: Kind
    let lineType: DiffLine.LineType
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let content: String
    let wordChanges: [DiffWordChange]?

    init(
        id: UUID = UUID(),
        kind: Kind,
        lineType: DiffLine.LineType,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        content: String,
        wordChanges: [DiffWordChange]?
    ) {
        self.id = id
        self.kind = kind
        self.lineType = lineType
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.content = content
        self.wordChanges = wordChanges
    }
}

struct SplitDiffSide: Sendable {
    let lineNumber: Int?
    let lineType: DiffLine.LineType
    let content: String
    let wordChanges: [DiffWordChange]?
}

struct SplitDiffRow: Identifiable, Sendable {
    enum Kind: Sendable {
        case hunkHeader
        case line
    }

    let id: UUID
    let kind: Kind
    let left: SplitDiffSide?
    let right: SplitDiffSide?

    init(
        id: UUID = UUID(),
        kind: Kind,
        left: SplitDiffSide?,
        right: SplitDiffSide?
    ) {
        self.id = id
        self.kind = kind
        self.left = left
        self.right = right
    }
}

struct UnifiedDiffLayout: Sendable {
    let rows: [UnifiedDiffRow]
    let hunkHeaders: [DiffHunkHeaderLayout]
    let contentSize: CGSize
    let maxLineNumberDigits: Int
}

struct SplitDiffLayout: Sendable {
    let rows: [SplitDiffRow]
    let hunkHeaders: [DiffHunkHeaderLayout]
    let contentSize: CGSize
    let maxLineNumberDigits: Int
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
}
