import Foundation
import Testing
import Editor
@testable import mac_client

// swiftlint:disable type_body_length

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

        #expect(
            await waitUntil {
                firstSession.document?.content == "let shared = true\n"
            }
        )

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
                return try await EditorDocument.prepareTextDocument(content: preview.content ?? "")
            }
        )

        session.open(url)

        #expect(
            await waitUntil {
                session.preview?.content == "let preview = true" &&
                    session.document?.content == "let preview = true" &&
                    session.isLoading
            }
        )

        let previewDocument = session.document

        #expect(
            await waitUntil {
                session.document?.content == "let preview = true" &&
                    session.isLoading == false
            }
        )
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
                    try await Task.sleep(for: .milliseconds(80))
                }
                return try await EditorDocument.prepareTextDocument(content: preview.content ?? "")
            }
        )

        session.open(firstURL)
        session.open(secondURL)

        #expect(
            await waitUntil(interval: .milliseconds(5)) {
                session.preview?.content == "let file = \"second-preview\"" &&
                    session.url == secondURL
            }
        )

        try await Task.sleep(for: .milliseconds(200))

        #expect(session.url == secondURL)
        #expect(session.document?.content == "let file = \"second-preview\"")
    }

    @Test("Too-large preview short-circuits before full document build")
    @MainActor
    func shortCircuitsTooLargePreview() async throws {
        let url = URL(fileURLWithPath: "/tmp/LargePreview.swift")
        let builderCalls = LoadCounter()
        let session = EditorSession(
            url: url,
            previewLoader: { _ in
                EditorSessionPreview(
                    kind: .tooLarge,
                    language: "swift",
                    revision: DocumentPreviewRevision(
                        fileSize: 8_192,
                        contentModificationDate: nil
                    ),
                    exceededLimit: true,
                    maxBytes: 1_024
                )
            },
            documentBuilder: { _, _ in
                await builderCalls.recordCall()
                return try await EditorDocument.prepareTextDocument(content: "should not load")
            }
        )

        session.open(url)

        try await Task.sleep(for: .milliseconds(40))

        #expect(session.preview?.isTooLarge == true)
        #expect(session.document == nil)
        #expect(session.isLoading == false)
        #expect(await builderCalls.value() == 0)
    }

    @Test("Reopening the same file only reloads when its revision changes")
    @MainActor
    func reloadsOnlyWhenRevisionChanges() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let url = tempDirectory.appendingPathComponent("Tracked.swift")
        try "let value = 1\n".write(to: url, atomically: true, encoding: .utf8)

        let previewCalls = LoadCounter()
        let builderCalls = LoadCounter()
        let session = EditorSession(
            url: url,
            previewLoader: { url in
                await previewCalls.recordCall()
                let content = try String(contentsOf: url, encoding: .utf8)
                return EditorSessionPreview(
                    kind: .text(content),
                    language: "swift",
                    revision: try DocumentPreviewRevision.current(for: url),
                    exceededLimit: false,
                    maxBytes: DocumentPreviewRequest.default.maxBytes
                )
            },
            documentBuilder: { _, preview in
                await builderCalls.recordCall()
                return try await EditorDocument.prepareTextDocument(content: preview.content ?? "")
            }
        )

        session.open(url)

        #expect(
            await waitUntil {
                session.document?.content == "let value = 1\n" &&
                    session.isLoading == false
            }
        )
        #expect(await previewCalls.value() == 1)
        #expect(await builderCalls.value() == 1)

        session.open(url)

        try await Task.sleep(for: .milliseconds(50))

        #expect(await previewCalls.value() == 1)
        #expect(await builderCalls.value() == 1)

        try await Task.sleep(for: .milliseconds(20))
        try "let value = 22\n".write(to: url, atomically: true, encoding: .utf8)

        session.open(url)

        #expect(
            await waitUntil {
                session.document?.content == "let value = 22\n" &&
                    session.isLoading == false
            }
        )
        #expect(await previewCalls.value() == 2)
        #expect(await builderCalls.value() == 2)
    }

    @Test("Present find seeds from the current selection and selects the first match")
    @MainActor
    func presentFindSeedsFromSelectionAndSelectsFirstMatch() async throws {
        let url = URL(fileURLWithPath: "/tmp/FindSeed.swift")
        let session = EditorSession(url: url) { _ in
            await MainActor.run {
                EditorDocument(content: "let value = value\n")
            }
        }

        session.open(url)

        #expect(
            await waitUntil {
                session.document?.content == "let value = value\n"
            }
        )

        session.document?.applyNavigationTarget(
            .match(EditorSearchMatch(startLine: 0, startColumn: 4, endLine: 0, endColumn: 9))
        )

        session.presentFind()

        #expect(session.isFindPresented)
        #expect(session.findQuery == "value")
        #expect(session.findMatches.count == 2)
        #expect(session.activeFindMatchIndex == 0)
        #expect(session.navigationTarget == .match(session.findMatches[0]))
        #expect(session.navigationRequestID > 0)
    }

    @Test("Pending navigation is preserved until the document is available")
    @MainActor
    func pendingNavigationAppliesWhenDocumentLoads() async throws {
        let url = URL(fileURLWithPath: "/tmp/PendingNavigation.swift")
        let session = EditorSession(
            url: url,
            previewLoader: { _ in
                EditorSessionPreview(content: "alpha beta gamma", language: "swift")
            },
            documentBuilder: { _, preview in
                try await Task.sleep(for: .milliseconds(40))
                return try await EditorDocument.prepareTextDocument(content: preview.content ?? "")
            }
        )

        let targetMatch = EditorSearchMatch(
            startLine: 0,
            startColumn: 6,
            endLine: 0,
            endColumn: 10
        )
        session.navigate(to: .match(targetMatch), focusEditor: false)
        session.open(url)

        #expect(
            await waitUntil {
                session.document?.selectedText == "beta" &&
                    session.navigationTarget == .match(targetMatch)
            }
        )
    }

    @Test("Dismiss find clears match state and refocuses the editor")
    @MainActor
    func dismissFindClearsMatchStateAndRequestsFocus() async throws {
        let url = URL(fileURLWithPath: "/tmp/DismissFind.swift")
        let session = EditorSession(url: url) { _ in
            await MainActor.run {
                EditorDocument(content: "let value = value\n")
            }
        }

        session.open(url)

        #expect(
            await waitUntil {
                session.document?.content == "let value = value\n"
            }
        )

        session.document?.applyNavigationTarget(
            .match(EditorSearchMatch(startLine: 0, startColumn: 4, endLine: 0, endColumn: 9))
        )
        session.presentFind()

        let focusRequestID = session.focusRequestID
        session.dismissFind()

        #expect(session.isFindPresented == false)
        #expect(session.findMatches.isEmpty)
        #expect(session.activeFindMatchIndex == nil)
        #expect(session.focusRequestID == focusRequestID + 1)
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    interval: Duration = .milliseconds(20),
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while clock.now < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: interval)
    }

    return condition()
}

// swiftlint:enable type_body_length
