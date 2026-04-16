// swiftlint:disable file_length
import ACPClientKit
import AppFeatures
import Editor
import Foundation
import GhosttyTerminal
import Git
import UniformTypeIdentifiers
import Workspace

struct AgentAttachmentSummary: Equatable, Sendable, Identifiable {
    enum Delivery: String, Equatable, Sendable {
        case embedded
        case linked
        case image
    }

    let attachment: AgentAttachment
    let title: String
    let subtitle: String?
    let systemImage: String
    let delivery: Delivery

    var id: String {
        attachment.id
    }
}

struct AgentMentionSuggestion: Equatable, Sendable, Identifiable {
    let url: URL
    let displayPath: String

    var id: String {
        url.absoluteString
    }
}

struct AgentInlineTerminalViewState: Equatable, Sendable, Identifiable {
    let terminalID: String
    let hostedSessionID: UUID
    let command: String
    let workingDirectoryURL: URL
    let logFileURL: URL
    var output: String
    var truncated: Bool
    var isRunning: Bool
    var exitCode: Int?
    var signal: String?

    var id: String {
        terminalID
    }
}

enum AgentWorkspaceBridgeError: LocalizedError, Equatable {
    case unavailable(String)
    case invalidPath(String)
    case outsideWorkspace(URL)
    case nonTextFile(URL)
    case terminalNotFound(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .invalidPath(let message):
            message
        case .outsideWorkspace(let url):
            "Path is outside the active workspace: \(url.path)"
        case .nonTextFile(let url):
            "The file is not readable as text: \(url.lastPathComponent)"
        case .terminalNotFound(let terminalID):
            "Inline terminal not found: \(terminalID)"
        }
    }
}

@MainActor
// swiftlint:disable:next type_body_length
final class AgentWorkspaceBridge {
    private struct ResolvedAttachmentPayload {
        let block: AgentContentBlock
        let summary: AgentAttachmentSummary
    }

    let workspaceID: Workspace.ID
    let workingDirectoryURL: URL

    private let editorSessionPool: EditorSessionPool
    private let workspaceTerminalRegistry: WorkspaceTerminalRegistry
    private let persistentTerminalHostController: PersistentTerminalHostController
    private let gitStoreProvider: @MainActor @Sendable () -> GitStore?
    private let terminalStore = AgentInlineTerminalStore()
    private let mentionIndex = AgentMentionIndex()

    var inlineTerminalUpdateHandler: (@MainActor (AgentInlineTerminalViewState) -> Void)?

    init(
        workspaceID: Workspace.ID,
        workingDirectoryURL: URL,
        editorSessionPool: EditorSessionPool,
        workspaceTerminalRegistry: WorkspaceTerminalRegistry,
        persistentTerminalHostController: PersistentTerminalHostController,
        gitStoreProvider: @escaping @MainActor @Sendable () -> GitStore?
    ) {
        self.workspaceID = workspaceID
        self.workingDirectoryURL = workingDirectoryURL.standardizedFileURL
        self.editorSessionPool = editorSessionPool
        self.workspaceTerminalRegistry = workspaceTerminalRegistry
        self.persistentTerminalHostController = persistentTerminalHostController
        self.gitStoreProvider = gitStoreProvider
    }

    func attachmentSummaries(
        for attachments: [AgentAttachment],
        capabilities: ACPPromptCapabilities
    ) async -> [AgentAttachmentSummary] {
        var summaries: [AgentAttachmentSummary] = []
        for attachment in attachments {
            if let summary = try? await resolvedAttachmentPayload(
                for: attachment,
                capabilities: capabilities
            ).summary {
                summaries.append(summary)
            }
        }
        return summaries
    }

