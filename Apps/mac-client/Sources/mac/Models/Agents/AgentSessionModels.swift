// swiftlint:disable file_length
import ACPClientKit
import Foundation
import Observation
import Workspace

typealias AgentSessionID = ACPSessionID

enum AgentSessionLaunchState: Equatable, Sendable {
    case idle
    case launching
    case connected
    case failed(String)
}

enum AgentAttachment: Equatable, Sendable, Identifiable {
    case file(url: URL)
    case gitDiff(path: String, isStaged: Bool)
    case image(url: URL)
    case url(URL)
    case snippet(language: String?, content: String)

    var id: String {
        switch self {
        case .file(let url):
            "file:\(url.absoluteString)"
        case .gitDiff(let path, let isStaged):
            "gitDiff:\(path):\(isStaged)"
        case .image(let url):
            "image:\(url.absoluteString)"
        case .url(let url):
            "url:\(url.absoluteString)"
        case .snippet(let language, let content):
            "snippet:\(language ?? "plain"):\(content)"
        }
    }
}

enum AgentMessageRole: String, Sendable, Equatable {
    case user
    case assistant
    case thought
}

struct AgentMessageTimelineItem: Equatable, Sendable, Identifiable {
    let id: String
    var role: AgentMessageRole
    var text: String
}

struct AgentToolContentPreview: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case text
        case diff
        case terminal
        case resource
        case image
        case unknown
    }

    let id: String
    var kind: Kind
    var summary: String
    var diff: AgentDiffContent?
    var terminalID: String?
}

struct AgentToolCallTimelineItem: Equatable, Sendable, Identifiable {
    let id: String
    var toolCallId: String
    var title: String
    var kind: String?
    var status: String?
    var locations: [AgentToolCallLocation]
    var content: [AgentToolContentPreview]
}

struct AgentApprovalTimelineItem: Equatable, Sendable, Identifiable {
    let id: String
    let requestID: ACPRequestID
    var title: String
    var toolCallId: String
    var options: [AgentPermissionOption]
    var selectedOptionID: String?
    var isResolved: Bool
}

struct AgentPlanTimelineItem: Equatable, Sendable, Identifiable {
    let id: String
    var entries: [AgentPlanEntry]
}

enum AgentStatusStyle: Equatable, Sendable {
    case neutral
    case warning
    case error
}

struct AgentStatusTimelineItem: Equatable, Sendable, Identifiable {
    let id: String
    var text: String
    var style: AgentStatusStyle
}

struct AgentFollowTarget: Equatable, Sendable {
    var location: AgentToolCallLocation
    var diff: AgentDiffContent?
}

struct AgentSubmissionSnapshot: Equatable, Sendable {
    var draft: String
    var selectedCommand: AgentAvailableCommand?
    var attachments: [AgentAttachment]
}

struct AgentPromptDraftResolution: Equatable, Sendable {
    var text: String
    var command: AgentAvailableCommand?
}

private struct PendingUserReplay {
    let messageID: String
    let expectedText: String
    var receivedText: String
}

enum AgentTimelineItem: Equatable, Sendable, Identifiable {
    case message(AgentMessageTimelineItem)
    case toolCall(AgentToolCallTimelineItem)
    case approval(AgentApprovalTimelineItem)
    case plan(AgentPlanTimelineItem)
    case status(AgentStatusTimelineItem)

    var id: String {
        switch self {
        case .message(let item):
            item.id
        case .toolCall(let item):
            item.id
        case .approval(let item):
            item.id
        case .plan(let item):
            item.id
        case .status(let item):
            item.id
        }
    }
}

enum AgentComposerSpeechState: Equatable, Sendable {
    case idle
    case recording(partialText: String)
    case permissionDenied(String)
    case unavailable(String)
    case failed(String)

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            nil
        case .recording(let partialText):
            partialText.isEmpty ? "Listening…" : partialText
        case .permissionDenied(let message),
             .unavailable(let message),
             .failed(let message):
            message
        }
    }
}

@MainActor
@Observable
// swiftlint:disable:next type_body_length
final class AgentSessionRuntime: Identifiable, TabContentProvider {
    nonisolated let id: String
    let workspaceID: Workspace.ID
    private(set) var sessionID: AgentSessionID
    private(set) var descriptor: ACPAgentDescriptor

    var connection: ACPConnection?
    var initializeResult: ACPInitializeResult?
    var launchState: AgentSessionLaunchState
    var timeline: [AgentTimelineItem]
    var attachments: [AgentAttachment]
    var attachmentSummaries: [AgentAttachmentSummary]
    var tabTitle: String
    var tabIcon: String
    var tabSubtitle: String?
    var draft: String
    var selectedCommand: AgentAvailableCommand?
    var mentionSuggestions: [AgentMentionSuggestion]
    var inlineTerminals: [String: AgentInlineTerminalViewState]
    var availableCommands: [AgentAvailableCommand]
    var configOptions: [AgentSessionConfigOption]
    var currentModeID: String?
    var isSendingPrompt: Bool
    var speechState: AgentComposerSpeechState
    var createdAt: Date
    var lastActivityAt: Date
    var lastSubmission: AgentSubmissionSnapshot?

    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var promptTask: Task<Void, Never>?
    @ObservationIgnored private var mentionTask: Task<Void, Never>?
    @ObservationIgnored private var speechCapture: (any AgentComposerSpeechCapture)?
    @ObservationIgnored private var speechBaseDraft = ""
    @ObservationIgnored private var pendingPermissionRequests: [ACPRequestID: AgentApprovalTimelineItem] = [:]
    @ObservationIgnored private var pendingUserReplay: PendingUserReplay?
    @ObservationIgnored private var workspaceBridge: AgentWorkspaceBridge?

