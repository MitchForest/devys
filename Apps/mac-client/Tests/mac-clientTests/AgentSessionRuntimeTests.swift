// swiftlint:disable type_body_length
import ACPClientKit
import AppFeatures
import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Agent Session Runtime Tests")
struct AgentSessionRuntimeTests {
    @Test("Tool call updates render as one evolving timeline card")
    @MainActor
    // swiftlint:disable:next function_body_length
    func toolCallUpdatesInPlace() {
        let runtime = makeRuntime()

        runtime.receiveSessionUpdate(
            .toolCall(
                AgentToolCall(
                    toolCallId: "tool-1",
                    title: "Read file",
                    kind: "read",
                    status: "running",
                    locations: [
                        AgentToolCallLocation(path: "Sources/Feature.swift", line: 8)
                    ],
                    content: [
                        .content(.text(AgentTextContent(text: "Inspecting file contents")))
                    ]
                )
            )
        )

        runtime.receiveSessionUpdate(
            .toolCallUpdate(
                AgentToolCallUpdate(
                    toolCallId: "tool-1",
                    title: "Read file",
                    kind: "read",
                    status: "completed",
                    locations: [
                        AgentToolCallLocation(path: "Sources/Feature.swift", line: 14)
                    ],
                    content: [
                        .diff(
                            AgentDiffContent(
                                path: "Sources/Feature.swift",
                                oldText: "let before = 1",
                                newText: "let after = 2"
                            )
                        )
                    ],
                    rawInput: nil,
                    rawOutput: nil
                )
            )
        )

        #expect(runtime.timeline.count == 1)

        guard case .toolCall(let item)? = runtime.timeline.first else {
            Issue.record("Expected a tool call timeline item")
            return
        }

        #expect(item.toolCallId == "tool-1")
        #expect(item.status == "completed")
        #expect(item.locations == [AgentToolCallLocation(path: "Sources/Feature.swift", line: 14)])
        #expect(item.content.count == 1)
        #expect(item.content.first?.kind == .diff)
        #expect(item.content.first?.diff?.newText == "let after = 2")
    }

    @Test("Plan updates replace prior plan state")
    @MainActor
    func planUpdatesReplacePriorState() {
        let runtime = makeRuntime()

        runtime.receiveSessionUpdate(
            .plan(
                AgentPlan(
                    entries: [
                        AgentPlanEntry(content: "Inspect workspace", priority: "high", status: "in_progress")
                    ]
                )
            )
        )

        runtime.receiveSessionUpdate(
            .plan(
                AgentPlan(
                    entries: [
                        AgentPlanEntry(content: "Inspect workspace", priority: "high", status: "completed"),
                        AgentPlanEntry(content: "Patch failing flow", priority: "high", status: "in_progress")
                    ]
                )
            )
        )

        #expect(runtime.timeline.count == 1)

        guard case .plan(let item)? = runtime.timeline.first else {
            Issue.record("Expected a plan timeline item")
            return
        }

        #expect(item.entries.count == 2)
        #expect(item.entries.map(\.content) == ["Inspect workspace", "Patch failing flow"])
        #expect(item.entries.map(\.status) == ["completed", "in_progress"])
    }

    @Test("Approval selection preserves the chosen option in timeline state")
    @MainActor
    func approvalSelectionPersists() {
        let runtime = makeRuntime()
        let requestID = ACPRequestID(rawValue: "permission-1")

        runtime.receivePermissionRequest(
            requestID: requestID,
            permissionRequest: AgentRequestPermissionRequest(
                sessionId: runtime.sessionID,
                toolCall: AgentToolCallUpdate(
                    toolCallId: "tool-approve",
                    title: "Run shell command",
                    kind: "execute",
                    status: "pending",
                    locations: nil,
                    content: nil,
                    rawInput: nil,
                    rawOutput: nil
                ),
                options: [
                    AgentPermissionOption(optionId: "allow_once", name: "Allow Once", kind: "allow_once"),
                    AgentPermissionOption(optionId: "deny", name: "Deny", kind: "deny")
                ]
            )
        )
        runtime.respondToApproval(requestID: requestID, optionID: "allow_once")

        #expect(runtime.timeline.count == 1)

        guard case .approval(let item)? = runtime.timeline.first else {
            Issue.record("Expected an approval timeline item")
            return
        }

        #expect(item.requestID == requestID)
        #expect(item.selectedOptionID == "allow_once")
        #expect(item.isResolved)
        #expect(item.options.map(\.optionId) == ["allow_once", "deny"])
    }

