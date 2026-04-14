// EditorDocument.swift
// DevysEditor - Metal-accelerated code editor
//
// Text storage and document model.

// swiftlint:disable file_length type_body_length

import Foundation
import Syntax
import Text

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
    var preferredColumn: Int?

    init(position: TextPosition = .zero) {
        self.position = position
        self.preferredColumn = nil
    }
}

private struct PreviewTextStorage: Sendable {
    var lines: [String]
    var version: DocumentVersion

    init(content: String, version: DocumentVersion = DocumentVersion()) {
        let parsedLines = content.components(separatedBy: "\n")
        self.lines = parsedLines.isEmpty ? [""] : parsedLines
        self.version = version
    }

    var lineCount: Int {
        lines.count
    }

    // periphery:ignore - exposed to editor state inspection and metrics tooling
    var characterCount: Int {
        lines.reduce(0) { $0 + $1.count } + max(0, lines.count - 1)
    }

    var content: String {
        lines.joined(separator: "\n")
    }
}

struct EditorDocumentReopenIdentity: Sendable, Hashable {
    let contentFingerprint: UInt64
    let mutationGeneration: UInt64

    static let empty = EditorDocumentReopenIdentity(
        contentFingerprint: 0,
        mutationGeneration: 0
    )

    func mutated() -> EditorDocumentReopenIdentity {
        EditorDocumentReopenIdentity(
            contentFingerprint: contentFingerprint,
            mutationGeneration: mutationGeneration &+ 1
        )
    }
}

// MARK: - Editor Document

/// The source of truth for document content.
@MainActor
@Observable
public final class EditorDocument {

    // MARK: - Text Storage

    private var textDocument: TextDocument?
    private var textSnapshot: DocumentSnapshot?
    private var previewStorage: PreviewTextStorage?
    private(set) var reopenIdentity: EditorDocumentReopenIdentity

    var lineCount: Int {
        textSnapshot?.lineCount ?? previewStorage?.lineCount ?? 1
    }

    // periphery:ignore - exposed to editor state inspection and metrics tooling
    var characterCount: Int {
        textSnapshot?.characterCount ?? previewStorage?.characterCount ?? 0
    }

    public var documentVersion: DocumentVersion {
        textSnapshot?.version ?? previewStorage?.version ?? DocumentVersion()
    }

    var snapshot: DocumentSnapshot? {
        textSnapshot
    }

    // periphery:ignore - queried by app state observers outside Periphery's call graph
    var hasLoadedTextDocument: Bool {
        textSnapshot != nil
    }

    var loadStateRevision: Int = 0

    // MARK: - Cursor

    var cursor = EditorCursor()
    var selection: TextRange?

    // MARK: - Metadata

    public var fileURL: URL?
    var language: String
    var syntaxController: SyntaxController?
    var syntaxThemeName: String?
    var syntaxMaximumTokenizationLineLength: Int?
    private var pendingSyntaxUpdate: SyntaxDocumentUpdate?
    public var isDirty: Bool = false

    // MARK: - Initialization

    public init(content: String, language: String = "plaintext") {
        let textDocument = TextDocument(content: content)
        self.textDocument = textDocument
        self.textSnapshot = textDocument.snapshot()
        self.previewStorage = nil
        self.language = language
        self.reopenIdentity = Self.makeReopenIdentity(for: content)
    }

    public init(previewContent: String, language: String = "plaintext") {
        self.textDocument = nil
        self.textSnapshot = nil
        self.previewStorage = PreviewTextStorage(content: previewContent)
        self.language = language
        self.reopenIdentity = Self.makeReopenIdentity(for: previewContent)
    }

    init(textDocument: TextDocument, language: String) {
        let snapshot = textDocument.snapshot()
        self.textDocument = textDocument
        self.textSnapshot = snapshot
        self.previewStorage = nil
        self.language = language
        self.reopenIdentity = Self.makeReopenIdentity(for: snapshot)
    }

    public static func load(from url: URL) async throws -> EditorDocument {
        try await load(from: url, ioService: DefaultDocumentIOService())
    }

    public static func makePreviewDocument(
        content: String,
        language: String,
        fileURL: URL? = nil
    ) -> EditorDocument {
        let document = EditorDocument(previewContent: content, language: language)
        document.fileURL = fileURL
        document.isDirty = false
        return document
    }