    init(
        workspaceID: Workspace.ID,
        sessionID: AgentSessionID,
        descriptor: ACPAgentDescriptor,
        launchState: AgentSessionLaunchState = .idle,
        timeline: [AgentTimelineItem] = [],
        attachments: [AgentAttachment] = []
    ) {
        self.id = sessionID.rawValue
        self.workspaceID = workspaceID
        self.sessionID = sessionID
        self.descriptor = descriptor
        self.connection = nil
        self.initializeResult = nil
        self.launchState = launchState
        self.timeline = timeline
        self.attachments = attachments
        self.attachmentSummaries = []
        self.tabTitle = descriptor.displayName
        self.tabIcon = AgentSessionRuntime.defaultIcon(for: descriptor.kind)
        self.tabSubtitle = nil
        self.draft = ""
        self.selectedCommand = nil
        self.mentionSuggestions = []
        self.inlineTerminals = [:]
        self.availableCommands = []
        self.configOptions = []
        self.currentModeID = nil
        self.isSendingPrompt = false
        self.speechState = .idle
        self.createdAt = Date()
        self.lastActivityAt = Date()
        self.lastSubmission = nil
    }

    deinit {
        eventTask?.cancel()
        promptTask?.cancel()
        mentionTask?.cancel()
    }

    var tabFolder: URL? {
        URL(fileURLWithPath: workspaceID, isDirectory: true)
    }

    var tabShowsBusyIndicator: Bool {
        true
    }

    var tabIsBusy: Bool {
        launchState == .launching || isSendingPrompt
    }

    var canSendDraft: Bool {
        launchState == .connected
            && connection != nil
            && (resolvedPromptDraft(draft: draft, selectedCommand: selectedCommand) != nil || !attachments.isEmpty)
            && !isSendingPrompt
    }

    var commandInputHint: String? {
        selectedCommand?.input?.hint
    }

    func updatePresentation(
        title: String? = nil,
        icon: String? = nil,
        subtitle: String? = nil
    ) {
        if let title, !title.isEmpty {
            tabTitle = title
        }
        if let icon {
            tabIcon = icon
        }
        tabSubtitle = subtitle
    }

    func bind(
        connection: ACPConnection,
        initializeResult: ACPInitializeResult? = nil,
        newSessionResponse: AgentSessionNewResponse? = nil,
        loadSessionResponse: AgentSessionLoadResponse? = nil
    ) {
        self.connection = connection
        self.initializeResult = initializeResult
        if let newSessionResponse {
            configOptions = newSessionResponse.configOptions ?? []
            currentModeID = newSessionResponse.modes?.currentModeId
        }
        if let loadSessionResponse {
            configOptions = loadSessionResponse.configOptions ?? []
            currentModeID = loadSessionResponse.modes?.currentModeId
        }
        launchState = .connected
        tabSubtitle = "Connected"
        touchActivity()
        refreshAttachmentSummaries()
        startEventLoop()
    }

    func recordLaunchFailure(_ message: String) {
        eventTask?.cancel()
        eventTask = nil
        promptTask?.cancel()
        promptTask = nil
        mentionTask?.cancel()
        mentionTask = nil
        connection = nil
        isSendingPrompt = false
        launchState = .failed(message)
        tabSubtitle = "Attention Required"
        resolvePendingPermissionRequests()
        touchActivity()
        timeline.append(
            .status(
                AgentStatusTimelineItem(
                    id: "status:\(UUID().uuidString)",
                    text: message,
                    style: .error
                )
            )
        )
    }

    func prepareForRestore(title: String?, subtitle: String?) {
        launchState = .launching
        if let title, !title.isEmpty {
            tabTitle = title
        }
        tabSubtitle = subtitle ?? "Restoring"
        touchActivity()
    }

    func updateSessionIdentity(
        sessionID: AgentSessionID,
        descriptor: ACPAgentDescriptor
    ) {
        self.sessionID = sessionID
        self.descriptor = descriptor
        tabTitle = descriptor.displayName
        tabIcon = Self.defaultIcon(for: descriptor.kind)
    }

    var canRetryLastSubmission: Bool {
        lastSubmission != nil && !isSendingPrompt
    }

    func retryLastSubmission() {
        guard let lastSubmission else { return }
        draft = lastSubmission.draft
        selectedCommand = lastSubmission.selectedCommand
        attachments = lastSubmission.attachments
        refreshAttachmentSummaries()
        refreshMentionSuggestions()
        sendDraft()
    }

    var stateSummary: String {
        switch launchState {
        case .idle:
            return "Idle"
        case .launching:
            return tabSubtitle ?? "Launching"
        case .connected:
            if isSendingPrompt {
                return "Running"
            }
            return tabSubtitle ?? "Connected"
        case .failed(let message):
            return message
        }
    }

    func configureWorkspaceBridge(_ bridge: AgentWorkspaceBridge) {
        workspaceBridge = bridge
        bridge.inlineTerminalUpdateHandler = { [weak self] snapshot in
            self?.inlineTerminals[snapshot.terminalID] = snapshot
        }
        refreshAttachmentSummaries()
        refreshMentionSuggestions()
    }

    func updateDraft(_ text: String) {
        draft = text
        refreshMentionSuggestions()
    }