    func mentionSuggestions(
        matching query: String,
        limit: Int = 12
    ) async -> [AgentMentionSuggestion] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        return await mentionIndex.suggestions(
            matching: normalizedQuery,
            limit: limit,
            rootURL: workingDirectoryURL
        )
    }

    func promptBlocks(
        draft: String,
        attachments: [AgentAttachment],
        capabilities: ACPPromptCapabilities
    ) async throws -> [AgentContentBlock] {
        var blocks: [AgentContentBlock] = []
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDraft.isEmpty {
            blocks.append(.text(AgentTextContent(text: trimmedDraft)))
        }

        for attachment in attachments {
            let payload = try await resolvedAttachmentPayload(for: attachment, capabilities: capabilities)
            blocks.append(payload.block)
        }

        return blocks
    }

    func readTextFile(
        path: String,
        line: Int? = nil,
        limit: Int? = nil
    ) throws -> String {
        let url = try validatedWorkspaceURL(path: path)
        let content: String
        if let session = editorSessionPool.session(for: url),
           let document = session.document {
            content = document.content
        } else {
            do {
                content = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw AgentWorkspaceBridgeError.nonTextFile(url)
            }
        }

        return slicedText(content, line: line, limit: limit)
    }

    func writeTextFile(
        path: String,
        content: String
    ) async throws {
        let url = try validatedWorkspaceURL(path: path)
        let parentDirectory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)

        if let session = editorSessionPool.session(for: url) {
            try await session.replaceDocumentContent(
                with: content,
                fileURL: url,
                markDirty: false
            )
        }

        await mentionIndex.invalidate(rootURL: workingDirectoryURL)
    }

    func createInlineTerminal(
        request: AgentCreateTerminalRequest
    ) async throws -> AgentCreateTerminalResponse {
        let cwdURL = try validatedOptionalWorkspaceURL(path: request.cwd)
        let terminal = try await terminalStore.create(
            workspaceID: workspaceID,
            request: request,
            defaultWorkingDirectoryURL: cwdURL ?? workingDirectoryURL,
            terminalHostController: persistentTerminalHostController
        ) { [weak self] snapshot in
            guard let self else { return }
            self.deliverInlineTerminal(snapshot)
        }
        return AgentCreateTerminalResponse(terminalId: terminal.terminalID)
    }

    func inlineTerminalSnapshot(id: String) async -> AgentInlineTerminalViewState? {
        await terminalStore.snapshot(id: id)
    }

    func terminalOutput(
        request: AgentTerminalOutputRequest
    ) async throws -> AgentTerminalOutputResponse {
        let snapshot = try await currentTerminalSnapshot(id: request.terminalId)
        let exitStatus = snapshot.exitCode == nil && snapshot.signal == nil
            ? nil
            : AgentTerminalExitStatus(
                exitCode: snapshot.exitCode,
                signal: snapshot.signal
            )
        return AgentTerminalOutputResponse(
            output: snapshot.output,
            truncated: snapshot.truncated,
            exitStatus: exitStatus
        )
    }

    func waitForTerminalExit(
        request: AgentWaitForTerminalExitRequest
    ) async throws -> AgentWaitForTerminalExitResponse {
        let exitStatus = try await terminalStore.waitForExit(id: request.terminalId)
        return AgentWaitForTerminalExitResponse(
            exitCode: exitStatus.exitCode,
            signal: exitStatus.signal
        )
    }

    func killTerminal(
        request: AgentKillTerminalRequest
    ) async throws {
        try await terminalStore.kill(
            id: request.terminalId,
            terminalHostController: persistentTerminalHostController
        )
    }

    func releaseTerminal(
        request: AgentReleaseTerminalRequest
    ) async throws {
        try await terminalStore.release(
            id: request.terminalId,
            terminalHostController: persistentTerminalHostController
        )
    }

    func promoteInlineTerminal(id: String) async throws -> UUID {
        let snapshot = try await currentTerminalSnapshot(id: id)
        if snapshot.isRunning {
            if let existing = workspaceTerminalRegistry.session(id: snapshot.hostedSessionID, in: workspaceID) {
                return existing.id
            }

            let attachCommand = await persistentTerminalHostController.attachCommand(
                for: snapshot.hostedSessionID
            )
            let session = workspaceTerminalRegistry.createSession(
                in: workspaceID,
                workingDirectory: snapshot.workingDirectoryURL,
                requestedCommand: snapshot.command,
                attachCommand: attachCommand,
                terminateHostedSessionOnClose: false,
                id: snapshot.hostedSessionID
            )
            session.tabTitle = snapshot.command
            return session.id
        }

        let command = "cat \(shellQuoted(snapshot.logFileURL.path))"
        let session = workspaceTerminalRegistry.createSession(
            in: workspaceID,
            workingDirectory: snapshot.workingDirectoryURL,
            requestedCommand: command
        )
        session.tabTitle = snapshot.command
        return session.id
    }

    private func currentTerminalSnapshot(id: String) async throws -> AgentInlineTerminalViewState {
        guard let snapshot = await terminalStore.snapshot(id: id) else {
            throw AgentWorkspaceBridgeError.terminalNotFound(id)
        }
        return snapshot
    }

    private func deliverInlineTerminal(_ snapshot: AgentInlineTerminalViewState) {
        inlineTerminalUpdateHandler?(snapshot)
    }

    private func resolvedAttachmentPayload(
        for attachment: AgentAttachment,
        capabilities: ACPPromptCapabilities
    ) async throws -> ResolvedAttachmentPayload {
        switch attachment {
        case .file(let url):
            return try await resolvedFileAttachment(url: url, capabilities: capabilities)
        case .gitDiff(let path, let isStaged):
            return try await resolvedGitDiffAttachment(
                path: path,
                isStaged: isStaged,
                capabilities: capabilities
            )
        case .image(let url):
            return try await resolvedImageAttachment(url: url, capabilities: capabilities)
        case .url(let url):
            let summary = AgentAttachmentSummary(
                attachment: attachment,
                title: url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent,
                subtitle: url.host,
                systemImage: "link",
                delivery: .linked
            )
            let block = AgentContentBlock.resourceLink(
                AgentResourceLink(
                    name: url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent,
                    title: url.host,
                    uri: url.absoluteString,
                    mimeType: nil
                )
            )
            return ResolvedAttachmentPayload(block: block, summary: summary)
        case .snippet(let language, let content):
            let resource = AgentEmbeddedResource.Resource(
                uri: "devys://snippet/\(UUID().uuidString)",
                text: content,
                blob: nil,
                mimeType: language.flatMap { "text/\($0)" } ?? "text/plain"
            )
            let summary = AgentAttachmentSummary(
                attachment: attachment,
                title: "Snippet",
                subtitle: language ?? "plain text",
                systemImage: "chevron.left.forwardslash.chevron.right",
                delivery: .embedded
            )
            return ResolvedAttachmentPayload(
                block: .resource(AgentEmbeddedResource(resource: resource)),
                summary: summary
            )
        }
    }

    private func resolvedFileAttachment(
        url: URL,
        capabilities: ACPPromptCapabilities
    ) async throws -> ResolvedAttachmentPayload {
        let normalizedURL = url.standardizedFileURL
        let attachment = AgentAttachment.file(url: normalizedURL)
        let mimeType = mimeType(for: normalizedURL)

        if let imageUTType = UTType(mimeType: mimeType),
           imageUTType.conforms(to: .image) {
            return try await resolvedImageAttachment(
                url: normalizedURL,
                capabilities: capabilities,
                attachment: attachment
            )
        }

        if capabilities.embeddedContext,
           let embedded = try? textResourceBlock(
            url: normalizedURL,
            attachment: attachment,
            mimeType: mimeType
           ) {
            return embedded
        }

        let summary = AgentAttachmentSummary(
            attachment: attachment,
            title: normalizedURL.lastPathComponent,
            subtitle: relativePath(for: normalizedURL),
            systemImage: "doc.text",
            delivery: .linked
        )
        return ResolvedAttachmentPayload(
            block: .resourceLink(
                AgentResourceLink(
                    name: normalizedURL.lastPathComponent,
                    title: relativePath(for: normalizedURL),
                    uri: normalizedURL.absoluteString,
                    mimeType: mimeType
                )
            ),
            summary: summary
        )
    }

    private func resolvedGitDiffAttachment(
        path: String,
        isStaged: Bool,
        capabilities: ACPPromptCapabilities
    ) async throws -> ResolvedAttachmentPayload {
        let attachment = AgentAttachment.gitDiff(path: path, isStaged: isStaged)
        let title = URL(fileURLWithPath: path).lastPathComponent
        guard let gitStore = gitStoreProvider() else {
            throw AgentWorkspaceBridgeError.unavailable("Git diff context is unavailable for this workspace.")
        }

        let diffText = try await gitStore.diffText(for: path, isStaged: isStaged)
        if capabilities.embeddedContext {
            let resource = AgentEmbeddedResource.Resource(
                uri: "devys://git-diff/\(workspaceID)/\(path)",
                text: diffText,
                blob: nil,
                mimeType: "text/x-diff"
            )
            let summary = AgentAttachmentSummary(
                attachment: attachment,
                title: title,
                subtitle: isStaged ? "Staged diff" : "Working tree diff",
                systemImage: "arrow.left.arrow.right",
                delivery: .embedded
            )
            return ResolvedAttachmentPayload(
                block: .resource(AgentEmbeddedResource(resource: resource)),
                summary: summary
            )
        }

        let summary = AgentAttachmentSummary(
            attachment: attachment,
            title: title,
            subtitle: isStaged ? "Linked staged diff" : "Linked working diff",
            systemImage: "arrow.left.arrow.right",
            delivery: .linked
        )
        return ResolvedAttachmentPayload(
            block: .resourceLink(
                AgentResourceLink(
                    name: title,
                    title: isStaged ? "Staged diff" : "Working tree diff",
                    uri: "devys://git-diff/\(workspaceID)/\(path)",
                    mimeType: "text/x-diff"
                )
            ),
            summary: summary
        )
    }

    private func resolvedImageAttachment(
        url: URL,
        capabilities: ACPPromptCapabilities,
        attachment: AgentAttachment? = nil
    ) async throws -> ResolvedAttachmentPayload {
        let normalizedURL = url.standardizedFileURL
        let attachment = attachment ?? .image(url: normalizedURL)
        let mimeType = mimeType(for: normalizedURL)

        if capabilities.image {
            let imageData = try Data(contentsOf: normalizedURL)
            let summary = AgentAttachmentSummary(
                attachment: attachment,
                title: normalizedURL.lastPathComponent,
                subtitle: relativePath(for: normalizedURL),
                systemImage: "photo",
                delivery: .image
            )
            return ResolvedAttachmentPayload(
                block: .image(
                    AgentImageContent(
                        mimeType: mimeType,
                        data: imageData.base64EncodedString()
                    )
                ),
                summary: summary
            )
        }

        let summary = AgentAttachmentSummary(
            attachment: attachment,
            title: normalizedURL.lastPathComponent,
            subtitle: "Image linked as a resource",
            systemImage: "photo",
            delivery: .linked
        )
        return ResolvedAttachmentPayload(
            block: .resourceLink(
                AgentResourceLink(
                    name: normalizedURL.lastPathComponent,
                    title: relativePath(for: normalizedURL),
                    uri: normalizedURL.absoluteString,
                    mimeType: mimeType
                )
            ),
            summary: summary
        )
    }

    private func textResourceBlock(
        url: URL,
        attachment: AgentAttachment,
        mimeType: String
    ) throws -> ResolvedAttachmentPayload {
        let text = try readAttachmentText(from: url)
        let summary = AgentAttachmentSummary(
            attachment: attachment,
            title: url.lastPathComponent,
            subtitle: relativePath(for: url),
            systemImage: "doc.text",
            delivery: .embedded
        )
        let resource = AgentEmbeddedResource.Resource(
            uri: url.absoluteString,
            text: text,
            blob: nil,
            mimeType: mimeType
        )
        return ResolvedAttachmentPayload(
            block: .resource(AgentEmbeddedResource(resource: resource)),
            summary: summary
        )
    }

    private func relativePath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = workingDirectoryURL.path
        if path == rootPath {
            return "."
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return url.lastPathComponent
    }

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return "text/plain"
    }

    private func readAttachmentText(from url: URL) throws -> String {
        let normalizedURL = url.standardizedFileURL
        let rootPrefix = workingDirectoryURL.path + "/"
        if normalizedURL.path == workingDirectoryURL.path
            || normalizedURL.path.hasPrefix(rootPrefix) {
            return try readTextFile(path: normalizedURL.path)
        }

        do {
            return try String(contentsOf: normalizedURL, encoding: .utf8)
        } catch {
            throw AgentWorkspaceBridgeError.nonTextFile(normalizedURL)
        }
    }

    private func slicedText(
        _ content: String,
        line: Int?,
        limit: Int?
    ) -> String {
        guard line != nil || limit != nil else {
            return content
        }

        let startLine = max(1, line ?? 1)
        let lineLimit = max(0, limit ?? Int.max)
        guard lineLimit > 0 else {
            return ""
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let startIndex = max(0, startLine - 1)
        guard startIndex < lines.count else {
            return ""
        }

        let endIndex = min(lines.count, startIndex + lineLimit)
        let slice = lines[startIndex..<endIndex].joined(separator: "\n")
        let includesTrailingNewline = content.hasSuffix("\n") && endIndex == lines.count
        return includesTrailingNewline ? slice + "\n" : slice
    }

    private func validatedWorkspaceURL(path: String) throws -> URL {
        guard !path.isEmpty else {
            throw AgentWorkspaceBridgeError.invalidPath("Missing file path.")
        }
        let url = resolvedWorkspaceURL(path: path)
        guard url.path == workingDirectoryURL.path || url.path.hasPrefix(workingDirectoryURL.path + "/") else {
            throw AgentWorkspaceBridgeError.outsideWorkspace(url)
        }
        return url
    }

    private func validatedOptionalWorkspaceURL(path: String?) throws -> URL? {
        guard let path else { return nil }
        return try validatedWorkspaceURL(path: path)
    }

    private func resolvedWorkspaceURL(path: String) -> URL {
        if NSString(string: path).isAbsolutePath {
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        return URL(fileURLWithPath: path, relativeTo: workingDirectoryURL)
            .standardizedFileURL
    }
}

private struct AgentInlineTerminalExitStatus: Equatable, Sendable {
    var exitCode: Int?
    var signal: String?
}

private actor AgentMentionIndex {
    private struct Entry: Sendable {
        let suggestion: AgentMentionSuggestion
        let haystack: [String]
    }

    private var cachedRootPath: String?
    private var entries: [Entry] = []

    func suggestions(
        matching query: String,
        limit: Int,
        rootURL: URL
    ) -> [AgentMentionSuggestion] {
        let rootPath = rootURL.standardizedFileURL.path
        if cachedRootPath != rootPath {
            cachedRootPath = rootPath
            entries = scan(rootURL)
        }

        return entries.lazy
            .filter { entry in
                entry.haystack.contains { $0.contains(query) }
            }
            .prefix(limit)
            .map(\.suggestion)
    }

    func invalidate(rootURL: URL) {
        let rootPath = rootURL.standardizedFileURL.path
        guard cachedRootPath == rootPath else { return }
        cachedRootPath = nil
        entries = []
    }

    private func scan(_ rootURL: URL) -> [Entry] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [Entry] = []
        let rootPath = rootURL.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                continue
            }

            let normalizedURL = url.standardizedFileURL
            let normalizedPath = normalizedURL.path
            let displayPath: String
            if normalizedPath == rootPath {
                displayPath = "."
            } else if normalizedPath.hasPrefix(rootPrefix) {
                displayPath = String(normalizedPath.dropFirst(rootPrefix.count))
            } else {
                displayPath = normalizedURL.lastPathComponent
            }

            results.append(
                Entry(
                    suggestion: AgentMentionSuggestion(
                        url: normalizedURL,
                        displayPath: displayPath
                    ),
                    haystack: [
                        normalizedURL.lastPathComponent.lowercased(),
                        displayPath.lowercased()
                    ]
                )
            )
        }

        return results.sorted {
            $0.suggestion.displayPath.localizedCaseInsensitiveCompare($1.suggestion.displayPath) == .orderedAscending
        }
    }
}