    public static func prepareTextDocument(content: String) async throws -> TextDocument {
        try await Task.detached(priority: .userInitiated) {
            TextDocument(content: content)
        }.value
    }

    public static func makeLoadedDocument(
        content: String,
        language: String,
        fileURL: URL? = nil
    ) async throws -> EditorDocument {
        let textDocument = try await prepareTextDocument(content: content)

        return await MainActor.run {
            let document = EditorDocument(
                textDocument: textDocument,
                language: language
            )
            document.fileURL = fileURL
            document.isDirty = false
            return document
        }
    }

    static func load(
        from url: URL,
        ioService: sending any DocumentIOService
    ) async throws -> EditorDocument {
        let result = try await ioService.load(url: url)
        let document = EditorDocument(
            textDocument: result.textDocument,
            language: result.language
        )
        document.fileURL = url
        document.isDirty = false
        return document
    }

    public func activatePreparedTextDocument(
        _ preparedTextDocument: TextDocument,
        expectedVersion: DocumentVersion,
        fileURL: URL? = nil
    ) async throws {
        let contentForActivation = content
        let currentVersion = documentVersion
        let shouldAdoptPrepared =
            currentVersion == expectedVersion &&
            !isDirty

        let finalTextDocument = shouldAdoptPrepared
            ? preparedTextDocument
            : try await Self.prepareTextDocument(content: contentForActivation)

        self.textDocument = finalTextDocument
        self.textSnapshot = finalTextDocument.snapshot()
        self.previewStorage = nil
        self.fileURL = fileURL ?? self.fileURL
        loadStateRevision += 1
        if let textSnapshot {
            reopenIdentity = Self.makeReopenIdentity(for: textSnapshot)
        }

        if let themeName = syntaxThemeName,
           let textSnapshot {
            syntaxController = SyntaxController(
                documentSnapshot: textSnapshot,
                language: language,
                themeName: themeName,
                warmCacheIdentity: syntaxWarmCacheIdentity,
                maximumTokenizationLineLength: syntaxMaximumTokenizationLineLength ?? 0
            )
        }
    }

    // MARK: - Line Access

    func line(at index: Int) -> String {
        if let textSnapshot {
            guard index >= 0 && index < textSnapshot.lineCount else {
                return ""
            }
            return textSnapshot.line(index).text
        }

        guard let previewStorage,
              index >= 0,
              index < previewStorage.lines.count else {
            return ""
        }
        return previewStorage.lines[index]
    }

    func lines(in range: Range<Int>) -> [String] {
        if let textSnapshot {
            let start = max(0, range.lowerBound)
            let end = min(textSnapshot.lineCount, range.upperBound)
            guard start < end else { return [] }
            return Array(textSnapshot.lines(in: start..<end).map(\.text))
        }

        guard let previewStorage else { return [] }
        let start = max(0, range.lowerBound)
        let end = min(previewStorage.lines.count, range.upperBound)
        guard start < end else { return [] }
        return Array(previewStorage.lines[start..<end])
    }

    func lineLength(at index: Int) -> Int {
        line(at: index).count
    }

    // MARK: - Content

    public var content: String {
        if let textSnapshot {
            return textSnapshot.slice(TextByteRange(0, textSnapshot.utf8Length)).text
        }
        return previewStorage?.content ?? ""
    }

    public var selectedText: String? {
        guard let selection, !selection.isEmpty else { return nil }
        return text(in: selection)
    }

    var syntaxWarmCacheIdentity: SyntaxWarmCacheIdentity {
        SyntaxWarmCacheIdentity(
            contentFingerprint: reopenIdentity.contentFingerprint,
            mutationGeneration: reopenIdentity.mutationGeneration
        )
    }

    @discardableResult
    func ensureSyntaxController(
        themeName: String,
        maximumTokenizationLineLength: Int = 0
    ) -> SyntaxController? {
        guard let textSnapshot else {
            return syntaxController
        }

        if let syntaxController,
           syntaxThemeName == themeName,
           syntaxMaximumTokenizationLineLength == maximumTokenizationLineLength {
            return syntaxController
        }

        let syntaxController = SyntaxController(
            documentSnapshot: textSnapshot,
            language: language,
            themeName: themeName,
            warmCacheIdentity: syntaxWarmCacheIdentity,
            maximumTokenizationLineLength: maximumTokenizationLineLength
        )
        self.syntaxController = syntaxController
        self.syntaxThemeName = themeName
        self.syntaxMaximumTokenizationLineLength = maximumTokenizationLineLength
        return syntaxController
    }

