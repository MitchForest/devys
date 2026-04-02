// EditorDocumentTests.swift
// DevysEditor - Metal-accelerated code editor
//
// Tests for EditorDocument.

import Testing
@testable import Editor

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
        #expect(doc.line(at: 0) == "Hello")
        #expect(doc.line(at: 1) == "World")
    }
    
    @Test("Inserts text")
    @MainActor
    func testInsertText() {
        let doc = EditorDocument(content: "Hello")
        doc.cursor.position = TextPosition(line: 0, column: 5)
        doc.insert(" World")
        #expect(doc.line(at: 0) == "Hello World")
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
}