    func selectSlashCommand(_ command: AgentAvailableCommand) {
        selectedCommand = command
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
            draft = ""
        }
        refreshMentionSuggestions()
    }

    func clearSelectedSlashCommand() {
        selectedCommand = nil
    }

    func addAttachment(_ attachment: AgentAttachment) {
        guard !attachments.contains(where: { $0.id == attachment.id }) else { return }
        attachments.append(attachment)
        refreshAttachmentSummaries()
    }

    func addAttachments(_ newAttachments: [AgentAttachment]) {
        var didChange = false
        for attachment in newAttachments where !attachments.contains(where: { $0.id == attachment.id }) {
            attachments.append(attachment)
            didChange = true
        }
        guard didChange else { return }
        refreshAttachmentSummaries()
    }

    func removeAttachment(id: String) {
        attachments.removeAll { $0.id == id }
        attachmentSummaries.removeAll { $0.id == id }
    }

    func inlineTerminal(id: String) -> AgentInlineTerminalViewState? {
        inlineTerminals[id]
    }

    func noteStatus(
        _ text: String,
        style: AgentStatusStyle
    ) {
        appendStatus(text, style: style)
    }

    func insertMention(_ suggestion: AgentMentionSuggestion) {
        guard let tokenRange = mentionTokenRange(in: draft) else { return }
        var updatedDraft = draft
        updatedDraft.replaceSubrange(tokenRange, with: "")
        updateDraft(updatedDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        addAttachment(.file(url: suggestion.url))
    }

    func promoteInlineTerminal(_ terminalID: String) async throws -> UUID {
        guard let workspaceBridge else {
            throw AgentWorkspaceBridgeError.unavailable("Workspace bridge unavailable for terminal promotion.")
        }
        return try await workspaceBridge.promoteInlineTerminal(id: terminalID)
    }

    // swiftlint:disable:next function_body_length
    func sendDraft() {
        guard let connection else { return }
        let draftSnapshot = draft
        let draftResolution = resolvedPromptDraft(
            draft: draftSnapshot,
            selectedCommand: selectedCommand
        )
        let attachmentSnapshot = attachments
        guard draftResolution != nil || !attachmentSnapshot.isEmpty else {
            return
        }

        isSendingPrompt = true
        touchActivity()

        promptTask?.cancel()
        promptTask = Task { [weak self] in
            guard let self else { return }
            do {
                let blocks = try await self.makePromptBlocks(
                    draft: draftResolution?.text ?? "",
                    attachments: attachmentSnapshot
                )
                guard !blocks.isEmpty else {
                    await self.finishPromptWithError("Prompt is empty.")
                    return
                }
                self.lastSubmission = AgentSubmissionSnapshot(
                    draft: draftSnapshot,
                    selectedCommand: draftResolution?.command,
                    attachments: attachmentSnapshot
                )
                if let submittedText = draftResolution?.text {
                    self.recordOptimisticUserSubmission(text: submittedText)
                } else {
                    self.pendingUserReplay = nil
                }
                self.draft = ""
                self.selectedCommand = nil
                self.attachments = []
                self.attachmentSummaries = []
                self.mentionSuggestions = []
                let response: AgentPromptResponse = try await connection.sendRequest(
                    method: "session/prompt",
                    params: AgentPromptRequest(sessionId: self.sessionID, prompt: blocks),
                    as: AgentPromptResponse.self
                )
                await self.handlePromptCompletion(stopReason: response.stopReason)
            } catch let error as ACPRemoteError {
                await self.finishPromptFailure(
                    message: error.message,
                    draft: draftSnapshot,
                    selectedCommand: draftResolution?.command,
                    attachments: attachmentSnapshot
                )
            } catch let error as ACPTransportError {
                await self.finishPromptFailure(
                    message: String(describing: error),
                    draft: draftSnapshot,
                    selectedCommand: draftResolution?.command,
                    attachments: attachmentSnapshot
                )
            } catch {
                await self.finishPromptFailure(
                    message: error.localizedDescription,
                    draft: draftSnapshot,
                    selectedCommand: draftResolution?.command,
                    attachments: attachmentSnapshot
                )
            }
        }
    }

    func cancelPrompt() {
        guard isSendingPrompt else { return }
        speechBaseDraft = ""
        touchActivity()

        let pendingIDs = pendingPermissionRequests.keys
        if let connection {
            Task { [sessionID] in
                for requestID in pendingIDs {
                    try? await connection.respond(
                        to: requestID,
                        result: AgentRequestPermissionResponse(outcome: .cancelled)
                    )
                }
                try? await connection.sendNotification(
                    method: "session/cancel",
                    params: ACPValue.object([
                        "sessionId": .string(sessionID.rawValue)
                    ])
                )
            }
        }
    }

    func setConfigOption(
        id: String,
        value: String
    ) {
        guard let connection else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let response: ACPValue = try await connection.sendRequest(
                    method: "session/set_config_option",
                    params: ACPValue.object([
                        "sessionId": .string(self.sessionID.rawValue),
                        "configId": .string(id),
                        "value": .string(value)
                    ]),
                    as: ACPValue.self
                )
                if let configOptionsValue = response["configOptions"] {
                    let configOptions = try ACPValue.decode([AgentSessionConfigOption].self, from: configOptionsValue)
                    self.applyConfigOptions(configOptions)
                }
            } catch {
                self.appendStatus(
                    "Failed to update \(id): \(error.localizedDescription)",
                    style: .error
                )
            }
        }
    }

    func respondToApproval(
        requestID: ACPRequestID,
        optionID: String
    ) {
        guard var approval = pendingPermissionRequests[requestID] else {
            return
        }

        approval.selectedOptionID = optionID
        approval.isResolved = true
        pendingPermissionRequests.removeValue(forKey: requestID)
        replaceTimelineItem(.approval(approval))
        touchActivity()

        guard let connection else { return }

        Task {
            try? await connection.respond(
                to: requestID,
                result: AgentRequestPermissionResponse(
                    outcome: .selected(optionId: optionID)
                )
            )
        }
    }

    func startDictation(using service: any AgentComposerSpeechService) {
        guard !speechState.isRecording else { return }
        touchActivity()

        Task { [weak self] in
            guard let self else { return }
            do {
                speechBaseDraft = draft
                let capture = try await service.startTranscription { [weak self] event in
                    guard let self else { return }
                    self.applySpeechEvent(event)
                }
                speechCapture = capture
                speechState = .recording(partialText: "")
            } catch let error as AgentComposerSpeechError {
                handleSpeechError(error)
            } catch {
                speechState = .failed(error.localizedDescription)
            }
        }
    }

    func stopDictation() {
        guard let speechCapture else { return }
        touchActivity()
        _ = speechCapture
        Task { [weak self] in
            await self?.finishSpeechCapture(stopCapture: true)
        }
    }

    func teardown() async {
        promptTask?.cancel()
        eventTask?.cancel()
        mentionTask?.cancel()
        await speechCapture?.stop()
        speechCapture = nil
        if let connection {
            await connection.shutdown()
        }
    }

    private func startEventLoop() {
        eventTask?.cancel()
        guard let connection else { return }

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in connection.events {
                await self.handleConnectionEvent(event)
            }
        }
    }

    private func handleConnectionEvent(_ event: ACPConnectionEvent) async {
        switch event {
        case .notification(let notification):
            handleNotification(notification)
        case .request(let request):
            handleRequest(request)
        case .stderr(let text):
            if launchState == .launching {
                tabSubtitle = text
            }
        case .terminated(let termination):
            eventTask?.cancel()
            eventTask = nil
            promptTask?.cancel()
            promptTask = nil
            connection = nil
            isSendingPrompt = false
            launchState = .failed("Adapter terminated (\(termination.reason.rawValue)).")
            resolvePendingPermissionRequests()
            appendStatus("Adapter terminated.", style: .error)
        }
    }

    private func handleNotification(_ notification: ACPNotification) {
        guard notification.method == "session/update",
              let params = notification.params,
              let decoded = try? ACPValue.decode(AgentSessionNotification.self, from: params),
              decoded.sessionId == sessionID else {
            return
        }

        receiveSessionUpdate(decoded.update)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func handleRequest(_ request: ACPIncomingRequest) {
        switch request.method {
        case "session/request_permission":
            guard let permissionRequest = decodeRequest(
                AgentRequestPermissionRequest.self,
                from: request,
                expectedSessionID: sessionID
            ) else {
                respondInvalidRequest(
                    request.id,
                    message: "Invalid permission request"
                )
                return
            }
            receivePermissionRequest(
                requestID: request.id,
                permissionRequest: permissionRequest
            )
        case "fs/read_text_file":
            guard let fileRequest = decodeRequest(
                AgentReadTextFileRequest.self,
                from: request,
                expectedSessionID: sessionID
            ) else {
                respondInvalidRequest(
                    request.id,
                    message: "Invalid file read request"
                )
                return
            }
            Task { [weak self] in
                await self?.respondToReadRequest(fileRequest, requestID: request.id)
            }
        case "fs/write_text_file":
            guard let fileRequest = decodeRequest(
                AgentWriteTextFileRequest.self,
                from: request,
                expectedSessionID: sessionID
            ) else {
                respondInvalidRequest(
                    request.id,
                    message: "Invalid file write request"
                )
                return
            }
            Task { [weak self] in
                await self?.respondToWriteRequest(fileRequest, requestID: request.id)
            }
        case "terminal/create":
            guard let terminalRequest = decodeRequest(
                AgentCreateTerminalRequest.self,
                from: request,
                expectedSessionID: sessionID
            ) else {
                respondInvalidRequest(
                    request.id,
                    message: "Invalid terminal create request"
                )
                return
            }
            Task { [weak self] in
                await self?.respondToCreateTerminal(terminalRequest, requestID: request.id)
            }
        case "terminal/output":
            guard let terminalRequest = decodeRequest(
                AgentTerminalOutputRequest.self,
                from: request,
                expectedSessionID: sessionID
            ) else {
                respondInvalidRequest(
                    request.id,
                    message: "Invalid terminal output request"
                )
                return
            }
            Task { [weak self] in
                await self?.respondToTerminalOutput(terminalRequest, requestID: request.id)
            }
        case "terminal/wait_for_exit":
            guard let terminalRequest = decodeRequest(
                AgentWaitForTerminalExitRequest.self,
                from: request,
                expectedSessionID: sessionID
            ) else {
                respondInvalidRequest(
                    request.id,
                    message: "Invalid terminal wait request"
                )
                return
            }
            Task { [weak self] in
                await self?.respondToWaitForExit(terminalRequest, requestID: request.id)
            }
        case "terminal/kill":
            guard let terminalRequest = decodeRequest(
                AgentKillTerminalRequest.self,
                from: request,
                expectedSessionID: sessionID
            ) else {
                respondInvalidRequest(
                    request.id,
                    message: "Invalid terminal kill request"
                )
                return
            }
            Task { [weak self] in
                await self?.respondToKillTerminal(terminalRequest, requestID: request.id)
            }
        case "terminal/release":
            guard let terminalRequest = decodeRequest(
                AgentReleaseTerminalRequest.self,
                from: request,
                expectedSessionID: sessionID
            ) else {
                respondInvalidRequest(
                    request.id,
                    message: "Invalid terminal release request"
                )
                return
            }
            Task { [weak self] in
                await self?.respondToReleaseTerminal(terminalRequest, requestID: request.id)
            }
        default:
            Task {
                try? await connection?.respondError(
                    to: request.id,
                    error: ACPRemoteError(code: -32601, message: "Method not supported")
                )
            }
        }
    }

    func receivePermissionRequest(
        requestID: ACPRequestID,
        permissionRequest: AgentRequestPermissionRequest
    ) {
        let approval = AgentApprovalTimelineItem(
            id: "approval:\(requestID.rawValue)",
            requestID: requestID,
            title: permissionRequest.toolCall.title ?? "Permission required",
            toolCallId: permissionRequest.toolCall.toolCallId,
            options: permissionRequest.options,
            selectedOptionID: nil,
            isResolved: false
        )
        pendingPermissionRequests[requestID] = approval
        replaceTimelineItem(.approval(approval))
        touchActivity()
    }

    func receiveSessionUpdate(_ update: AgentSessionUpdate) {
        touchActivity()
        switch update {
        case .userMessageChunk(let content):
            receiveUserMessageChunk(content.plainText)
        case .assistantMessageChunk(let content):
            appendMessage(role: .assistant, text: content.plainText)
        case .agentThoughtChunk(let content):
            appendMessage(role: .thought, text: content.plainText)
        case .toolCall(let toolCall):
            upsertToolCall(toolCall)
        case .toolCallUpdate(let update):
            updateToolCall(update)
        case .plan(let plan):
            replaceTimelineItem(
                .plan(
                    AgentPlanTimelineItem(
                        id: "plan",
                        entries: plan.entries
                    )
                )
            )
        case .availableCommandsUpdate(let commands):
            availableCommands = commands
            if let selectedCommand,
               !commands.contains(where: { $0.name == selectedCommand.name }) {
                self.selectedCommand = nil
            }
        case .currentModeUpdate(let currentModeID):
            self.currentModeID = currentModeID
        case .configOptionUpdate(let configOptions):
            applyConfigOptions(configOptions)
        case .sessionInfoUpdate(let info):
            if let title = info.title, !title.isEmpty {
                tabTitle = title
            }
            tabSubtitle = info.updatedAt ?? tabSubtitle
        }
    }

    private func decodeRequest<Request: Decodable & AgentSessionScopedRequest>(
        _ type: Request.Type,
        from request: ACPIncomingRequest,
        expectedSessionID: AgentSessionID
    ) -> Request? {
        guard let params = request.params,
              let decoded = try? ACPValue.decode(Request.self, from: params),
              decoded.sessionId == expectedSessionID else {
            return nil
        }
        return decoded
    }

    private func respondInvalidRequest(
        _ requestID: ACPRequestID,
        message: String
    ) {
        Task {
            try? await connection?.respondError(
                to: requestID,
                error: ACPRemoteError(code: -32602, message: message)
            )
        }
    }

    private func respondToReadRequest(
        _ request: AgentReadTextFileRequest,
        requestID: ACPRequestID
    ) async {
        guard let workspaceBridge else {
            await respondBridgeUnavailable(
                requestID: requestID,
                message: "Workspace bridge unavailable for file reads."
            )
            return
        }

        do {
            let content = try workspaceBridge.readTextFile(
                path: request.path,
                line: request.line,
                limit: request.limit
            )
            try await connection?.respond(
                to: requestID,
                result: AgentReadTextFileResponse(content: content)
            )
        } catch {
            await respondBridgeError(error, requestID: requestID)
        }
    }

    private func respondToWriteRequest(
        _ request: AgentWriteTextFileRequest,
        requestID: ACPRequestID
    ) async {
        guard let workspaceBridge else {
            await respondBridgeUnavailable(
                requestID: requestID,
                message: "Workspace bridge unavailable for file writes."
            )
            return
        }

        do {
            try await workspaceBridge.writeTextFile(path: request.path, content: request.content)
            try await connection?.respond(to: requestID, result: ACPValue?.none)
        } catch {
            await respondBridgeError(error, requestID: requestID)
        }
    }

    private func respondToCreateTerminal(
        _ request: AgentCreateTerminalRequest,
        requestID: ACPRequestID
    ) async {
        guard let workspaceBridge else {
            await respondBridgeUnavailable(
                requestID: requestID,
                message: "Workspace bridge unavailable for terminals."
            )
            return
        }

        do {
            let response = try await workspaceBridge.createInlineTerminal(request: request)
            try await connection?.respond(to: requestID, result: response)
        } catch {
            await respondBridgeError(error, requestID: requestID)
        }
    }

    private func respondToTerminalOutput(
        _ request: AgentTerminalOutputRequest,
        requestID: ACPRequestID
    ) async {
        guard let workspaceBridge else {
            await respondBridgeUnavailable(
                requestID: requestID,
                message: "Workspace bridge unavailable for terminals."
            )
            return
        }

        do {
            let response = try await workspaceBridge.terminalOutput(request: request)
            try await connection?.respond(to: requestID, result: response)
        } catch {
            await respondBridgeError(error, requestID: requestID)
        }
    }

    private func respondToWaitForExit(
        _ request: AgentWaitForTerminalExitRequest,
        requestID: ACPRequestID
    ) async {
        guard let workspaceBridge else {
            await respondBridgeUnavailable(
                requestID: requestID,
                message: "Workspace bridge unavailable for terminals."
            )
            return
        }

        do {
            let response = try await workspaceBridge.waitForTerminalExit(request: request)
            try await connection?.respond(to: requestID, result: response)
        } catch {
            await respondBridgeError(error, requestID: requestID)
        }
    }

    private func respondToKillTerminal(
        _ request: AgentKillTerminalRequest,
        requestID: ACPRequestID
    ) async {
        guard let workspaceBridge else {
            await respondBridgeUnavailable(
                requestID: requestID,
                message: "Workspace bridge unavailable for terminals."
            )
            return
        }

        do {
            try await workspaceBridge.killTerminal(request: request)
            try await connection?.respond(to: requestID, result: ACPValue?.none)
        } catch {
            await respondBridgeError(error, requestID: requestID)
        }
    }

    private func respondToReleaseTerminal(
        _ request: AgentReleaseTerminalRequest,
        requestID: ACPRequestID
    ) async {
        guard let workspaceBridge else {
            await respondBridgeUnavailable(
                requestID: requestID,
                message: "Workspace bridge unavailable for terminals."
            )
            return
        }

        do {
            try await workspaceBridge.releaseTerminal(request: request)
            try await connection?.respond(to: requestID, result: ACPValue?.none)
        } catch {
            await respondBridgeError(error, requestID: requestID)
        }
    }

    private func respondBridgeUnavailable(
        requestID: ACPRequestID,
        message: String
    ) async {
        try? await connection?.respondError(
            to: requestID,
            error: ACPRemoteError(code: -32003, message: message)
        )
    }

    private func respondBridgeError(
        _ error: Error,
        requestID: ACPRequestID
    ) async {
        let remoteError: ACPRemoteError
        if let workspaceError = error as? AgentWorkspaceBridgeError {
            let code: Int = switch workspaceError {
            case .invalidPath, .outsideWorkspace, .nonTextFile:
                -32001
            case .terminalNotFound:
                -32002
            case .unavailable:
                -32003
            }
            remoteError = ACPRemoteError(
                code: code,
                message: workspaceError.localizedDescription
            )
        } else {
            remoteError = ACPRemoteError(code: -32000, message: error.localizedDescription)
        }

        try? await connection?.respondError(
            to: requestID,
            error: remoteError
        )
    }

    private func applyConfigOptions(_ configOptions: [AgentSessionConfigOption]) {
        self.configOptions = configOptions
        if let modeOption = configOptions.first(where: { $0.category == "mode" || $0.id == "mode" }) {
            currentModeID = modeOption.currentValue
        }
        touchActivity()
    }

    private func handlePromptCompletion(stopReason: String) async {
        isSendingPrompt = false
        touchActivity()
        if stopReason == "cancelled" {
            appendStatus("Prompt cancelled.", style: .warning)
        }
    }

    private func finishPromptWithError(_ message: String) async {
        isSendingPrompt = false
        touchActivity()
        appendStatus(message, style: .error)
    }

    private func finishPromptFailure(
        message: String,
        draft: String,
        selectedCommand: AgentAvailableCommand?,
        attachments: [AgentAttachment]
    ) async {
        if self.draft.isEmpty {
            self.draft = draft
        }
        if self.selectedCommand == nil {
            self.selectedCommand = selectedCommand
        }
        if self.attachments.isEmpty {
            self.attachments = attachments
            refreshAttachmentSummaries()
        }
        await finishPromptWithError(message)
    }

    private func makePromptBlocks(
        draft: String,
        attachments: [AgentAttachment]
    ) async throws -> [AgentContentBlock] {
        if let workspaceBridge {
            return try await workspaceBridge.promptBlocks(
                draft: draft,
                attachments: attachments,
                capabilities: initializeResult?.capabilities.promptCapabilities ?? ACPPromptCapabilities()
            )
        }

        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [.text(AgentTextContent(text: trimmed))]
    }

    func resolvedPromptDraft(
        draft: String,
        selectedCommand: AgentAvailableCommand?
    ) -> AgentPromptDraftResolution? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selectedCommand {
            let text = trimmed.isEmpty
                ? "/\(selectedCommand.name)"
                : "/\(selectedCommand.name) \(trimmed)"
            return AgentPromptDraftResolution(text: text, command: selectedCommand)
        }

        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("/") else {
            return AgentPromptDraftResolution(text: trimmed, command: nil)
        }

        let slashBody = String(trimmed.dropFirst())
        let commandName = slashBody.prefix { !$0.isWhitespace }
        guard !commandName.isEmpty,
              let command = availableCommands.first(
                where: { $0.name.caseInsensitiveCompare(String(commandName)) == .orderedSame }
              ) else {
            return AgentPromptDraftResolution(text: trimmed, command: nil)
        }

        let inputStart = slashBody.index(slashBody.startIndex, offsetBy: commandName.count)
        let input = slashBody[inputStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        let text = input.isEmpty ? "/\(command.name)" : "/\(command.name) \(input)"
        return AgentPromptDraftResolution(text: text, command: command)
    }

    private func refreshAttachmentSummaries() {
        guard let workspaceBridge else {
            attachmentSummaries = attachments.map {
                AgentAttachmentSummary(
                    attachment: $0,
                    title: $0.id,
                    subtitle: nil,
                    systemImage: "paperclip",
                    delivery: .linked
                )
            }
            return
        }

        let bridge = workspaceBridge
        let attachments = self.attachments
        let capabilities = initializeResult?.capabilities.promptCapabilities ?? ACPPromptCapabilities()
        Task { [weak self] in
            guard let self else { return }
            let summaries = await bridge.attachmentSummaries(
                for: attachments,
                capabilities: capabilities
            )
            if self.attachments.map(\.id) == attachments.map(\.id) {
                self.attachmentSummaries = summaries
            }
        }
    }

    private func refreshMentionSuggestions() {
        guard let workspaceBridge,
              let query = mentionQuery(in: draft) else {
            mentionTask?.cancel()
            mentionTask = nil
            mentionSuggestions = []
            return
        }
        let draftSnapshot = draft
        mentionTask?.cancel()
        mentionTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }

            let suggestions = await workspaceBridge.mentionSuggestions(matching: query)
            guard !Task.isCancelled,
                  let self,
                  self.draft == draftSnapshot,
                  self.mentionQuery(in: self.draft) == query else {
                return
            }
            self.mentionSuggestions = suggestions
        }
    }

    private func mentionQuery(in draft: String) -> String? {
        guard let range = mentionTokenRange(in: draft) else {
            return nil
        }
        let token = draft[range]
        let query = String(token.dropFirst())
        return query.isEmpty ? nil : query
    }

    private func mentionTokenRange(in draft: String) -> Range<String.Index>? {
        guard !draft.isEmpty else { return nil }
        var start = draft.endIndex
        while start > draft.startIndex {
            let index = draft.index(before: start)
            if draft[index].isWhitespace {
                break
            }
            start = index
        }
        guard start < draft.endIndex,
              draft[start] == "@" else {
            return nil
        }
        return start..<draft.endIndex
    }

    private func appendMessage(
        role: AgentMessageRole,
        text: String
    ) {
        guard !text.isEmpty else { return }
        if case .message(var message)? = timeline.last,
           message.role == role {
            message.text += text
            timeline[timeline.count - 1] = .message(message)
            return
        }

        timeline.append(
            .message(
                AgentMessageTimelineItem(
                    id: "message:\(role.rawValue):\(UUID().uuidString)",
                    role: role,
                    text: text
                )
            )
        )
    }

    func recordOptimisticUserSubmission(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pendingUserReplay = nil
            return
        }

        let messageID = "message:user:local:\(UUID().uuidString)"
        timeline.append(
            .message(
                AgentMessageTimelineItem(
                    id: messageID,
                    role: .user,
                    text: trimmed
                )
            )
        )
        pendingUserReplay = PendingUserReplay(
            messageID: messageID,
            expectedText: trimmed,
            receivedText: ""
        )
        touchActivity()
    }

    private func receiveUserMessageChunk(_ text: String) {
        guard !text.isEmpty else { return }

        guard var pendingUserReplay else {
            appendMessage(role: .user, text: text)
            return
        }

        let combined = pendingUserReplay.receivedText + text
        if pendingUserReplay.expectedText.hasPrefix(combined) {
            pendingUserReplay.receivedText = combined
            self.pendingUserReplay = combined == pendingUserReplay.expectedText ? nil : pendingUserReplay
            return
        }

        self.pendingUserReplay = nil
        if replaceMessageText(id: pendingUserReplay.messageID, with: combined) {
            return
        }
        appendMessage(role: .user, text: text)
    }

    @discardableResult
    private func replaceMessageText(
        id: String,
        with text: String
    ) -> Bool {
        guard let index = timeline.firstIndex(where: { $0.id == id }),
              case .message(var message) = timeline[index] else {
            return false
        }
        message.text = text
        timeline[index] = .message(message)
        touchActivity()
        return true
    }

    private func upsertToolCall(_ toolCall: AgentToolCall) {
        let item = AgentToolCallTimelineItem(
            id: "tool:\(toolCall.toolCallId)",
            toolCallId: toolCall.toolCallId,
            title: toolCall.title,
            kind: toolCall.kind,
            status: toolCall.status,
            locations: toolCall.locations,
            content: toolCall.content.enumerated().map(previewContent)
        )
        replaceTimelineItem(.toolCall(item))
    }

    private func updateToolCall(_ update: AgentToolCallUpdate) {
        let identifier = "tool:\(update.toolCallId)"
        guard let index = timeline.firstIndex(where: { $0.id == identifier }),
              case .toolCall(var existing) = timeline[index] else {
            let fallback = AgentToolCallTimelineItem(
                id: identifier,
                toolCallId: update.toolCallId,
                title: update.title ?? "Tool call",
                kind: update.kind,
                status: update.status,
                locations: update.locations ?? [],
                content: (update.content ?? []).enumerated().map(previewContent)
            )
            replaceTimelineItem(.toolCall(fallback))
            return
        }

        if let title = update.title {
            existing.title = title
        }
        if let kind = update.kind {
            existing.kind = kind
        }
        if let status = update.status {
            existing.status = status
        }
        if let locations = update.locations {
            existing.locations = locations
        }
        if let content = update.content {
            existing.content = content.enumerated().map(previewContent)
        }
        timeline[index] = .toolCall(existing)
    }

    // swiftlint:disable:next function_body_length
    private func previewContent(
        indexAndContent: (offset: Int, element: AgentToolCallContent)
    ) -> AgentToolContentPreview {
        let (offset, content) = indexAndContent
        switch content {
        case .content(let block):
            switch block {
            case .text(let value):
                return AgentToolContentPreview(
                    id: "tool-content:\(offset)",
                    kind: .text,
                    summary: value.text,
                    diff: nil,
                    terminalID: nil
                )
            case .resourceLink(let link):
                return AgentToolContentPreview(
                    id: "tool-content:\(offset)",
                    kind: .resource,
                    summary: link.title ?? link.name,
                    diff: nil,
                    terminalID: nil
                )
            case .resource(let resource):
                return AgentToolContentPreview(
                    id: "tool-content:\(offset)",
                    kind: .resource,
                    summary: resource.resource.uri,
                    diff: nil,
                    terminalID: nil
                )
            case .image(let image):
                return AgentToolContentPreview(
                    id: "tool-content:\(offset)",
                    kind: .image,
                    summary: image.mimeType,
                    diff: nil,
                    terminalID: nil
                )
            case .unknown(let type):
                return AgentToolContentPreview(
                    id: "tool-content:\(offset)",
                    kind: .unknown,
                    summary: type,
                    diff: nil,
                    terminalID: nil
                )
            }
        case .diff(let diff):
            return AgentToolContentPreview(
                id: "tool-content:\(offset)",
                kind: .diff,
                summary: diff.path,
                diff: diff,
                terminalID: nil
            )
        case .terminal(let terminal):
            return AgentToolContentPreview(
                id: "tool-content:\(offset)",
                kind: .terminal,
                summary: terminal.terminalId,
                diff: nil,
                terminalID: terminal.terminalId
            )
        case .unknown(let type):
            return AgentToolContentPreview(
                id: "tool-content:\(offset)",
                kind: .unknown,
                summary: type,
                diff: nil,
                terminalID: nil
            )
        }
    }

    private func replaceTimelineItem(_ item: AgentTimelineItem) {
        if let index = timeline.firstIndex(where: { $0.id == item.id }) {
            timeline[index] = item
        } else {
            timeline.append(item)
        }
        touchActivity()
    }

    private func appendStatus(
        _ text: String,
        style: AgentStatusStyle
    ) {
        timeline.append(
            .status(
                AgentStatusTimelineItem(
                    id: "status:\(UUID().uuidString)",
                    text: text,
                    style: style
                )
            )
        )
        touchActivity()
    }

    private func resolvePendingPermissionRequests() {
        guard !pendingPermissionRequests.isEmpty else { return }
        let approvals = pendingPermissionRequests.values
        pendingPermissionRequests.removeAll()

        for var approval in approvals {
            approval.isResolved = true
            replaceTimelineItem(.approval(approval))
        }
    }

    private func applySpeechEvent(_ event: AgentComposerSpeechEvent) {
        let separator = speechBaseDraft.isEmpty ? "" : " "
        draft = speechBaseDraft + separator + event.text
        speechState = .recording(partialText: event.text)
        touchActivity()
        if event.isFinal {
            Task { [weak self] in
                await self?.finishSpeechCapture(stopCapture: true)
            }
        }
    }

    private func handleSpeechError(_ error: AgentComposerSpeechError) {
        switch error {
        case .permissionDenied(let message):
            speechState = .permissionDenied(message)
        case .unavailable(let message):
            speechState = .unavailable(message)
        case .failed(let message):
            speechState = .failed(message)
        }
    }

    private func finishSpeechCapture(stopCapture: Bool) async {
        let capture = speechCapture
        speechCapture = nil
        if stopCapture {
            await capture?.stop()
        }
        speechBaseDraft = draft
        if case .recording = speechState {
            speechState = .idle
        }
        touchActivity()
    }

    private func touchActivity() {
        lastActivityAt = Date()
    }

    private static func defaultIcon(for kind: ACPAgentKind) -> String {
        switch kind {
        case .codex:
            "chevron.left.forwardslash.chevron.right"
        case .claude:
            "brain"
        }
    }
}