    func adoptSyntaxController(
        _ syntaxController: SyntaxController,
        themeName: String,
        maximumTokenizationLineLength: Int? = nil
    ) {
        syntaxController.updateWarmCacheIdentity(syntaxWarmCacheIdentity)
        self.syntaxController = syntaxController
        self.syntaxThemeName = themeName
        self.syntaxMaximumTokenizationLineLength = maximumTokenizationLineLength
    }

    func syncSyntaxController(dirtyFrom lineIndex: Int) {
        guard let textSnapshot else { return }
        syntaxController?.updateWarmCacheIdentity(syntaxWarmCacheIdentity)
        if let pendingSyntaxUpdate,
           pendingSyntaxUpdate.newSnapshot.version == textSnapshot.version {
            syntaxController?.updateDocument(pendingSyntaxUpdate, dirtyFrom: lineIndex)
            self.pendingSyntaxUpdate = nil
        } else {
            syntaxController?.updateDocument(textSnapshot, dirtyFrom: lineIndex)
        }
    }

    var endPosition: TextPosition {
        let lastLineIndex = max(0, lineCount - 1)
        return TextPosition(
            line: lastLineIndex,
            column: lineLength(at: lastLineIndex)
        )
    }

    // MARK: - Editing

    func insert(_ text: String) {
        insert(text, at: cursor.position)
    }

    func replace(_ range: TextRange, with text: String) {
        let normalized = clamped(range.normalized)
        guard normalized.start != normalized.end else {
            insert(text, at: normalized.start)
            return
        }

        applyReplacement(in: normalized, with: text)
        cursor.position = endingPosition(
            afterInserting: text,
            at: normalized.start
        )
        cursor.preferredColumn = nil
        selection = nil
        isDirty = true
    }

    func insert(_ text: String, at position: TextPosition) {
        let position = clamped(position)
        applyReplacement(
            in: TextRange(start: position, end: position),
            with: text
        )
        cursor.position = endingPosition(afterInserting: text, at: position)
        cursor.preferredColumn = nil
        selection = nil
        isDirty = true
    }

    func deleteBackward() {
        guard cursor.position.column > 0 || cursor.position.line > 0 else { return }

        if cursor.position.column > 0 {
            let end = cursor.position
            let start = TextPosition(line: end.line, column: end.column - 1)
            applyReplacement(in: TextRange(start: start, end: end), with: "")
            cursor.position = start
        } else {
            let previousLine = cursor.position.line - 1
            let start = TextPosition(
                line: previousLine,
                column: lineLength(at: previousLine)
            )
            applyReplacement(in: TextRange(start: start, end: cursor.position), with: "")
            cursor.position = start
        }

        cursor.preferredColumn = nil
        isDirty = true
    }

    func deleteForward() {
        let currentLineLength = lineLength(at: cursor.position.line)

        if cursor.position.column < currentLineLength {
            let start = cursor.position
            let end = TextPosition(line: start.line, column: start.column + 1)
            applyReplacement(in: TextRange(start: start, end: end), with: "")
        } else if cursor.position.line < lineCount - 1 {
            let end = TextPosition(line: cursor.position.line + 1, column: 0)
            applyReplacement(in: TextRange(start: cursor.position, end: end), with: "")
        }

        cursor.preferredColumn = nil
        isDirty = true
    }

    func text(in range: TextRange) -> String {
        let normalized = clamped(range.normalized)
        guard normalized.start != normalized.end else { return "" }

        if let textSnapshot {
            return textSnapshot.slice(utf8ByteRange(for: normalized)).text
        }

        let start = normalized.start
        let end = normalized.end
        guard let previewStorage else { return "" }

        if start.line == end.line {
            let line = previewStorage.lines[start.line]
            let startIndex = line.index(line.startIndex, offsetBy: start.column)
            let endIndex = line.index(line.startIndex, offsetBy: end.column)
            return String(line[startIndex..<endIndex])
        }

        var parts: [String] = []
        let firstLine = previewStorage.lines[start.line]
        parts.append(String(firstLine.dropFirst(start.column)))

        if end.line > start.line + 1 {
            for index in (start.line + 1)..<end.line {
                parts.append(previewStorage.lines[index])
            }
        }

        let lastLine = previewStorage.lines[end.line]
        parts.append(String(lastLine.prefix(end.column)))

        return parts.joined(separator: "\n")
    }

