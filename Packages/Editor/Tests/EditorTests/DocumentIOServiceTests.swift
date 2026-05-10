import Foundation
import Testing
@testable import Editor

@Suite("Document IO Service Tests")
struct DocumentIOServiceTests {
    @Test("Bounded preview returns text and revision metadata for small UTF-8 files")
    func boundedPreviewReturnsTextAndRevision() async throws {
        let fixture = try TestDocumentIOFixture()
        defer { fixture.cleanup() }

        let url = fixture.directory.appendingPathComponent("Small.swift")
        try "let value = 1\n".write(to: url, atomically: true, encoding: .utf8)

        let preview = try await DefaultDocumentIOService().loadPreview(
            url: url,
            request: DocumentPreviewRequest(maxBytes: 1024)
        )

        #expect(preview.content == "let value = 1\n")
        #expect(preview.language == "swift")
        #expect(preview.isEligibleForFullLoad)
        #expect(preview.revision.fileSize == 14)
    }

    @Test("Bounded preview marks oversized files without decoding the whole document")
    func boundedPreviewDetectsTooLargeFiles() async throws {
        let fixture = try TestDocumentIOFixture()
        defer { fixture.cleanup() }

        let url = fixture.directory.appendingPathComponent("Large.swift")
        let content = String(repeating: "abcdefghij", count: 500)
        try content.write(to: url, atomically: true, encoding: .utf8)

        let preview = try await DefaultDocumentIOService().loadPreview(
            url: url,
            request: DocumentPreviewRequest(maxBytes: 1024)
        )

        #expect(preview.isTooLarge)
        #expect(preview.content == nil)
        #expect(preview.exceededLimit)
        #expect(preview.isEligibleForFullLoad == false)
        #expect((preview.revision.fileSize ?? 0) > 1024)
    }

    @Test("Bounded preview detects binary files")
    func boundedPreviewDetectsBinaryFiles() async throws {
        let fixture = try TestDocumentIOFixture()
        defer { fixture.cleanup() }

        let url = fixture.directory.appendingPathComponent("Image.bin")
        try Data([0x00, 0xFF, 0x10, 0x41]).write(to: url)

        let preview = try await DefaultDocumentIOService().loadPreview(
            url: url,
            request: DocumentPreviewRequest(maxBytes: 1024)
        )

        #expect(preview.isBinary)
        #expect(preview.content == nil)
        #expect(preview.isEligibleForFullLoad == false)
    }
}

private struct TestDocumentIOFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-document-io-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
