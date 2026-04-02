// EditorDocument.swift
// DevysEditor - Metal-accelerated code editor
//
// Text storage and document model.

import Foundation
import Syntax

// MARK: - Text Position

/// A position in the document (line, column)
struct TextPosition: Equatable, Hashable, Sendable {
    var line: Int
    var column: Int

    static let zero = TextPosition(line: 0, column: 0)
}

// MARK: - Text Range

/// A range in the document
struct TextRange: Equatable, Sendable {
    var start: TextPosition
    var end: TextPosition

    var isEmpty: Bool {
        start == end
    }
    
    /// Normalized range (start before end)
    var normalized: TextRange {
        if start.line > end.line || (start.line == end.line && start.column > end.column) {
            return TextRange(start: end, end: start)
        }
        return self
    }
}

// MARK: - Editor Cursor

/// Cursor state
struct EditorCursor: Equatable, Sendable {
    var position: TextPosition
    var preferredColumn: Int?  // For vertical movement
    
    init(position: TextPosition = .zero) {
        self.position = position
        self.preferredColumn = nil
    }
}

// MARK: - Editor Document

/// The source of truth for document content.
@MainActor
@Observable
public final class EditorDocument {
    
    // MARK: - Text Storage
    
    /// Lines of text
    private var lines: [String]
    
    /// Line count
    var lineCount: Int { lines.count }
    
    /// Total character count
    private(set) var characterCount: Int = 0
    
    // MARK: - Cursor
    
    /// Primary cursor
    var cursor = EditorCursor()
    
    /// Selection range (nil if no selection)
    var selection: TextRange?
    
    // MARK: - Metadata
    
    /// File URL
    public var fileURL: URL?
    
    /// Language identifier
    var language: String
    
    /// Whether document has unsaved changes
    public var isDirty: Bool = false
    
    // MARK: - Initialization
    
    /// Create document with content
    public init(content: String, language: String = "plaintext") {
        var parsedLines = content.components(separatedBy: "\n")
        if parsedLines.isEmpty {
            parsedLines = [""]
        }
        self.lines = parsedLines
        self.language = language
        recalculateCharacterCount()
    }
    
    /// Create document from file contents.
    public static func load(from url: URL) async throws -> EditorDocument {
        try await load(from: url, ioService: DefaultDocumentIOService())
    }

    static func load(
        from url: URL,
        ioService: DocumentIOService
    ) async throws -> EditorDocument {
        let result = try await ioService.load(url: url)
        let document = EditorDocument(content: result.content, language: result.language)
        document.fileURL = url
        document.isDirty = false
        return document
    }
    
    // MARK: - Line Access
    
    /// Get a line by index
    func line(at index: Int) -> String {
        guard index >= 0 && index < lines.count else {
            return ""
        }
        return lines[index]
    }
    
    /// Get multiple lines
    func lines(in range: Range<Int>) -> [String] {
        let start = max(0, range.lowerBound)
        let end = min(lines.count, range.upperBound)
        guard start < end else { return [] }
        return Array(lines[start..<end])
    }
    
    /// Get line length
    func lineLength(at index: Int) -> Int {
        line(at: index).count
    }
    
    // MARK: - Content
    
    /// Get full content as string
    public var content: String {
        lines.joined(separator: "\n")
    }

    /// End position in document.
    var endPosition: TextPosition {
        let lastLineIndex = max(0, lines.count - 1)
        return TextPosition(line: lastLineIndex, column: lineLength(at: lastLineIndex))
    }
    
    // MARK: - Editing
    
    /// Insert text at cursor
    func insert(_ text: String) {
        insert(text, at: cursor.position)
    }

    /// Replace range with text.
    func replace(_ range: TextRange, with text: String) {
        let start = range.normalized.start
        delete(range)
        insert(text, at: start)
    }
    
    /// Insert text at position
    func insert(_ text: String, at position: TextPosition) {
        guard position.line >= 0 && position.line < lines.count else { return }
        
        let insertLines = text.components(separatedBy: "\n")
        let currentLine = lines[position.line]
        let col = min(position.column, currentLine.count)
        
        let prefix = String(currentLine.prefix(col))
        let suffix = String(currentLine.dropFirst(col))
        
        if insertLines.count == 1 {
            // Single line insert
            lines[position.line] = prefix + insertLines[0] + suffix
            cursor.position = TextPosition(
                line: position.line,
                column: col + insertLines[0].count
            )
        } else {
            // Multi-line insert
            var newLines: [String] = []
            newLines.append(prefix + insertLines[0])
            for i in 1..<(insertLines.count - 1) {
                newLines.append(insertLines[i])
            }
            guard let lastLine = insertLines.last else { return }
            newLines.append(lastLine + suffix)
            
            lines.replaceSubrange(position.line...position.line, with: newLines)
            
            cursor.position = TextPosition(
                line: position.line + insertLines.count - 1,
                column: lastLine.count
            )
        }
        
        recalculateCharacterCount()
        selection = nil
        isDirty = true
    }
    
