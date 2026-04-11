// periphery:ignore:all - executable test adapter is launched out-of-process by package tests
// swiftlint:disable file_length
import ACPClientKit
import Foundation

private struct ACPInboundEnvelope: Decodable {
    let jsonrpc: String
    let id: ACPRequestID?
    let method: String?
    let params: ACPValue?
    let result: ACPValue?
    let error: ACPRemoteError?
}

private struct ACPResponseEnvelope: Encodable {
    let jsonrpc = "2.0"
    let id: ACPRequestID
    let result: ACPValue?
    let error: ACPRemoteError?
}

private struct ACPNotificationEnvelope: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: ACPValue?
}

private struct ACPRequestEnvelope: Encodable {
    let jsonrpc = "2.0"
    let id: ACPRequestID
    let method: String
    let params: ACPValue?
}

private enum Mode: String {
    case normal
    case crashOnInitialize = "crash_on_initialize"
    case unsupportedProtocol = "unsupported_protocol"
    case missingTerminalCapability = "missing_terminal_capability"
}

private let mode = Mode(
    rawValue: ProcessInfo.processInfo.environment["ACP_TEST_MODE"] ?? ""
) ?? .normal

private final class OutputWriter: @unchecked Sendable {
    private let lock = NSLock()

    func stdoutWrite<Payload: Encodable>(_ payload: Payload) {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? JSONEncoder().encode(payload) else {
            exit(23)
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    func stderrWrite(_ string: String) {
        lock.lock()
        defer { lock.unlock() }

        let data = Data(string.utf8)
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data([0x0A]))
    }
}

private actor AdapterState {
    struct SessionState: Sendable {
        var configOptions: ACPValue
        var currentModeID: String
        var promptTask: Task<Void, Never>?
    }

    private var sessions: [String: SessionState] = [:]
    private var nextSession = 1
    private var nextPermissionRequest = 1
    private var pendingPermissionContinuations: [ACPRequestID: CheckedContinuation<ACPValue?, Never>] = [:]

    func createSession() -> String {
        let sessionID = "sess-\(nextSession)"
        nextSession += 1
        sessions[sessionID] = SessionState(
            configOptions: Self.defaultConfigOptions(),
            currentModeID: "code",
            promptTask: nil
        )
        return sessionID
    }

    func configOptions(for sessionID: String) -> ACPValue {
        sessions[sessionID]?.configOptions ?? Self.defaultConfigOptions()
    }

    func currentModeID(for sessionID: String) -> String {
        sessions[sessionID]?.currentModeID ?? "code"
    }

    func updateConfigOption(
        sessionID: String,
        configID: String,
        value: String
    ) -> ACPValue {
        let current = sessions[sessionID] ?? SessionState(
            configOptions: Self.defaultConfigOptions(),
            currentModeID: "code",
            promptTask: nil
        )
        let updated = Self.updatingConfigOptions(
            current.configOptions,
            configID: configID,
            value: value
        )
        var next = current
        next.configOptions = updated
        if configID == "mode" {
            next.currentModeID = value
        }
        sessions[sessionID] = next
        return updated
    }

    func registerPromptTask(
        sessionID: String,
        task: Task<Void, Never>
    ) {
        guard var current = sessions[sessionID] else { return }
        current.promptTask?.cancel()
        current.promptTask = task
        sessions[sessionID] = current
    }

    func finishPromptTask(sessionID: String) {
        guard var current = sessions[sessionID] else { return }
        current.promptTask = nil
        sessions[sessionID] = current
    }

    func cancelPrompt(sessionID: String) {
        guard var current = sessions[sessionID] else { return }
        current.promptTask?.cancel()
        current.promptTask = nil
        sessions[sessionID] = current

        let continuations = pendingPermissionContinuations
        pendingPermissionContinuations.removeAll()
        continuations.values.forEach { continuation in
            continuation.resume(returning: .object(["outcome": .string("cancelled")]))
        }
    }

    func nextPermissionID() -> ACPRequestID {
        let id = ACPRequestID(rawValue: "perm-\(nextPermissionRequest)")
        nextPermissionRequest += 1
        return id
    }

    func waitForPermissionResponse(id: ACPRequestID) async -> ACPValue? {
        await withCheckedContinuation { continuation in
            pendingPermissionContinuations[id] = continuation
        }
    }

    func resolvePendingRequest(
        id: ACPRequestID,
        result: ACPValue?
    ) -> Bool {
        guard let continuation = pendingPermissionContinuations.removeValue(forKey: id) else {
            return false
        }
        continuation.resume(returning: result)
        return true
    }

    // swiftlint:disable:next function_body_length
    private static func defaultConfigOptions() -> ACPValue {
        .array([
            .object([
                "type": .string("select"),
                "id": .string("mode"),
                "name": .string("Mode"),
                "category": .string("mode"),
                "currentValue": .string("code"),
                "options": .array([
                    .object([
                        "value": .string("code"),
                        "name": .string("Code"),
                        "description": .string("Full coding mode")
                    ]),
                    .object([
                        "value": .string("ask"),
                        "name": .string("Ask"),
                        "description": .string("Conversation mode")
                    ])
                ])
            ]),
            .object([
                "type": .string("select"),
                "id": .string("model"),
                "name": .string("Model"),
                "category": .string("model"),
                "currentValue": .string("test-pro"),
                "options": .array([
                    .object([
                        "value": .string("test-pro"),
                        "name": .string("Test Pro")
                    ]),
                    .object([
                        "value": .string("test-fast"),
                        "name": .string("Test Fast")
                    ])
                ])
            ]),
            .object([
                "type": .string("select"),
                "id": .string("thought_level"),
                "name": .string("Reasoning"),
                "category": .string("thought_level"),
                "currentValue": .string("medium"),
                "options": .array([
                    .object([
                        "value": .string("low"),
                        "name": .string("Low")
                    ]),
                    .object([
                        "value": .string("medium"),
                        "name": .string("Medium")
                    ]),
                    .object([
                        "value": .string("high"),
                        "name": .string("High")
                    ])
                ])
            ])
        ])
    }

    private static func updatingConfigOptions(
        _ value: ACPValue,
        configID: String,
        value selectedValue: String
    ) -> ACPValue {
        guard case .array(let items) = value else { return value }
        return .array(
            items.map { item in
                guard case .object(var object) = item,
                      object["id"]?.stringValue == configID
                else {
                    return item
                }
                object["currentValue"] = .string(selectedValue)
                return .object(object)
            }
        )
    }
}

private let writer = OutputWriter()
private let state = AdapterState()

private func initializeResult(for mode: Mode) -> ACPInitializeResult {
    let capabilityValues: ACPObject = switch mode {
    case .missingTerminalCapability:
        [
            "loadSession": .bool(true),
            "promptCapabilities": .object([
                "image": .bool(true),
                "embeddedContext": .bool(true),
                "audio": .bool(false)
            ]),
            "sessionCapabilities": .object([
                "list": .object([:])
            ])
        ]
    default:
        [
            "loadSession": .bool(true),
            "promptCapabilities": .object([
                "image": .bool(true),
                "embeddedContext": .bool(true),
                "audio": .bool(false)
            ]),
            "sessionCapabilities": .object([
                "list": .object([:])
            ]),
            "terminals": .bool(true)
        ]
    }

    return ACPInitializeResult(
        protocolVersion: mode == .unsupportedProtocol ? 999 : ACPProtocolVersion.current,
        capabilities: ACPServerCapabilities(values: capabilityValues),
        serverInfo: ACPImplementationInfo(name: "ACP Test Adapter", version: "1.0.0")
    )
}

private func textFromPrompt(_ value: ACPValue?) -> String {
    guard case .array(let blocks) = value?["prompt"] else {
        return ""
    }

    return blocks.compactMap { block in
        block["text"]?.stringValue
    }
    .joined()
}

private func emitNotification(method: String, params: ACPValue?) {
    writer.stdoutWrite(
        ACPNotificationEnvelope(
            method: method,
            params: params
        )
    )
}

private func emitResponse(id: ACPRequestID, result: ACPValue?, error: ACPRemoteError? = nil) {
    writer.stdoutWrite(
        ACPResponseEnvelope(
            id: id,
            result: result,
            error: error
        )
    )
}

private func emitSessionUpdate(sessionID: String, update: ACPValue) {
    emitNotification(
        method: "session/update",
        params: .object([
            "sessionId": .string(sessionID),
            "update": update
        ])
    )
}

private func emitPermissionRequest(
    sessionID: String,
    toolCallID: String
) async -> ACPValue? {
    let permissionID = await state.nextPermissionID()
    writer.stdoutWrite(
        ACPRequestEnvelope(
            id: permissionID,
            method: "session/request_permission",
            params: .object([
                "sessionId": .string(sessionID),
                "toolCall": .object([
                    "toolCallId": .string(toolCallID),
                    "title": .string("Apply generated diff"),
                    "status": .string("pending")
                ]),
                "options": .array([
                    .object([
                        "optionId": .string("allow_once"),
                        "name": .string("Allow Once"),
                        "kind": .string("allow_once")
                    ]),
                    .object([
                        "optionId": .string("reject_once"),
                        "name": .string("Reject"),
                        "kind": .string("reject_once")
                    ])
                ])
            ])
        )
    )
    return await state.waitForPermissionResponse(id: permissionID)
}

// swiftlint:disable:next function_body_length
private func handlePrompt(
    requestID: ACPRequestID,
    params: ACPValue?
) {
    let sessionID = params?["sessionId"]?.stringValue ?? "unknown"
    let promptText = textFromPrompt(params)

    let task = Task<Void, Never> {
        defer {
            Task {
                await state.finishPromptTask(sessionID: sessionID)
            }
        }

        do {
            emitSessionUpdate(
                sessionID: sessionID,
                update: .object([
                    "sessionUpdate": .string("user_message_chunk"),
                    "content": .object([
                        "type": .string("text"),
                        "text": .string(promptText)
                    ])
                ])
            )
            emitSessionUpdate(
                sessionID: sessionID,
                update: .object([
                    "sessionUpdate": .string("session_info_update"),
                    "title": .string("Specimen Session")
                ])
            )

            let configOptions = await state.configOptions(for: sessionID)
            emitSessionUpdate(
                sessionID: sessionID,
                update: .object([
                    "sessionUpdate": .string("config_option_update"),
                    "configOptions": configOptions
                ])
            )
            emitSessionUpdate(
                sessionID: sessionID,
                update: .object([
                    "sessionUpdate": .string("available_commands_update"),
                    "availableCommands": .array([
                        .object([
                            "name": .string("create_plan"),
                            "description": .string("Generate an execution plan")
                        ]),
                        .object([
                            "name": .string("explain_changes"),
                            "description": .string("Explain the current working changes"),
                            "input": .object([
                                "hint": .string("Optional focus area")
                            ])
                        ])
                    ])
                ])
            )

            try await Task.sleep(nanoseconds: 30_000_000)
            try Task.checkCancellation()

            emitSessionUpdate(
                sessionID: sessionID,
                update: .object([
                    "sessionUpdate": .string("agent_message_chunk"),
                    "content": .object([
                        "type": .string("text"),
                        "text": .string("Inspecting the workspace and preparing a response.\n")
                    ])
                ])
            )
            emitSessionUpdate(
                sessionID: sessionID,
                update: .object([
                    "sessionUpdate": .string("plan"),
                    "entries": .array([
                        .object([
                            "content": .string("Inspect the relevant files"),
                            "priority": .string("high"),
                            "status": .string("completed")
                        ]),
                        .object([
                            "content": .string("Apply the requested update"),
                            "priority": .string("high"),
                            "status": .string("in_progress")
                        ]),
                        .object([
                            "content": .string("Verify the result"),
                            "priority": .string("medium"),
                            "status": .string("pending")
                        ])
                    ])
                ])
            )

            let toolCallID = "tool-1"
            emitSessionUpdate(
                sessionID: sessionID,
                update: .object([
                    "sessionUpdate": .string("tool_call"),
                    "toolCallId": .string(toolCallID),
                    "title": .string("Editing AgentSurface.swift"),
                    "kind": .string("edit"),
                    "status": .string("in_progress"),
                    "locations": .array([
                        .object([
                            "path": .string("Sources/App/AgentSurface.swift"),
                            "line": .integer(42)
                        ])
                    ])
                ])
            )

            if promptText.localizedCaseInsensitiveContains("approve") {
                let permissionResponse = await emitPermissionRequest(
                    sessionID: sessionID,
                    toolCallID: toolCallID
                )
                let selectedOption = permissionResponse?["outcome"]?["optionId"]?.stringValue
                    ?? permissionResponse?["optionId"]?.stringValue
                    ?? permissionResponse?["outcome"]?.stringValue

                emitSessionUpdate(
                    sessionID: sessionID,
                    update: .object([
                        "sessionUpdate": .string("tool_call_update"),
                        "toolCallId": .string(toolCallID),
                        "status": .string(selectedOption == "reject_once" ? "failed" : "completed"),
                        "title": .string(selectedOption == "reject_once" ? "Edit rejected" : "Edit approved"),
                        "content": .array([
                            .object([
                                "type": .string("diff"),
                                "path": .string("Sources/App/AgentSurface.swift"),
                                "oldText": .string("old value"),
                                "newText": .string("new value")
                            ])
                        ])
                    ])
                )
            } else {
                emitSessionUpdate(
                    sessionID: sessionID,
                    update: .object([
                        "sessionUpdate": .string("tool_call_update"),
                        "toolCallId": .string(toolCallID),
                        "status": .string("completed"),
                        "content": .array([
                            .object([
                                "type": .string("diff"),
                                "path": .string("Sources/App/AgentSurface.swift"),
                                "oldText": .string("let title = \"Old\""),
                                "newText": .string("let title = \"New\"")
                            ]),
                            .object([
                                "type": .string("content"),
                                "content": .object([
                                    "type": .string("text"),
                                    "text": .string("Updated the surface title and supporting layout.")
                                ])
                            ])
                        ])
                    ])
                )
            }

            try await Task.sleep(nanoseconds: 30_000_000)
            try Task.checkCancellation()

            emitSessionUpdate(
                sessionID: sessionID,
                update: .object([
                    "sessionUpdate": .string("agent_message_chunk"),
                    "content": .object([
                        "type": .string("text"),
                        "text": .string("Completed the requested operation for: \(promptText)")
                    ])
                ])
            )

            emitResponse(
                id: requestID,
                result: .object([
                    "stopReason": .string("end_turn")
                ])
            )
        } catch {
            emitResponse(
                id: requestID,
                result: .object([
                    "stopReason": .string("cancelled")
                ])
            )
        }
    }

    Task {
        await state.registerPromptTask(sessionID: sessionID, task: task)
    }
}

@main
struct ACPClientKitTestAdapterMain {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func main() async throws {
        while let line = readLine() {
            let data = Data(line.utf8)
            let envelope = try JSONDecoder().decode(ACPInboundEnvelope.self, from: data)

            guard envelope.jsonrpc == "2.0" else {
                exit(22)
            }

            if envelope.method == nil,
               let responseID = envelope.id,
               await state.resolvePendingRequest(id: responseID, result: envelope.result) {
                continue
            }

            guard let method = envelope.method else {
                exit(22)
            }

            let requestID = envelope.id

            switch method {
            case "initialize":
                if mode == .crashOnInitialize {
                    exit(91)
                }
                guard let requestID else {
                    exit(24)
                }

                emitResponse(
                    id: requestID,
                    result: try ACPValue.encode(initializeResult(for: mode))
                )
                emitNotification(
                    method: "acp/test_notification",
                    params: .object([
                        "phase": .string("initialized")
                    ])
                )
                writer.stderrWrite("adapter: initialize complete")

            case "echo":
                guard let requestID else {
                    exit(24)
                }
                emitResponse(
                    id: requestID,
                    result: envelope.params
                )

            case "delayed_echo":
                let delayMS = envelope.params?["delay_ms"]?.integerValue ?? 0
                usleep(useconds_t(max(delayMS, 0) * 1_000))
                guard let requestID else {
                    exit(24)
                }
                emitResponse(
                    id: requestID,
                    result: envelope.params?["value"]
                )

            case "emit_permission_request":
                guard let requestID else {
                    exit(24)
                }
                let sessionID = envelope.params?["sessionId"]?.stringValue ?? "sess-probe"
                writer.stdoutWrite(
                    ACPRequestEnvelope(
                        id: ACPRequestID(rawValue: "perm-probe"),
                        method: "session/request_permission",
                        params: .object([
                            "sessionId": .string(sessionID),
                            "toolCall": .object([
                                "toolCallId": .string("probe-tool"),
                                "title": .string("Probe permission request"),
                                "status": .string("pending")
                            ]),
                            "options": .array([
                                .object([
                                    "optionId": .string("allow_once"),
                                    "name": .string("Allow Once"),
                                    "kind": .string("allow_once")
                                ]),
                                .object([
                                    "optionId": .string("reject_once"),
                                    "name": .string("Reject"),
                                    "kind": .string("reject_once")
                                ])
                            ])
                        ])
                    )
                )
                emitResponse(id: requestID, result: .null)

            case "session/new":
                guard let requestID else {
                    exit(24)
                }
                let sessionID = await state.createSession()
                let configOptions = await state.configOptions(for: sessionID)
                let currentModeID = await state.currentModeID(for: sessionID)
                emitResponse(
                    id: requestID,
                    result: .object([
                        "sessionId": .string(sessionID),
                        "configOptions": configOptions,
                        "modes": .object([
                            "currentModeId": .string(currentModeID),
                            "availableModes": .array([
                                .object([
                                    "id": .string("code"),
                                    "name": .string("Code"),
                                    "description": .string("Full coding mode")
                                ]),
                                .object([
                                    "id": .string("ask"),
                                    "name": .string("Ask"),
                                    "description": .string("Conversation mode")
                                ])
                            ])
                        ])
                    ])
                )

            case "session/prompt":
                guard let requestID else {
                    exit(24)
                }
                handlePrompt(requestID: requestID, params: envelope.params)

            case "session/cancel":
                if let sessionID = envelope.params?["sessionId"]?.stringValue {
                    await state.cancelPrompt(sessionID: sessionID)
                }

            case "session/set_config_option":
                guard let requestID else {
                    exit(24)
                }
                let sessionID = envelope.params?["sessionId"]?.stringValue ?? "sess-1"
                let configID = envelope.params?["configId"]?.stringValue ?? ""
                let value = envelope.params?["value"]?.stringValue ?? ""
                let configOptions = await state.updateConfigOption(
                    sessionID: sessionID,
                    configID: configID,
                    value: value
                )
                emitResponse(
                    id: requestID,
                    result: .object([
                        "configOptions": configOptions
                    ])
                )
                emitSessionUpdate(
                    sessionID: sessionID,
                    update: .object([
                        "sessionUpdate": .string("config_option_update"),
                        "configOptions": configOptions
                    ])
                )
                if configID == "mode" {
                    emitSessionUpdate(
                        sessionID: sessionID,
                        update: .object([
                            "sessionUpdate": .string("current_mode_update"),
                            "currentModeId": .string(value)
                        ])
                    )
                }

            case "crash_after_request":
                exit(92)

            default:
                guard let requestID else {
                    exit(24)
                }
                emitResponse(
                    id: requestID,
                    result: nil,
                    error: ACPRemoteError(
                        code: -32601,
                        message: "Method not found",
                        data: .string(method)
                    )
                )
            }
        }
    }
}
