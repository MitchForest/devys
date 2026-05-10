import Testing
@testable import Text

struct TextDocumentTests {
    @Test
    func snapshotExposesCanonicalLineAndOffsetAPI() {
        let content = "cafe\ncafe\u{301}\n"
        let document = TextDocument(content: content)
        let snapshot = document.snapshot()

        #expect(snapshot.version == DocumentVersion(0))
        #expect(snapshot.characterCount == content.count)
        #expect(snapshot.lineCount == 3)
        #expect(snapshot.utf8Length == content.utf8.count)
        #expect(snapshot.utf16Length == content.utf16.count)

        #expect(snapshot.line(0).text == "cafe")
        #expect(snapshot.line(1).text == "cafe\u{301}")
        #expect(snapshot.line(2).text == "")

        let lines = snapshot.lines(in: 0..<3)
        #expect(lines.map(\.text) == ["cafe", "cafe\u{301}", ""])

        let utf8Point = TextPoint(line: 1, column: "cafe\u{301}".utf8.count)
        let utf16Point = TextPoint(line: 1, column: "cafe\u{301}".utf16.count)

        #expect(snapshot.offset(of: utf8Point, encoding: .utf8) == 11)
        #expect(snapshot.offset(of: utf16Point, encoding: .utf16) == 10)
        #expect(snapshot.point(at: 11, encoding: .utf8) == utf8Point)
        #expect(snapshot.point(at: 10, encoding: .utf16) == utf16Point)
        #expect(snapshot.slice(TextByteRange(5, 11)).text == "cafe\u{301}")
    }

    @Test
    func applyAdvancesDocumentVersionAndInvalidatesFromFirstChangedLine() {
        let document = TextDocument(content: "alpha\nbravo")
        let snapshot = document.snapshot()
        let bravoStart = snapshot.offset(
            of: TextPoint(line: 1, column: 0),
            encoding: .utf8
        )
        let bravoEnd = snapshot.offset(
            of: TextPoint(line: 1, column: 5),
            encoding: .utf8
        )

        let result = document.apply(
            EditTransaction(
                edits: [
                    TextEdit(
                        range: TextByteRange(bravoStart, bravoEnd),
                        replacement: "beta"
                    )
                ],
                selectionIntent: .collapseToInsertionEnd
            )
        )
        let updated = document.snapshot()

        #expect(result.oldVersion == DocumentVersion(0))
        #expect(result.newVersion == DocumentVersion(1))
        #expect(result.invalidatedRange == SourceLineRange(1, 2))
        #expect(updated.version == DocumentVersion(1))
        #expect(updated.characterCount == "alpha\nbeta".count)
        #expect(updated.lineCount == 2)
        #expect(updated.line(0).text == "alpha")
        #expect(updated.line(1).text == "beta")
    }

    @Test
    func applyUsesOriginalSnapshotOffsetsForMultipleEdits() {
        let document = TextDocument(content: "abc\ndef\nghi")
        let snapshot = document.snapshot()

        let defStart = snapshot.offset(
            of: TextPoint(line: 1, column: 0),
            encoding: .utf8
        )
        let defEnd = snapshot.offset(
            of: TextPoint(line: 1, column: 3),
            encoding: .utf8
        )
        let endOffset = snapshot.utf8Length

        let result = document.apply(
            EditTransaction(
                edits: [
                    TextEdit(range: TextByteRange(defStart, defEnd), replacement: "delta"),
                    TextEdit(range: TextByteRange(endOffset, endOffset), replacement: "!")
                ]
            )
        )
        let updated = document.snapshot()

        #expect(result.newVersion == DocumentVersion(1))
        #expect(result.invalidatedRange == SourceLineRange(1, 3))
        #expect(updated.lineCount == 3)
        #expect(updated.line(0).text == "abc")
        #expect(updated.line(1).text == "delta")
        #expect(updated.line(2).text == "ghi!")
    }

    @Test
    func earlierSnapshotsRemainStableAfterLaterEdits() {
        let document = TextDocument(content: "first\nsecond")
        let original = document.snapshot()

        let insertionPoint = original.offset(
            of: TextPoint(line: 0, column: 5),
            encoding: .utf8
        )
        _ = document.apply(
            EditTransaction(
                edits: [
                    TextEdit(
                        range: TextByteRange(insertionPoint, insertionPoint),
                        replacement: "!"
                    )
                ]
            )
        )

        let updated = document.snapshot()

        #expect(original.version == DocumentVersion(0))
        #expect(original.line(0).text == "first")
        #expect(original.line(1).text == "second")
        #expect(updated.version == DocumentVersion(1))
        #expect(updated.line(0).text == "first!")
        #expect(updated.line(1).text == "second")
    }
}
