// EditorDocumentTests.swift
// DevysEditor - Metal-accelerated code editor
//
// Tests for EditorDocument.

import Foundation
import Testing
import Text
@testable import Editor

private struct PreparedDocumentIOService: DocumentIOService {
    let textDocument: TextDocument
    let language: String

    func loadPreview(url _: URL, request: DocumentPreviewRequest) async throws -> LoadedDocumentPreview {
        LoadedDocumentPreview(
            kind: .text(
                textDocument.snapshot().slice(
                    TextByteRange(0, textDocument.snapshot().utf8Length)
                ).text
            ),
            language: language,
            revision: DocumentPreviewRevision(fileSize: nil, contentModificationDate: nil),
            exceededLimit: false,
            maxBytes: request.maxBytes
        )
    }

    func load(url _: URL) async throws -> LoadedDocumentContents {
        LoadedDocumentContents(
            textDocument: textDocument,
            language: language
        )
    }
}

@Suite("EditorDocument Tests")
struct EditorDocumentTests {
    
    @Test("Creates empty document")
    @MainActor
    func testEmptyDocument() {
        let doc = EditorDocument(content: "")
        #expect(doc.lineCount == 1)
        #expect(doc.line(at: 0) == "")
    }
    
    @Test("Creates document with content")
    @MainActor
    func testDocumentWithContent() {
        let doc = EditorDocument(content: "Hello\nWorld")
        #expect(doc.lineCount == 2)
        #expect(doc.characterCount == "Hello\nWorld".count)
        #expect(doc.line(at: 0) == "Hello")
        #expect(doc.line(at: 1) == "World")
    }

    @Test("Unchanged content produces a stable reopen identity across fresh documents")
    @MainActor
    func testStableReopenIdentityAcrossFreshDocuments() {
        let first = EditorDocument(content: "let value = 1\n", language: "swift")
        let second = EditorDocument(content: "let value = 1\n", language: "swift")

        #expect(first.reopenIdentity == second.reopenIdentity)
    }
    
    @Test("Inserts text")
    @MainActor
    func testInsertText() {
        let doc = EditorDocument(content: "Hello")
        let originalIdentity = doc.reopenIdentity
        doc.cursor.position = TextPosition(line: 0, column: 5)
        doc.insert(" World")
        #expect(doc.line(at: 0) == "Hello World")
        #expect(doc.reopenIdentity != originalIdentity)
    }
    
    @Test("Deletes backward")
    @MainActor
    func testDeleteBackward() {
        let doc = EditorDocument(content: "Hello")
        doc.cursor.position = TextPosition(line: 0, column: 5)
        doc.deleteBackward()
        #expect(doc.line(at: 0) == "Hell")
    }
    
    @Test("Moves cursor")
    @MainActor
    func testCursorMovement() {
        let doc = EditorDocument(content: "Hello\nWorld")
        
        doc.cursor.position = TextPosition(line: 0, column: 0)
        doc.moveCursorRight()
        #expect(doc.cursor.position.column == 1)
        
        doc.moveCursorDown()
        #expect(doc.cursor.position.line == 1)
        
        doc.moveCursorToLineEnd()
        #expect(doc.cursor.position.column == 5)
    }

    @Test("Edits multibyte characters using character columns")
    @MainActor
    func testMultibyteCharacterEditing() {
        let doc = EditorDocument(content: "A🙂B")
        doc.cursor.position = TextPosition(line: 0, column: 2)

        doc.deleteBackward()
        #expect(doc.line(at: 0) == "AB")

        doc.cursor.position = TextPosition(line: 0, column: 1)
        doc.insert("é")
        #expect(doc.line(at: 0) == "AéB")
    }

    @Test("Loads from a prebuilt text document")
    @MainActor
    func testLoadFromPreparedTextDocument() async throws {
        let url = URL(fileURLWithPath: "/tmp/Prepared.swift")
        let prepared = TextDocument(content: "struct Example {}\n")
        let service = PreparedDocumentIOService(
            textDocument: prepared,
            language: "swift"
        )

        let document = try await EditorDocument.load(from: url, ioService: service)

        #expect(document.content == "struct Example {}\n")
        #expect(document.lineCount == 2)
        #expect(document.fileURL == url)
    }

    @Test("Preview-backed document upgrades to prepared text ownership in place")
    @MainActor
    func testPreviewDocumentActivatesPreparedTextDocument() async throws {
        let url = URL(fileURLWithPath: "/tmp/PreviewUpgrade.swift")
        let document = EditorDocument.makePreviewDocument(
            content: "let preview = true\n",
            language: "swift",
            fileURL: url
        )

        let expectedVersion = document.documentVersion
        #expect(document.snapshot == nil)
        #expect(document.hasLoadedTextDocument == false)
        #expect(document.content == "let preview = true\n")

        let prepared = try await EditorDocument.prepareTextDocument(content: document.content)
        try await document.activatePreparedTextDocument(
            prepared,
            expectedVersion: expectedVersion,
            fileURL: url
        )

        #expect(document.snapshot != nil)
        #expect(document.hasLoadedTextDocument)
        #expect(document.content == "let preview = true\n")
        #expect(document.fileURL == url)
    }

    @Test("Loaded documents adopt a prepared reload when the version still matches")
    @MainActor
    func testLoadedDocumentActivatesPreparedReloadInPlace() async throws {
        let url = URL(fileURLWithPath: "/tmp/LoadedReload.swift")
        let document = EditorDocument(
            content: "let stale = true\n",
            language: "swift"
        )
        document.fileURL = url

        let expectedVersion = document.documentVersion
        let prepared = try await EditorDocument.prepareTextDocument(content: "let fresh = true\n")

        try await document.activatePreparedTextDocument(
            prepared,
            expectedVersion: expectedVersion,
            fileURL: url
        )

        #expect(document.hasLoadedTextDocument)
        #expect(document.content == "let fresh = true\n")
        #expect(document.fileURL == url)
    }

    @Test("Find matches uses smart case and respects limits")
    @MainActor
    func testFindMatchesUsesSmartCaseAndRespectsLimits() {
        let document = EditorDocument(
            content: """
            Alpha alpha
            alpha
            """,
            language: "swift"
        )

        let limitedInsensitiveMatches = document.findMatches(for: "alpha", limit: 2)
        #expect(limitedInsensitiveMatches.count == 2)
        #expect(
            limitedInsensitiveMatches == [
                EditorSearchMatch(startLine: 0, startColumn: 0, endLine: 0, endColumn: 5),
                EditorSearchMatch(startLine: 0, startColumn: 6, endLine: 0, endColumn: 11),
            ]
        )

        let caseSensitiveMatches = document.findMatches(for: "Alpha")
        #expect(
            caseSensitiveMatches == [
                EditorSearchMatch(startLine: 0, startColumn: 0, endLine: 0, endColumn: 5)
            ]
        )
    }

    @Test("Navigation targets update selection and clamp locations")
    @MainActor
    func testApplyNavigationTargetUpdatesSelectionAndClampsLocations() {
        let document = EditorDocument(
            content: """
            Hello
            World
            """,
            language: "swift"
        )

        let match = EditorSearchMatch(startLine: 1, startColumn: 1, endLine: 1, endColumn: 4)
        document.applyNavigationTarget(.match(match))

        #expect(document.selectedText == "orl")
        #expect(document.cursor.position.line == 1)
        #expect(document.cursor.position.column == 1)

        document.applyNavigationTarget(.location(line: 8, column: 99))

        #expect(document.selectedText == nil)
        #expect(document.cursor.position.line == 1)
        #expect(document.cursor.position.column == 5)
    }
}
