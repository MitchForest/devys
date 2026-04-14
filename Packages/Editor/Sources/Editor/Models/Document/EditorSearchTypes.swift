// EditorSearchTypes.swift
// DevysEditor - Search and navigation primitives.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

public struct EditorSearchMatch: Equatable, Sendable, Identifiable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int

    public init(
        startLine: Int,
        startColumn: Int,
        endLine: Int,
        endColumn: Int
    ) {
        self.startLine = startLine
        self.startColumn = startColumn
        self.endLine = endLine
        self.endColumn = endColumn
    }

    public var id: String {
        "\(startLine):\(startColumn):\(endLine):\(endColumn)"
    }
}

public struct EditorNavigationTarget: Equatable, Sendable {
    public let cursorLine: Int
    public let cursorColumn: Int
    public let selection: EditorSearchMatch?

    public init(
        cursorLine: Int,
        cursorColumn: Int,
        selection: EditorSearchMatch? = nil
    ) {
        self.cursorLine = cursorLine
        self.cursorColumn = cursorColumn
        self.selection = selection
    }

    public static func location(line: Int, column: Int) -> EditorNavigationTarget {
        EditorNavigationTarget(cursorLine: line, cursorColumn: column)
    }

    public static func match(_ match: EditorSearchMatch) -> EditorNavigationTarget {
        EditorNavigationTarget(
            cursorLine: match.startLine,
            cursorColumn: match.startColumn,
            selection: match
        )
    }
}