    public func findMatches(
        for query: String,
        caseSensitive: Bool? = nil,
        limit: Int = 500
    ) -> [EditorSearchMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, limit > 0 else { return [] }

        let shouldUseCaseSensitiveSearch: Bool
        if let caseSensitive {
            shouldUseCaseSensitiveSearch = caseSensitive
        } else {
            shouldUseCaseSensitiveSearch = trimmedQuery.contains { $0.isUppercase }
        }

        let compareLine: (String) -> String = shouldUseCaseSensitiveSearch
            ? { $0 }
            : { $0.lowercased() }

        let needle = compareLine(trimmedQuery)
        var matches: [EditorSearchMatch] = []
        matches.reserveCapacity(min(lineCount, limit))

        for lineIndex in 0..<lineCount {
            let line = line(at: lineIndex)
            let haystack = compareLine(line)
            var searchStartIndex = haystack.startIndex

            while searchStartIndex < haystack.endIndex,
                  let range = haystack.range(of: needle, range: searchStartIndex..<haystack.endIndex) {
                let startColumn = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
                let endColumn = haystack.distance(from: haystack.startIndex, to: range.upperBound)
                matches.append(
                    EditorSearchMatch(
                        startLine: lineIndex,
                        startColumn: startColumn,
                        endLine: lineIndex,
                        endColumn: endColumn
                    )
                )
                if matches.count >= limit {
                    return matches
                }
                searchStartIndex = range.upperBound
            }
        }

        return matches
    }

    func delete(_ range: TextRange) {
        let normalized = clamped(range.normalized)
        guard normalized.start != normalized.end else { return }

        applyReplacement(in: normalized, with: "")
        cursor.position = normalized.start
        cursor.preferredColumn = nil
        selection = nil
        isDirty = true
    }

    // MARK: - Cursor Movement

    func moveCursorLeft() {
        if cursor.position.column > 0 {
            cursor.position.column -= 1
        } else if cursor.position.line > 0 {
            cursor.position.line -= 1
            cursor.position.column = lineLength(at: cursor.position.line)
        }
        cursor.preferredColumn = nil
    }

    func moveCursorRight() {
        let currentLineLength = lineLength(at: cursor.position.line)
        if cursor.position.column < currentLineLength {
            cursor.position.column += 1
        } else if cursor.position.line < lineCount - 1 {
            cursor.position.line += 1
            cursor.position.column = 0
        }
        cursor.preferredColumn = nil
    }

    func moveCursorUp() {
        guard cursor.position.line > 0 else { return }

        let preferredColumn = cursor.preferredColumn ?? cursor.position.column
        cursor.position.line -= 1
        cursor.position.column = min(preferredColumn, lineLength(at: cursor.position.line))
        cursor.preferredColumn = preferredColumn
    }

    func moveCursorDown() {
        guard cursor.position.line < lineCount - 1 else { return }

        let preferredColumn = cursor.preferredColumn ?? cursor.position.column
        cursor.position.line += 1
        cursor.position.column = min(preferredColumn, lineLength(at: cursor.position.line))
        cursor.preferredColumn = preferredColumn
    }

    func moveCursorToLineStart() {
        cursor.position.column = 0
        cursor.preferredColumn = nil
    }

    func moveCursorToLineEnd() {
        cursor.position.column = lineLength(at: cursor.position.line)
        cursor.preferredColumn = nil
    }

    public func applyNavigationTarget(_ target: EditorNavigationTarget) {
        let clampedTargetPosition = clamped(
            TextPosition(line: target.cursorLine, column: target.cursorColumn)
        )

        if let selection = target.selection {
            let selectedRange = TextRange(
                start: TextPosition(line: selection.startLine, column: selection.startColumn),
                end: TextPosition(line: selection.endLine, column: selection.endColumn)
            )
            let clampedRange = clamped(selectedRange)
            self.selection = clampedRange
            cursor.position = clampedRange.start
        } else {
            self.selection = nil
            cursor.position = clampedTargetPosition
        }

        cursor.preferredColumn = nil
    }

