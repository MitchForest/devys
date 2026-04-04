import Foundation
import Testing
import Editor
@testable import mac_client

private actor LoadCounter {
    private var count = 0

    func recordCall() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

@Suite("EditorSession Tests")
struct EditorSessionTests {
    @Test("Canonical session pool reuses one live session per file path until the final release")
    @MainActor
    func canonicalSessionPoolReusesSingleLiveSession() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let url = tempDirectory.appendingPathComponent("Shared.swift")
        try "let shared = true\n".write(to: url, atomically: true, encoding: .utf8)

        let pool = EditorSessionPool()
        let firstSession = pool.acquire(url: url)
        let secondSession = pool.acquire(url: url)

        #expect(firstSession === secondSession)
        #expect(pool.sessionsByURL.count == 1)

        try await Task.sleep(for: .milliseconds(200))

        #expect(firstSession.document?.content == "let shared = true\n")

        pool.release(url: url)
        #expect(pool.session(for: url) === firstSession)

        pool.release(url: url)
        #expect(pool.session(for: url) == nil)
        #expect(pool.sessionsByURL.isEmpty)
    }

    @Test("Publishes preview text before the full document finishes loading")
    @MainActor
    func publishesPreviewBeforeFullDocumentLoad() async throws {
        let url = URL(fileURLWithPath: "/tmp/Preview.swift")
        let session = EditorSession(
            url: url,
            previewLoader: { _ in
                try await Task.sleep(for: .milliseconds(20))
                return EditorSessionPreview(
                    content: "let preview = true",
                    language: "swift"
                )
            },
            documentBuilder: { _, preview in
                try await Task.sleep(for: .milliseconds(120))
                return try await EditorDocument.prepareTextDocument(content: preview.content)
            }
        )

        session.open(url)

        try await Task.sleep(for: .milliseconds(60))

        #expect(session.preview?.content == "let preview = true")
        #expect(session.document?.content == "let preview = true")
        #expect(session.isLoading)

        let previewDocument = session.document

        try await Task.sleep(for: .milliseconds(140))

        #expect(session.document?.content == "let preview = true")
        #expect(session.isLoading == false)
        #expect(session.document === previewDocument)
    }

    @Test("Does not start duplicate loads for the same URL while already loading")
    @MainActor
    func avoidsDuplicateLoadsForSameURL() async throws {
        let url = URL(fileURLWithPath: "/tmp/Notes.swift")
        let counter = LoadCounter()
        let session = EditorSession(url: url) { _ in
            await counter.recordCall()
            try await Task.sleep(for: .milliseconds(50))
            return await MainActor.run {
                EditorDocument(content: "let value = 1")
            }
        }

        session.open(url)
        session.open(url)

        try await Task.sleep(for: .milliseconds(120))

        #expect(await counter.value() == 1)
        #expect(session.document?.content == "let value = 1")
    }

    @Test("Ignores stale completions after retargeting a tab to another file")
    @MainActor
    func ignoresStaleLoadCompletion() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/First.swift")
        let secondURL = URL(fileURLWithPath: "/tmp/Second.swift")

        let session = EditorSession(url: firstURL) { url in
            if url == firstURL {
                try await Task.sleep(for: .milliseconds(120))
                return await MainActor.run {
                    EditorDocument(content: "let file = \"first\"")
                }
            }

            try await Task.sleep(for: .milliseconds(20))
            return await MainActor.run {
                EditorDocument(content: "let file = \"second\"")
            }
        }

        session.open(firstURL)
        session.open(secondURL)

        try await Task.sleep(for: .milliseconds(200))

        #expect(session.url == secondURL)
        #expect(session.document?.content == "let file = \"second\"")
    }

    @Test("Ignores stale preview and final completions after retargeting")
    @MainActor
    func ignoresStalePreviewAndFinalCompletion() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/FirstPreview.swift")
        let secondURL = URL(fileURLWithPath: "/tmp/SecondPreview.swift")

        let session = EditorSession(
            url: firstURL,
            previewLoader: { url in
                if url == firstURL {
                    try await Task.sleep(for: .milliseconds(80))
                    return EditorSessionPreview(
                        content: "let file = \"first-preview\"",
                        language: "swift"
                    )
                }

                try await Task.sleep(for: .milliseconds(10))
                return EditorSessionPreview(
                    content: "let file = \"second-preview\"",
                    language: "swift"
                )
            },
            documentBuilder: { url, preview in
                if url == firstURL {
                    try await Task.sleep(for: .milliseconds(120))
                } else {
                    try await Task.sleep(for: .milliseconds(20))
                }
                return try await EditorDocument.prepareTextDocument(content: preview.content)
            }
        )

        session.open(firstURL)
        session.open(secondURL)

        try await Task.sleep(for: .milliseconds(15))

        #expect(session.preview?.content == "let file = \"second-preview\"")
        #expect(session.url == secondURL)

        try await Task.sleep(for: .milliseconds(200))

        #expect(session.url == secondURL)
        #expect(session.document?.content == "let file = \"second-preview\"")
    }
}