@MainActor
final class WorkspaceAgentRuntimeRegistry {
    private var sessionsByID: [AgentSessionID: AgentSessionRuntime] = [:]

    var allSessions: [AgentSessionRuntime] {
        sessionsByID.values.sorted {
            if $0.lastActivityAt == $1.lastActivityAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.lastActivityAt > $1.lastActivityAt
        }
    }

    @discardableResult
    func ensureSession(
        workspaceID: Workspace.ID,
        sessionID: AgentSessionID,
        descriptor: ACPAgentDescriptor
    ) -> AgentSessionRuntime {
        if let existing = sessionsByID[sessionID] {
            return existing
        }

        let runtime = AgentSessionRuntime(
            workspaceID: workspaceID,
            sessionID: sessionID,
            descriptor: descriptor
        )
        sessionsByID[sessionID] = runtime
        return runtime
    }

    func rekeySession(
        _ runtime: AgentSessionRuntime,
        to sessionID: AgentSessionID,
        descriptor: ACPAgentDescriptor
    ) {
        sessionsByID.removeValue(forKey: runtime.sessionID)
        runtime.updateSessionIdentity(sessionID: sessionID, descriptor: descriptor)
        sessionsByID[sessionID] = runtime
    }

    func session(id: AgentSessionID) -> AgentSessionRuntime? {
        sessionsByID[id]
    }

    func removeSession(id: AgentSessionID) {
        sessionsByID.removeValue(forKey: id)
    }

    func removeAll() {
        sessionsByID.removeAll()
    }
}