    // MARK: - Helpers

    private func clamped(_ position: TextPosition) -> TextPosition {
        let line = min(max(position.line, 0), max(0, lineCount - 1))
        let column = min(max(position.column, 0), lineLength(at: line))
        return TextPosition(line: line, column: column)
    }

    private func clamped(_ range: TextRange) -> TextRange {
        TextRange(start: clamped(range.start), end: clamped(range.end))
    }

    private func endingPosition(
        afterInserting text: String,
        at position: TextPosition
    ) -> TextPosition {
        let insertedLines = text.components(separatedBy: "\n")
        if insertedLines.count == 1 {
            return TextPosition(
                line: position.line,
                column: position.column + insertedLines[0].count
            )
        }

        let lastLine = insertedLines.last ?? ""
        return TextPosition(
            line: position.line + insertedLines.count - 1,
            column: lastLine.count
        )
    }

    private func applyReplacement(
        in range: TextRange,
        with replacement: String
    ) {
        if let textDocument {
            let oldSnapshot = textSnapshot ?? textDocument.snapshot()
            let transaction = EditTransaction(
                edits: [
                    TextEdit(
                        range: utf8ByteRange(for: range),
                        replacement: replacement
                    )
                ]
            )

            _ = textDocument.apply(transaction)
            let newSnapshot = textDocument.snapshot()
            textSnapshot = newSnapshot
            pendingSyntaxUpdate = SyntaxDocumentUpdate(
                oldSnapshot: oldSnapshot,
                newSnapshot: newSnapshot,
                transaction: transaction
            )
        } else {
            applyPreviewReplacement(in: range, with: replacement)
        }

        reopenIdentity = reopenIdentity.mutated()
        loadStateRevision += 1
    }

    private func applyPreviewReplacement(
        in range: TextRange,
        with replacement: String
    ) {
        guard var previewStorage else { return }

        let start = range.start
        let end = range.end

        let startLine = previewStorage.lines[start.line]
        let endLine = previewStorage.lines[end.line]
        let prefix = String(startLine.prefix(start.column))
        let suffix = String(endLine.dropFirst(end.column))
        let replacementLines = replacement.components(separatedBy: "\n")

        var newLines: [String]
        if replacementLines.count == 1 {
            newLines = [prefix + replacementLines[0] + suffix]
        } else {
            newLines = []
            newLines.append(prefix + replacementLines[0])
            if replacementLines.count > 2 {
                newLines.append(contentsOf: replacementLines[1..<(replacementLines.count - 1)])
            }
            let lastReplacementLine = replacementLines.last ?? ""
            newLines.append(lastReplacementLine + suffix)
        }

        previewStorage.lines.replaceSubrange(start.line...end.line, with: newLines)
        previewStorage.version = previewStorage.version.next()
        self.previewStorage = previewStorage
    }

    private func utf8ByteRange(for range: TextRange) -> TextByteRange {
        TextByteRange(
            utf8Offset(for: range.start),
            utf8Offset(for: range.end)
        )
    }

    private func utf8Offset(for position: TextPosition) -> Int {
        guard let textSnapshot else {
            return 0
        }

        let position = clamped(position)
        let lineText = line(at: position.line)
        let index = lineText.index(lineText.startIndex, offsetBy: position.column)
        let utf8Column = lineText[..<index].utf8.count
        return textSnapshot.offset(
            of: TextPoint(line: position.line, column: utf8Column),
            encoding: .utf8
        )
    }

    private static func makeReopenIdentity(for content: String) -> EditorDocumentReopenIdentity {
        EditorDocumentReopenIdentity(
            contentFingerprint: fnv1a64(content),
            mutationGeneration: 0
        )
    }

    private static func makeReopenIdentity(for snapshot: DocumentSnapshot) -> EditorDocumentReopenIdentity {
        makeReopenIdentity(
            for: snapshot.slice(TextByteRange(0, snapshot.utf8Length)).text
        )
    }

    private static func fnv1a64(_ string: String) -> UInt64 {
        let offsetBasis: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        var hash = offsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}

// swiftlint:enable file_length type_body_length