    @Test("Config option order is preserved and mode selection updates current mode")
    @MainActor
    func configOptionOrderIsStable() {
        let runtime = makeRuntime()

        runtime.receiveSessionUpdate(
            .configOptionUpdate([
                makeConfigOption(
                    id: "model",
                    name: "Model",
                    category: "model",
                    currentValue: "gpt-5.4",
                    values: [
                        ("gpt-5.4", "GPT-5.4"),
                        ("gpt-5.3", "GPT-5.3")
                    ]
                ),
                makeConfigOption(
                    id: "mode",
                    name: "Mode",
                    category: "mode",
                    currentValue: "build",
                    values: [
                        ("ask", "Ask"),
                        ("build", "Build")
                    ]
                ),
                makeConfigOption(
                    id: "thought_level",
                    name: "Reasoning",
                    category: "thought_level",
                    currentValue: "high",
                    values: [
                        ("medium", "Medium"),
                        ("high", "High")
                    ]
                )
            ])
        )

        #expect(runtime.configOptions.map(\.id) == ["model", "mode", "thought_level"])
        #expect(runtime.currentModeID == "build")
    }

    @Test("Selected slash commands stay structured until prompt assembly")
    @MainActor
    func selectedSlashCommandsResolveExplicitly() {
        let runtime = makeRuntime()
        let command = AgentAvailableCommand(
            name: "create_plan",
            description: "Generate a plan",
            input: AgentAvailableCommandInput(hint: "What should the plan cover?")
        )

        runtime.selectSlashCommand(command)
        runtime.updateDraft("Refactor the launch path")

        let resolution = runtime.resolvedPromptDraft(
            draft: runtime.draft,
            selectedCommand: runtime.selectedCommand
        )

        #expect(runtime.draft == "Refactor the launch path")
        #expect(runtime.selectedCommand == command)
        #expect(
            resolution == AgentPromptDraftResolution(
                text: "/create_plan Refactor the launch path",
                command: command
            )
        )
    }

    @Test("Typed slash commands resolve only against advertised command names")
    @MainActor
    func typedSlashCommandsResolveAgainstAvailableCommands() {
        let runtime = makeRuntime()
        let command = AgentAvailableCommand(
            name: "explain_changes",
            description: "Explain changes",
            input: AgentAvailableCommandInput(hint: "Optional focus area")
        )
        runtime.availableCommands = [command]

        let matching = runtime.resolvedPromptDraft(
            draft: "/explain_changes focus on tests",
            selectedCommand: nil
        )
        let unmatched = runtime.resolvedPromptDraft(
            draft: "/unknown_command focus on tests",
            selectedCommand: nil
        )

        #expect(matching?.command == command)
        #expect(matching?.text == "/explain_changes focus on tests")
        #expect(unmatched?.command == nil)
        #expect(unmatched?.text == "/unknown_command focus on tests")
    }

    @Test("Speech permission denial updates composer state explicitly")
    @MainActor
    func speechPermissionDenied() async {
        let runtime = makeRuntime()
        let speechService = FakeSpeechService(result: .failure(.permissionDenied("Speech access denied.")))

        runtime.startDictation(using: speechService)
        await waitUntil("speech permission denial") {
            if case .permissionDenied = runtime.speechState {
                return true
            }
            return false
        }

        #expect(runtime.speechState == .permissionDenied("Speech access denied."))
    }

    @Test("Unavailable transcriber updates composer state explicitly")
    @MainActor
    func speechUnavailable() async {
        let runtime = makeRuntime()
        let speechService = FakeSpeechService(result: .failure(.unavailable("No transcriber available.")))

        runtime.startDictation(using: speechService)
        await waitUntil("speech unavailable state") {
            if case .unavailable = runtime.speechState {
                return true
            }
            return false
        }

        #expect(runtime.speechState == .unavailable("No transcriber available."))
    }

    @Test("Speech transcription appends into an existing draft and settles on final text")
    @MainActor
    func speechTranscriptionAppendsToExistingDraft() async {
        let runtime = makeRuntime()
        runtime.draft = "Refactor this"
        let capture = FakeSpeechCapture()
        let speechService = FakeSpeechService(result: .success(capture))

        runtime.startDictation(using: speechService)
        await waitUntil("speech recording start") {
            runtime.speechState.isRecording
        }

        await speechService.emit(AgentComposerSpeechEvent(text: "carefully", isFinal: false))
        await waitUntil("partial transcript") {
            runtime.draft == "Refactor this carefully"
        }

        #expect(runtime.draft == "Refactor this carefully")
        #expect(runtime.speechState == .recording(partialText: "carefully"))

        await speechService.emit(AgentComposerSpeechEvent(text: "carefully and keep tests green", isFinal: true))
        await waitUntil("final transcript") {
            runtime.speechState == .idle
        }

        #expect(runtime.draft == "Refactor this carefully and keep tests green")
        #expect(runtime.speechState == .idle)
        #expect(capture.stopCallCount == 1)
    }

    @Test("Optimistic user submissions deduplicate matching adapter replay")
    @MainActor
    func optimisticUserSubmissionDeduplicatesReplay() {
        let runtime = makeRuntime()
        runtime.recordOptimisticUserSubmission(text: "Review the latest changes")

        runtime.receiveSessionUpdate(
            .userMessageChunk(
                .text(
                    AgentTextContent(text: "Review the latest changes")
                )
            )
        )

        #expect(runtime.timeline.count == 1)
        guard case .message(let item)? = runtime.timeline.first else {
            Issue.record("Expected a single optimistic user message")
            return
        }
        #expect(item.role == .user)
        #expect(item.text == "Review the latest changes")
    }

    @Test("Adapter replay can refine an optimistic user submission without duplicating it")
    @MainActor
    func optimisticUserSubmissionAdoptsReplayText() {
        let runtime = makeRuntime()
        runtime.recordOptimisticUserSubmission(text: "Review latest")

        runtime.receiveSessionUpdate(
            .userMessageChunk(
                .text(
                    AgentTextContent(text: "Review latest changes")
                )
            )
        )

        #expect(runtime.timeline.count == 1)
        guard case .message(let item)? = runtime.timeline.first else {
            Issue.record("Expected the optimistic user message to be updated in place")
            return
        }
        #expect(item.role == .user)
        #expect(item.text == "Review latest changes")
    }

    @Test("Retry restores the last submitted draft and attachments")
    @MainActor
    func retryRestoresLastSubmission() {
        let runtime = makeRuntime()
        runtime.lastSubmission = AgentSubmissionSnapshot(
            draft: "Retry this change",
            attachments: [
                .file(url: URL(fileURLWithPath: "/tmp/devys/repo/Sources/App.swift"))
            ]
        )

        runtime.retryLastSubmission()

        #expect(runtime.draft == "Retry this change")
        #expect(runtime.attachments.count == 1)
        #expect(
            runtime.attachments.first ==
                .file(url: URL(fileURLWithPath: "/tmp/devys/repo/Sources/App.swift"))
        )
    }

    @Test("Restore failure records an explicit status row")
    @MainActor
    func restoreFailureProducesStatusRow() {
        let runtime = makeRuntime()

        runtime.prepareForRestore(title: "Codex", subtitle: "Restoring")
        runtime.recordLaunchFailure("Failed to restore session: auth required.")

        #expect(runtime.launchState == .failed("Failed to restore session: auth required."))
        #expect(runtime.tabSubtitle == "Attention Required")
        guard case .status(let item)? = runtime.timeline.last else {
            Issue.record("Expected a status timeline item")
            return
        }
        #expect(item.style == .error)
        #expect(item.text == "Failed to restore session: auth required.")
    }

    @Test("Launch failures clear the connection and disable sending")
    @MainActor
    func launchFailureClearsConnectionState() {
        let runtime = makeRuntime()
        runtime.connection = makeConnection()
        runtime.draft = "Retry this prompt"

        runtime.recordLaunchFailure("Adapter terminated.")

        #expect(runtime.connection == nil)
        #expect(runtime.launchState == .failed("Adapter terminated."))
        #expect(!runtime.canSendDraft)
    }

    @MainActor
    private func makeRuntime() -> AgentSessionRuntime {
        AgentSessionRuntime(
            workspaceID: "/tmp/devys/worktrees/agents",
            sessionID: AgentSessionID(rawValue: "session-1"),
            descriptor: ACPAgentDescriptor.descriptor(for: .codex)
        )
    }

    private func makeConnection() -> ACPConnection {
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let transport = ACPTransportStdio(
            process: Process(),
            stdinHandle: stdinPipe.fileHandleForWriting,
            stdoutHandle: stdoutPipe.fileHandleForReading,
            stderrHandle: stderrPipe.fileHandleForReading
        )
        return ACPConnection(transport: transport)
    }

    private func makeConfigOption(
        id: String,
        name: String,
        category: String,
        currentValue: String,
        values: [(String, String)]
    ) -> AgentSessionConfigOption {
        AgentSessionConfigOption(
            id: id,
            name: name,
            category: category,
            type: "select",
            currentValue: currentValue,
            groups: [
                AgentSessionConfigValueGroup(
                    group: nil,
                    name: nil,
                    options: values.map { value, title in
                        AgentSessionConfigSelectValue(value: value, name: title, description: nil)
                    }
                )
            ]
        )
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for \(description)")
    }
}

// swiftlint:enable type_body_length

@MainActor
private final class FakeSpeechCapture: AgentComposerSpeechCapture {
    private(set) var stopCallCount = 0

    func stop() async {
        stopCallCount += 1
    }
}

@MainActor
private final class FakeSpeechService: AgentComposerSpeechService, @unchecked Sendable {
    enum Result {
        case success(FakeSpeechCapture)
        case failure(AgentComposerSpeechError)
    }

    private let result: Result
    private var onEvent: (@MainActor @Sendable (AgentComposerSpeechEvent) -> Void)?

    init(result: Result) {
        self.result = result
    }

    func startTranscription(
        onEvent: @escaping @MainActor @Sendable (AgentComposerSpeechEvent) -> Void
    ) async throws -> any AgentComposerSpeechCapture {
        self.onEvent = onEvent
        switch result {
        case .success(let capture):
            return capture
        case .failure(let error):
            throw error
        }
    }

    func emit(_ event: AgentComposerSpeechEvent) async {
        guard let onEvent else { return }
        onEvent(event)
    }
}