private actor AgentInlineTerminalStore {
    private final class ManagedTerminal {
        let terminalID: String
        let hostedSessionID: UUID
        let attachHandle: FileHandle
        let workingDirectoryURL: URL
        let logFileURL: URL
        let outputByteLimit: Int?
        let command: String
        var output = ""
        var truncated = false
        var exitStatus = AgentInlineTerminalExitStatus(exitCode: nil, signal: nil)
        var isRunning = true
        var waiters: [CheckedContinuation<AgentInlineTerminalExitStatus, Never>] = []

        init(
            terminalID: String,
            hostedSessionID: UUID,
            attachHandle: FileHandle,
            workingDirectoryURL: URL,
            logFileURL: URL,
            outputByteLimit: Int?,
            command: String
        ) {
            self.terminalID = terminalID
            self.hostedSessionID = hostedSessionID
            self.attachHandle = attachHandle
            self.workingDirectoryURL = workingDirectoryURL
            self.logFileURL = logFileURL
            self.outputByteLimit = outputByteLimit
            self.command = command
        }
    }

    private var terminals: [String: ManagedTerminal] = [:]
    private var retainedSnapshots: [String: AgentInlineTerminalViewState] = [:]

    func create(
        workspaceID: Workspace.ID,
        request: AgentCreateTerminalRequest,
        defaultWorkingDirectoryURL: URL,
        terminalHostController: PersistentTerminalHostController,
        onUpdate: @escaping @MainActor @Sendable (AgentInlineTerminalViewState) -> Void
    ) async throws -> AgentInlineTerminalViewState {
        let workingDirectoryURL = defaultWorkingDirectoryURL.standardizedFileURL
        let displayCommand = ([request.command] + request.args).joined(separator: " ")
        let launchCommand = envWrappedShellCommand(
            ([request.command] + request.args).map(shellQuoted).joined(separator: " "),
            environment: request.env.map { ($0.name, $0.value) }
        )
        try await terminalHostController.ensureRunning()
        let record = try await terminalHostController.createSession(
            workspaceID: workspaceID,
            workingDirectory: workingDirectoryURL,
            launchCommand: launchCommand
        )
        let terminalID = record.id.uuidString
        let attachHandle = try Self.attachHandle(
            sessionID: record.id,
            socketPath: terminalHostController.socketPath
        )

        let logDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("devys-acp-terminals", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logFileURL = logDirectory.appendingPathComponent("\(workspaceID)-\(terminalID).log")
        FileManager.default.createFile(atPath: logFileURL.path, contents: Data())

        let terminal = ManagedTerminal(
            terminalID: terminalID,
            hostedSessionID: record.id,
            attachHandle: attachHandle,
            workingDirectoryURL: workingDirectoryURL,
            logFileURL: logFileURL,
            outputByteLimit: request.outputByteLimit,
            command: displayCommand
        )
        terminals[terminalID] = terminal

        let snapshot = snapshot(for: terminal)
        retainedSnapshots[terminalID] = snapshot
        startAttachLoop(
            for: terminalID,
            handle: attachHandle,
            onUpdate: onUpdate
        )
        await onUpdate(snapshot)
        return snapshot
    }

    func snapshot(id: String) -> AgentInlineTerminalViewState? {
        if let terminal = terminals[id] {
            return snapshot(for: terminal)
        }
        return retainedSnapshots[id]
    }

    func waitForExit(id: String) async throws -> AgentInlineTerminalExitStatus {
        if let terminal = terminals[id], !terminal.isRunning {
            return terminal.exitStatus
        }
        if let snapshot = retainedSnapshots[id], !snapshot.isRunning {
            return AgentInlineTerminalExitStatus(exitCode: snapshot.exitCode, signal: snapshot.signal)
        }
        guard let terminal = terminals[id] else {
            throw AgentWorkspaceBridgeError.terminalNotFound(id)
        }
        return await withCheckedContinuation { continuation in
            terminal.waiters.append(continuation)
        }
    }

    func kill(
        id: String,
        terminalHostController: PersistentTerminalHostController
    ) async throws {
        guard let terminal = terminals[id] else {
            throw AgentWorkspaceBridgeError.terminalNotFound(id)
        }
        guard terminal.isRunning else { return }
        try await terminalHostController.terminateSession(id: terminal.hostedSessionID)
    }

    func release(
        id: String,
        terminalHostController: PersistentTerminalHostController
    ) async throws {
        guard let terminal = terminals[id] else {
            throw AgentWorkspaceBridgeError.terminalNotFound(id)
        }
        if terminal.isRunning {
            try await terminalHostController.terminateSession(id: terminal.hostedSessionID)
            _ = try await waitForExit(id: id)
        }
        try? terminal.attachHandle.close()
        retainedSnapshots[id] = snapshot(for: terminal)
        terminals.removeValue(forKey: id)
    }

    private func startAttachLoop(
        for terminalID: String,
        handle: FileHandle,
        onUpdate: @escaping @MainActor @Sendable (AgentInlineTerminalViewState) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            while true {
                do {
                    let (type, payload) = try TerminalHostSocketIO.readFrame(from: handle)
                    Task { [self, terminalID, type, payload, onUpdate] in
                        await self.processAttachFrame(
                            id: terminalID,
                            type: type,
                            payload: payload,
                            onUpdate: onUpdate
                        )
                    }
                    if type == .close {
                        return
                    }
                } catch {
                    Task { [self, terminalID, onUpdate] in
                        await self.finishUnexpectedly(
                            id: terminalID,
                            onUpdate: onUpdate
                        )
                    }
                    return
                }
            }
        }
    }

    private func processAttachFrame(
        id: String,
        type: TerminalHostStreamFrameType,
        payload: Data,
        onUpdate: @escaping @MainActor @Sendable (AgentInlineTerminalViewState) -> Void
    ) async {
        switch type {
        case .output:
            await appendOutput(
                id: id,
                data: payload,
                onUpdate: onUpdate
            )
        case .close:
            await finish(
                id: id,
                payload: payload,
                onUpdate: onUpdate
            )
        case .input, .resize:
            break
        }
    }

    private func appendOutput(
        id: String,
        data: Data,
        onUpdate: @escaping @MainActor @Sendable (AgentInlineTerminalViewState) -> Void
    ) async {
        guard let terminal = terminals[id] else { return }
        if let handle = try? FileHandle(forWritingTo: terminal.logFileURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }

        let chunk = String(bytes: data, encoding: .utf8) ?? ""
        terminal.output.append(chunk)
        if let outputByteLimit = terminal.outputByteLimit {
            while terminal.output.lengthOfBytes(using: .utf8) > outputByteLimit, !terminal.output.isEmpty {
                terminal.output.removeFirst()
                terminal.truncated = true
            }
        }

        let snapshot = snapshot(for: terminal)
        retainedSnapshots[id] = snapshot
        await onUpdate(snapshot)
    }

    private func finish(
        id: String,
        payload: Data,
        onUpdate: @escaping @MainActor @Sendable (AgentInlineTerminalViewState) -> Void
    ) async {
        guard let terminal = terminals[id] else { return }
        terminal.isRunning = false
        try? terminal.attachHandle.close()

        if let exitFrame = try? JSONDecoder().decode(TerminalHostExitFrame.self, from: payload) {
            terminal.exitStatus = AgentInlineTerminalExitStatus(
                exitCode: exitFrame.exitCode,
                signal: exitFrame.signal
            )
        }

        let snapshot = snapshot(for: terminal)
        retainedSnapshots[id] = snapshot
        let waiters = terminal.waiters
        terminal.waiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: terminal.exitStatus)
        }
        await onUpdate(snapshot)
    }

    private func finishUnexpectedly(
        id: String,
        onUpdate: @escaping @MainActor @Sendable (AgentInlineTerminalViewState) -> Void
    ) async {
        guard let terminal = terminals[id], terminal.isRunning else { return }
        await finish(id: id, payload: Data(), onUpdate: onUpdate)
    }

    private func snapshot(for terminal: ManagedTerminal) -> AgentInlineTerminalViewState {
        AgentInlineTerminalViewState(
            terminalID: terminal.terminalID,
            hostedSessionID: terminal.hostedSessionID,
            command: terminal.command,
            workingDirectoryURL: terminal.workingDirectoryURL,
            logFileURL: terminal.logFileURL,
            output: terminal.output,
            truncated: terminal.truncated,
            isRunning: terminal.isRunning,
            exitCode: terminal.exitStatus.exitCode,
            signal: terminal.exitStatus.signal
        )
    }

    private static func attachHandle(
        sessionID: UUID,
        socketPath: String
    ) throws -> FileHandle {
        let fd = try TerminalHostSocketIO.connect(to: socketPath)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let request = TerminalHostControlRequest.attach(sessionID: sessionID, cols: 120, rows: 40)
        let requestData = try JSONEncoder().encode(request)
        try TerminalHostSocketIO.writeLine(requestData, to: handle)

        let responseData = try TerminalHostSocketIO.readLine(from: handle)
        let response = try JSONDecoder().decode(TerminalHostControlResponse.self, from: responseData)
        switch response {
        case .attached:
            return handle
        case .failure(let message):
            try? handle.close()
            throw AgentWorkspaceBridgeError.unavailable(message)
        default:
            try? handle.close()
            throw AgentWorkspaceBridgeError.unavailable("Failed to attach to the hosted terminal session.")
        }
    }
}
