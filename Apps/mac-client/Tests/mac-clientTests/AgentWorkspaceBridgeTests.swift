import ACPClientKit
import AppFeatures
import Editor
import Foundation
import Git
import Testing
import Workspace
@testable import mac_client

@Suite("Agent Workspace Bridge Tests")
struct AgentWorkspaceBridgeTests {
    @Test("File attachments embed text resources when embedded context is supported")
    @MainActor
    func embeddedFileAttachmentPromptBlock() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("Sources/Feature.swift")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "struct Feature {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let bridge = makeBridge(workspaceURL: workspaceURL)
        let blocks = try await bridge.promptBlocks(
            draft: "Review this file",
            attachments: [.file(url: fileURL)],
            capabilities: ACPPromptCapabilities(embeddedContext: true)
        )

        #expect(blocks.count == 2)
        guard case .resource(let resource) = blocks[1] else {
            Issue.record("Expected an embedded resource block")
            return
        }

        #expect(resource.resource.uri == fileURL.absoluteString)
        #expect(resource.resource.text == "struct Feature {}")
    }

    @Test("Image attachments become ACP image blocks when the agent supports image prompts")
    @MainActor
    func imageAttachmentPromptBlock() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let imageURL = workspaceURL.appendingPathComponent("diagram.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)

        let bridge = makeBridge(workspaceURL: workspaceURL)
        let blocks = try await bridge.promptBlocks(
            draft: "",
            attachments: [.image(url: imageURL)],
            capabilities: ACPPromptCapabilities(image: true)
        )

        #expect(blocks.count == 1)
        guard case .image(let image) = blocks[0] else {
            Issue.record("Expected an image block")
            return
        }

        #expect(image.mimeType == "image/png")
        #expect(image.data != nil)
    }

    @Test("Filesystem reads prefer unsaved editor content")
    @MainActor
    func dirtyBufferReadUsesEditorTruth() throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("notes.txt")
        try "disk".write(to: fileURL, atomically: true, encoding: .utf8)

        let pool = EditorSessionPool()
        let session = pool.acquire(url: fileURL)
        session.cancelLoading()
        let document = EditorDocument(content: "dirty buffer", language: "plaintext")
        document.fileURL = fileURL
        document.isDirty = true
        session.document = document
        session.phase = .loaded(document)

        let bridge = makeBridge(workspaceURL: workspaceURL, editorSessionPool: pool)
        let content = try bridge.readTextFile(path: fileURL.path)

        #expect(content == "dirty buffer")
    }

    @Test("Relative filesystem paths resolve from the workspace root")
    @MainActor
    func relativePathsResolveFromWorkspaceRoot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("Sources/Notes.txt")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "workspace scoped".write(to: fileURL, atomically: true, encoding: .utf8)

        let bridge = makeBridge(workspaceURL: workspaceURL)
        let content = try bridge.readTextFile(path: "Sources/Notes.txt")

        #expect(content == "workspace scoped")

        try await bridge.writeTextFile(path: "Sources/NewFile.txt", content: "created relatively")
        #expect(
            try String(
                contentsOf: workspaceURL.appendingPathComponent("Sources/NewFile.txt"),
                encoding: .utf8
            ) == "created relatively"
        )
    }

    @Test("Filesystem writes update disk and open editor sessions")
    @MainActor
    func writeOpenFileReconcilesEditorState() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("README.md")
        try "before".write(to: fileURL, atomically: true, encoding: .utf8)

        let pool = EditorSessionPool()
        let session = pool.acquire(url: fileURL)
        session.cancelLoading()
        let document = EditorDocument(content: "before", language: "markdown")
        document.fileURL = fileURL
        document.isDirty = true
        session.document = document
        session.phase = .loaded(document)

        let bridge = makeBridge(workspaceURL: workspaceURL, editorSessionPool: pool)
        try await bridge.writeTextFile(path: fileURL.path, content: "after")

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "after")
        #expect(session.document?.content == "after")
        #expect(session.isDirty == false)
    }

    @Test("Filesystem writes succeed for unopened files")
    @MainActor
    func writeUnopenedFileSucceeds() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("new.txt")
        let bridge = makeBridge(workspaceURL: workspaceURL)

        try await bridge.writeTextFile(path: fileURL.path, content: "created")

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "created")
    }

    @Test("Inline terminals retain output after release")
    @MainActor
    func inlineTerminalLifecycleRetainsOutput() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let bridge = makeBridge(workspaceURL: workspaceURL)
        let sessionID = ChatSessionID(rawValue: "sess-test")

        let created = try await bridge.createInlineTerminal(
            request: AgentCreateTerminalRequest(
                sessionId: sessionID,
                command: "sh",
                args: ["-lc", "printf 'hello from terminal'"],
                cwd: workspaceURL.path
            )
        )

        let exited = try await bridge.waitForTerminalExit(
            request: AgentWaitForTerminalExitRequest(
                sessionId: sessionID,
                terminalId: created.terminalId
            )
        )
        #expect(exited.exitCode == 0)

        let output = try await bridge.terminalOutput(
            request: AgentTerminalOutputRequest(
                sessionId: sessionID,
                terminalId: created.terminalId
            )
        )
        #expect(output.output.contains("hello from terminal"))

        try await bridge.releaseTerminal(
            request: AgentReleaseTerminalRequest(
                sessionId: sessionID,
                terminalId: created.terminalId
            )
        )

        let retained = await bridge.inlineTerminalSnapshot(id: created.terminalId)
        #expect(retained?.isRunning == false)
        #expect(retained?.output.contains("hello from terminal") == true)
    }

    @Test("Promoting a running inline terminal reuses the hosted session")
    @MainActor
    func promoteInlineTerminalReusesHostedSession() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let registry = WorkspaceTerminalRegistry()
        let bridge = makeBridge(
            workspaceURL: workspaceURL,
            workspaceTerminalRegistry: registry
        )
        let sessionID = ChatSessionID(rawValue: "sess-promote")

        let created = try await bridge.createInlineTerminal(
            request: AgentCreateTerminalRequest(
                sessionId: sessionID,
                command: "sh",
                args: ["-lc", "printf 'ready'; sleep 1"],
                cwd: workspaceURL.path
            )
        )

        await waitUntil("inline terminal output") {
            await bridge.inlineTerminalSnapshot(id: created.terminalId)?.output.contains("ready") == true
        }

        let promotedID = try await bridge.promoteInlineTerminal(id: created.terminalId)
        let hostedSessionID = try #require(UUID(uuidString: created.terminalId))
        let terminalSession = registry.session(id: promotedID, in: workspaceURL.path)

        #expect(promotedID == hostedSessionID)
        #expect(terminalSession?.requestedCommand?.isEmpty == false)
        #expect(terminalSession?.terminateHostedSessionOnClose == false)
    }

    @Test("Relative terminal working directories resolve from the workspace root")
    @MainActor
    func relativeTerminalWorkingDirectoryResolvesFromWorkspaceRoot() async throws {
        let workspaceURL = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let scriptsURL = workspaceURL.appendingPathComponent("Scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)

        let bridge = makeBridge(workspaceURL: workspaceURL)
        let sessionID = ChatSessionID(rawValue: "sess-relative-cwd")
        let created = try await bridge.createInlineTerminal(
            request: AgentCreateTerminalRequest(
                sessionId: sessionID,
                command: "sh",
                args: ["-lc", "pwd"],
                cwd: "Scripts"
            )
        )

        _ = try await bridge.waitForTerminalExit(
            request: AgentWaitForTerminalExitRequest(
                sessionId: sessionID,
                terminalId: created.terminalId
            )
        )
        let output = try await bridge.terminalOutput(
            request: AgentTerminalOutputRequest(
                sessionId: sessionID,
                terminalId: created.terminalId
            )
        )

        #expect(output.output.contains(scriptsURL.path))
    }

    @MainActor
    private func makeBridge(
        workspaceURL: URL,
        editorSessionPool: EditorSessionPool = EditorSessionPool(),
        workspaceTerminalRegistry: WorkspaceTerminalRegistry = WorkspaceTerminalRegistry()
    ) -> AgentWorkspaceBridge {
        let gitStoreProvider: @MainActor @Sendable () -> GitStore? = { nil }
        let terminalHostController = PersistentTerminalHostController(
            socketPath: makeTestSocketPath(),
            executablePathProvider: testExecutablePath
        )
        return AgentWorkspaceBridge(
            workspaceID: workspaceURL.path,
            workingDirectoryURL: workspaceURL,
            editorSessionPool: editorSessionPool,
            workspaceTerminalRegistry: workspaceTerminalRegistry,
            persistentTerminalHostController: terminalHostController,
            gitStoreProvider: gitStoreProvider
        )
    }

    private func makeTemporaryWorkspace() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = root.appendingPathComponent("devys-agent-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for \(description)")
    }

    private func makeTestSocketPath() -> String {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let suffix = UUID().uuidString.prefix(8)
        return root
            .appendingPathComponent("devys-th-\(suffix).sock", isDirectory: false)
            .path
    }
}

private func testExecutablePath() -> String? {
    let bundles = [Bundle.main] + Bundle.allBundles
    for bundle in bundles {
        if let executablePath = bundle.executableURL?.path,
           FileManager.default.isExecutableFile(atPath: executablePath),
           executablePath.hasSuffix("/Devys") {
            return executablePath
        }
    }

    let environment = ProcessInfo.processInfo.environment
    if let testHost = environment["TEST_HOST"],
       FileManager.default.isExecutableFile(atPath: testHost) {
        return testHost
    }

    if let builtProductsDirectory = environment["BUILT_PRODUCTS_DIR"] {
        let candidate = URL(fileURLWithPath: builtProductsDirectory, isDirectory: true)
            .appendingPathComponent("Devys.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("Devys", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }
    }

    return nil
}