    /// Delete character before cursor (backspace)
    func deleteBackward() {
        guard cursor.position.column > 0 || cursor.position.line > 0 else { return }
        
        if cursor.position.column > 0 {
            // Delete character on current line
            let line = lines[cursor.position.line]
            let index = line.index(line.startIndex, offsetBy: cursor.position.column - 1)
            lines[cursor.position.line].remove(at: index)
            cursor.position.column -= 1
        } else {
            // Join with previous line
            let currentLine = lines[cursor.position.line]
            let prevLine = lines[cursor.position.line - 1]
            lines[cursor.position.line - 1] = prevLine + currentLine
            lines.remove(at: cursor.position.line)
            cursor.position = TextPosition(
                line: cursor.position.line - 1,
                column: prevLine.count
            )
        }
        
        recalculateCharacterCount()
        isDirty = true
    }
    
    /// Delete character after cursor
    func deleteForward() {
        let lineLength = lineLength(at: cursor.position.line)
        
        if cursor.position.column < lineLength {
            // Delete character on current line
            let line = lines[cursor.position.line]
            let index = line.index(line.startIndex, offsetBy: cursor.position.column)
            lines[cursor.position.line].remove(at: index)
        } else if cursor.position.line < lines.count - 1 {
            // Join with next line
            let nextLine = lines[cursor.position.line + 1]
            lines[cursor.position.line] += nextLine
            lines.remove(at: cursor.position.line + 1)
        }
        
        recalculateCharacterCount()
        isDirty = true
    }

    /// Get text inside a range.
    func text(in range: TextRange) -> String {
        let normalized = range.normalized
        let start = clamped(normalized.start)
        let end = clamped(normalized.end)

        guard start != end else { return "" }

        if start.line == end.line {
            let line = lines[start.line]
            let startIndex = line.index(line.startIndex, offsetBy: start.column)
            let endIndex = line.index(line.startIndex, offsetBy: end.column)
            return String(line[startIndex..<endIndex])
        }

        var parts: [String] = []
        let firstLine = lines[start.line]
        parts.append(String(firstLine.dropFirst(start.column)))

        if end.line > start.line + 1 {
            for index in (start.line + 1)..<end.line {
                parts.append(lines[index])
            }
        }

        let lastLine = lines[end.line]
        parts.append(String(lastLine.prefix(end.column)))

        return parts.joined(separator: "\n")
    }

    /// Delete text inside a range.
    func delete(_ range: TextRange) {
        let normalized = range.normalized
        let start = clamped(normalized.start)
        let end = clamped(normalized.end)

        guard start != end else { return }

        if start.line == end.line {
            let line = lines[start.line]
            let startIndex = line.index(line.startIndex, offsetBy: start.column)
            let endIndex = line.index(line.startIndex, offsetBy: end.column)
            lines[start.line].removeSubrange(startIndex..<endIndex)
        } else {
            let startLine = lines[start.line]
            let endLine = lines[end.line]
            let prefix = String(startLine.prefix(start.column))
            let suffix = String(endLine.dropFirst(end.column))
            lines[start.line] = prefix + suffix
            if end.line > start.line {
                lines.removeSubrange((start.line + 1)...end.line)
            }
        }

        cursor.position = start
        cursor.preferredColumn = nil
        selection = nil
        recalculateCharacterCount()
        isDirty = true
    }
    
    // MARK: - Cursor Movement
    
    /// Move cursor left
    func moveCursorLeft() {
        if cursor.position.column > 0 {
            cursor.position.column -= 1
        } else if cursor.position.line > 0 {
            cursor.position.line -= 1
            cursor.position.column = lineLength(at: cursor.position.line)
        }
        cursor.preferredColumn = nil
    }
    
    /// Move cursor right
    func moveCursorRight() {
        let lineLength = lineLength(at: cursor.position.line)
        if cursor.position.column < lineLength {
            cursor.position.column += 1
        } else if cursor.position.line < lines.count - 1 {
            cursor.position.line += 1
            cursor.position.column = 0
        }
        cursor.preferredColumn = nil
    }
    
    /// Move cursor up
    func moveCursorUp() {
        guard cursor.position.line > 0 else { return }
        
        let preferredCol = cursor.preferredColumn ?? cursor.position.column
        cursor.position.line -= 1
        cursor.position.column = min(preferredCol, lineLength(at: cursor.position.line))
        cursor.preferredColumn = preferredCol
    }
    
    /// Move cursor down
    func moveCursorDown() {
        guard cursor.position.line < lines.count - 1 else { return }
        
        let preferredCol = cursor.preferredColumn ?? cursor.position.column
        cursor.position.line += 1
        cursor.position.column = min(preferredCol, lineLength(at: cursor.position.line))
        cursor.preferredColumn = preferredCol
    }
    
    /// Move cursor to line start
    func moveCursorToLineStart() {
        cursor.position.column = 0
        cursor.preferredColumn = nil
    }
    
    /// Move cursor to line end
    func moveCursorToLineEnd() {
        cursor.position.column = lineLength(at: cursor.position.line)
        cursor.preferredColumn = nil
    }
    
    // MARK: - Helpers
    
    private func recalculateCharacterCount() {
        characterCount = lines.reduce(0) { $0 + $1.count } + max(0, lines.count - 1)
    }

    private func clamped(_ position: TextPosition) -> TextPosition {
        let line = min(max(position.line, 0), max(0, lines.count - 1))
        let column = min(max(position.column, 0), lineLength(at: line))
        return TextPosition(line: line, column: column)
    }
}
