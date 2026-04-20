// periphery:ignore:all - ACP wire models are retained for Codable protocol compatibility and UI state mapping.
// swiftlint:disable file_length
import ACPClientKit
import AppFeatures
import Foundation

protocol AgentSessionScopedRequest {
    var sessionId: ChatSessionID { get }
}

struct AgentSessionNewRequest: Codable, Sendable {
    var cwd: String
    var mcpServers: [ACPValue]

    init(
        cwd: String,
        mcpServers: [ACPValue] = []
    ) {
        self.cwd = cwd
        self.mcpServers = mcpServers
    }
}

struct AgentSessionNewResponse: Decodable, Sendable, Equatable {
    var sessionId: ChatSessionID
    var configOptions: [AgentSessionConfigOption]?
    var modes: AgentSessionModeState?

    private enum CodingKeys: String, CodingKey {
        case sessionId
        case configOptions
        case options
        case modes
        case currentModeId
        case availableModes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(ChatSessionID.self, forKey: .sessionId)
        configOptions = try container.decodeIfPresent([AgentSessionConfigOption].self, forKey: .configOptions)
            ?? container.decodeIfPresent([AgentSessionConfigOption].self, forKey: .options)
        modes = try container.decodeIfPresent(AgentSessionModeState.self, forKey: .modes)
            ?? AgentSessionModeState.makeLegacyIfPresent(
                currentModeId: try decodeFlexibleStringIfPresent(forKey: .currentModeId, in: container),
                availableModes: try container.decodeIfPresent([AgentSessionMode].self, forKey: .availableModes)
            )
    }
}

struct AgentSessionLoadRequest: Codable, Sendable {
    var sessionId: ChatSessionID
    var cwd: String
    var mcpServers: [ACPValue]

    init(
        sessionId: ChatSessionID,
        cwd: String,
        mcpServers: [ACPValue] = []
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.mcpServers = mcpServers
    }
}

struct AgentSessionLoadResponse: Decodable, Sendable, Equatable {
    var sessionId: ChatSessionID
    var configOptions: [AgentSessionConfigOption]?
    var modes: AgentSessionModeState?

    private enum CodingKeys: String, CodingKey {
        case sessionId
        case configOptions
        case options
        case modes
        case currentModeId
        case availableModes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(ChatSessionID.self, forKey: .sessionId)
        configOptions = try container.decodeIfPresent([AgentSessionConfigOption].self, forKey: .configOptions)
            ?? container.decodeIfPresent([AgentSessionConfigOption].self, forKey: .options)
        modes = try container.decodeIfPresent(AgentSessionModeState.self, forKey: .modes)
            ?? AgentSessionModeState.makeLegacyIfPresent(
                currentModeId: try decodeFlexibleStringIfPresent(forKey: .currentModeId, in: container),
                availableModes: try container.decodeIfPresent([AgentSessionMode].self, forKey: .availableModes)
            )
    }
}

struct AgentPromptRequest: Codable, Sendable {
    var sessionId: ChatSessionID
    var prompt: [AgentContentBlock]
}

struct AgentPromptResponse: Codable, Sendable, Equatable {
    var stopReason: String
}

struct AgentSessionNotification: Decodable, Sendable, Equatable {
    var sessionId: ChatSessionID
    var update: AgentSessionUpdate
}

enum AgentSessionUpdate: Decodable, Sendable, Equatable {
    case userMessageChunk(AgentContentBlock)
    case assistantMessageChunk(AgentContentBlock)
    case agentThoughtChunk(AgentContentBlock)
    case toolCall(AgentToolCall)
    case toolCallUpdate(AgentToolCallUpdate)
    case plan(AgentPlan)
    case availableCommandsUpdate([AgentAvailableCommand])
    case currentModeUpdate(String)
    case configOptionUpdate([AgentSessionConfigOption])
    case sessionInfoUpdate(AgentSessionInfoUpdate)

    private enum CodingKeys: String, CodingKey {
        case sessionUpdate
        case content
        case availableCommands
        case currentModeId
        case configOptions
        case title
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .sessionUpdate) {
        case "user_message_chunk":
            self = .userMessageChunk(try container.decode(AgentContentBlock.self, forKey: .content))
        case "agent_message_chunk":
            self = .assistantMessageChunk(try container.decode(AgentContentBlock.self, forKey: .content))
        case "agent_thought_chunk":
            self = .agentThoughtChunk(try container.decode(AgentContentBlock.self, forKey: .content))
        case "tool_call":
            self = .toolCall(try AgentToolCall(from: decoder))
        case "tool_call_update":
            self = .toolCallUpdate(try AgentToolCallUpdate(from: decoder))
        case "plan":
            self = .plan(try AgentPlan(from: decoder))
        case "available_commands_update":
            self = .availableCommandsUpdate(
                try container.decode([AgentAvailableCommand].self, forKey: .availableCommands)
            )
        case "current_mode_update":
            self = .currentModeUpdate(try container.decode(String.self, forKey: .currentModeId))
        case "config_option_update":
            self = .configOptionUpdate(
                try container.decode([AgentSessionConfigOption].self, forKey: .configOptions)
            )
        case "session_info_update":
            self = .sessionInfoUpdate(try AgentSessionInfoUpdate(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .sessionUpdate,
                in: container,
                debugDescription: "Unsupported session update."
            )
        }
    }
}

enum AgentContentBlock: Codable, Sendable, Equatable {
    case text(AgentTextContent)
    case image(AgentImageContent)
    case resourceLink(AgentResourceLink)
    case resource(AgentEmbeddedResource)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "text":
            self = .text(try AgentTextContent(from: decoder))
        case "image":
            self = .image(try AgentImageContent(from: decoder))
        case "resource_link":
            self = .resourceLink(try AgentResourceLink(from: decoder))
        case "resource":
            self = .resource(try AgentEmbeddedResource(from: decoder))
        default:
            self = .unknown(type: (try? container.decode(String.self, forKey: .type)) ?? "unknown")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .resourceLink(let content):
            try content.encode(to: encoder)
        case .resource(let content):
            try content.encode(to: encoder)
        case .unknown(let type):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
        }
    }

    var plainText: String {
        switch self {
        case .text(let content):
            content.text
        case .image(let content):
            "[Image: \(content.mimeType)]"
        case .resourceLink(let content):
            "[Resource: \(content.title ?? content.name)]"
        case .resource(let content):
            content.plainText
        case .unknown(let type):
            "[\(type)]"
        }
    }
}

struct AgentTextContent: Codable, Sendable, Equatable {
    var type: String = "text"
    var text: String
}

struct AgentImageContent: Codable, Sendable, Equatable {
    var type: String = "image"
    var mimeType: String
    var data: String?
}

struct AgentResourceLink: Codable, Sendable, Equatable {
    var type: String = "resource_link"
    var name: String
    var title: String?
    var uri: String?
    var mimeType: String?
}

struct AgentEmbeddedResource: Codable, Sendable, Equatable {
    struct Resource: Codable, Sendable, Equatable {
        var uri: String
        var text: String?
        var blob: String?
        var mimeType: String?
    }

    var type: String = "resource"
    var resource: Resource

    var plainText: String {
        if let text = resource.text {
            return text
        }
        return "[Embedded resource: \(resource.uri)]"
    }
}

struct AgentToolCall: Decodable, Sendable, Equatable {
    var toolCallId: String
    var title: String
    var kind: String?
    var status: String?
    var locations: [AgentToolCallLocation]
    var content: [AgentToolCallContent]
    var rawInput: ACPValue?
    var rawOutput: ACPValue?

    init(
        toolCallId: String,
        title: String,
        kind: String? = nil,
        status: String? = nil,
        locations: [AgentToolCallLocation] = [],
        content: [AgentToolCallContent] = [],
        rawInput: ACPValue? = nil,
        rawOutput: ACPValue? = nil
    ) {
        self.toolCallId = toolCallId
        self.title = title
        self.kind = kind
        self.status = status
        self.locations = locations
        self.content = content
        self.rawInput = rawInput
        self.rawOutput = rawOutput
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        locations = try container.decodeIfPresent([AgentToolCallLocation].self, forKey: .locations) ?? []
        content = try container.decodeIfPresent([AgentToolCallContent].self, forKey: .content) ?? []
        rawInput = try container.decodeIfPresent(ACPValue.self, forKey: .rawInput)
        rawOutput = try container.decodeIfPresent(ACPValue.self, forKey: .rawOutput)
    }

    private enum CodingKeys: String, CodingKey {
        case toolCallId
        case title
        case kind
        case status
        case locations
        case content
        case rawInput
        case rawOutput
    }
}

struct AgentToolCallUpdate: Decodable, Sendable, Equatable {
    var toolCallId: String
    var title: String?
    var kind: String?
    var status: String?
    var locations: [AgentToolCallLocation]?
    var content: [AgentToolCallContent]?
    var rawInput: ACPValue?
    var rawOutput: ACPValue?
}

struct AgentToolCallLocation: Codable, Sendable, Equatable, Hashable {
    var path: String
    var line: Int?
}

enum AgentToolCallContent: Decodable, Sendable, Equatable {
    case content(AgentContentBlock)
    case diff(AgentDiffContent)
    case terminal(AgentTerminalReference)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "content":
            self = .content(try AgentContentWrapper(from: decoder).content)
        case "diff":
            self = .diff(try AgentDiffContent(from: decoder))
        case "terminal":
            self = .terminal(try AgentTerminalReference(from: decoder))
        default:
            self = .unknown(type: (try? container.decode(String.self, forKey: .type)) ?? "unknown")
        }
    }
}

struct AgentContentWrapper: Codable, Sendable, Equatable {
    var type: String = "content"
    var content: AgentContentBlock
}

struct AgentDiffContent: Codable, Sendable, Equatable {
    var type: String = "diff"
    var path: String
    var oldText: String?
    var newText: String
}

struct AgentTerminalReference: Codable, Sendable, Equatable {
    var type: String = "terminal"
    var terminalId: String
}

struct AgentPlan: Decodable, Sendable, Equatable {
    var entries: [AgentPlanEntry]
}

struct AgentPlanEntry: Codable, Sendable, Equatable {
    var content: String
    var priority: String
    var status: String
}

struct AgentAvailableCommand: Codable, Sendable, Equatable, Identifiable {
    var name: String
    var description: String
    var input: AgentAvailableCommandInput?

    var id: String {
        name
    }
}

struct AgentAvailableCommandInput: Codable, Sendable, Equatable {
    var hint: String?

    private enum CodingKeys: String, CodingKey {
        case hint
        case placeholder
        case description
    }

    init(hint: String?) {
        self.hint = hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hint = try decodeFlexibleStringIfPresent(forKey: .hint, in: container)
            ?? decodeFlexibleStringIfPresent(forKey: .placeholder, in: container)
            ?? decodeFlexibleStringIfPresent(forKey: .description, in: container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(hint, forKey: .hint)
    }
}

struct AgentSessionInfoUpdate: Codable, Sendable, Equatable {
    var title: String?
    var updatedAt: String?
}

struct AgentSessionModeState: Codable, Sendable, Equatable {
    var currentModeId: String
    var availableModes: [AgentSessionMode]

    private enum CodingKeys: String, CodingKey {
        case currentModeId
        case availableModes
    }

    private init(
        currentModeId: String?,
        availableModes: [AgentSessionMode]?
    ) {
        guard let currentModeId else {
            self.currentModeId = ""
            self.availableModes = []
            return
        }
        self.currentModeId = currentModeId
        self.availableModes = availableModes ?? []
    }

    static func makeLegacyIfPresent(
        currentModeId: String?,
        availableModes: [AgentSessionMode]?
    ) -> AgentSessionModeState? {
        guard currentModeId != nil else {
            return nil
        }
        return AgentSessionModeState(
            currentModeId: currentModeId,
            availableModes: availableModes
        )
    }
}

struct AgentSessionMode: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var description: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
    }

    init(
        id: String,
        name: String,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try decodeFlexibleString(forKey: .id, in: container)
        name = try decodeFlexibleString(forKey: .name, in: container)
        description = try decodeFlexibleStringIfPresent(forKey: .description, in: container)
    }
}

struct AgentSessionConfigOption: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var category: String?
    var type: String
    var currentValue: String
    var groups: [AgentSessionConfigValueGroup]

    var allValues: [AgentSessionConfigSelectValue] {
        groups.flatMap(\.options)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case category
        case type
        case currentValue
        case options
    }

    init(
        id: String,
        name: String,
        description: String? = nil,
        category: String? = nil,
        type: String,
        currentValue: String,
        groups: [AgentSessionConfigValueGroup]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.type = type
        self.currentValue = currentValue
        self.groups = groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try decodeFlexibleString(forKey: .id, in: container)
        name = try decodeFlexibleString(forKey: .name, in: container)
        description = try decodeFlexibleStringIfPresent(forKey: .description, in: container)
        category = try decodeFlexibleStringIfPresent(forKey: .category, in: container)
        type = try decodeFlexibleString(forKey: .type, in: container)
        currentValue = try decodeFlexibleString(forKey: .currentValue, in: container)

        if let flatValues = try? container.decode([AgentSessionConfigSelectValue].self, forKey: .options) {
            groups = [AgentSessionConfigValueGroup(group: nil, name: nil, options: flatValues)]
        } else if let groupedValues = try? container.decode([AgentSessionConfigValueGroup].self, forKey: .options) {
            groups = groupedValues
        } else {
            groups = []
        }
    }
}

struct AgentSessionConfigValueGroup: Codable, Sendable, Equatable, Identifiable {
    var group: String?
    var name: String?
    var options: [AgentSessionConfigSelectValue]

    var id: String {
        if let group {
            return group
        }
        if let name {
            return name
        }
        return options.map(\.value).joined(separator: "|")
    }
}

struct AgentSessionConfigSelectValue: Codable, Sendable, Equatable, Identifiable {
    var value: String
    var name: String
    var description: String?

    var id: String {
        value
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case name
        case description
    }

    init(
        value: String,
        name: String,
        description: String? = nil
    ) {
        self.value = value
        self.name = name
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try decodeFlexibleString(forKey: .value, in: container)
        name = try decodeFlexibleStringIfPresent(forKey: .name, in: container) ?? value
        description = try decodeFlexibleStringIfPresent(forKey: .description, in: container)
    }
}

private func decodeFlexibleString<Key: CodingKey>(
    forKey key: Key,
    in container: KeyedDecodingContainer<Key>
) throws -> String {
    if let value = try decodeFlexibleStringIfPresent(forKey: key, in: container) {
        return value
    }

    throw DecodingError.keyNotFound(
        key,
        DecodingError.Context(
            codingPath: container.codingPath,
            debugDescription: "Expected a string-compatible value."
        )
    )
}

private func decodeFlexibleStringIfPresent<Key: CodingKey>(
    forKey key: Key,
    in container: KeyedDecodingContainer<Key>
) throws -> String? {
    if let value = try container.decodeIfPresent(String.self, forKey: key) {
        return value
    }
    if let value = try container.decodeIfPresent(Int.self, forKey: key) {
        return String(value)
    }
    if let value = try container.decodeIfPresent(Double.self, forKey: key) {
        return String(value)
    }
    if let value = try container.decodeIfPresent(Bool.self, forKey: key) {
        return value ? "true" : "false"
    }
    return nil
}

struct AgentRequestPermissionRequest: Decodable, Sendable, Equatable, AgentSessionScopedRequest {
    var sessionId: ChatSessionID
    var toolCall: AgentToolCallUpdate
    var options: [AgentPermissionOption]
}

struct AgentPermissionOption: Codable, Sendable, Equatable, Identifiable {
    var optionId: String
    var name: String
    var kind: String

    var id: String {
        optionId
    }
}

struct AgentRequestPermissionResponse: Codable, Sendable, Equatable {
    var outcome: AgentRequestPermissionOutcome
}

struct AgentReadTextFileRequest: Codable, Sendable, Equatable, AgentSessionScopedRequest {
    var sessionId: ChatSessionID
    var path: String
    var line: Int?
    var limit: Int?
}

struct AgentReadTextFileResponse: Codable, Sendable, Equatable {
    var content: String
}

struct AgentWriteTextFileRequest: Codable, Sendable, Equatable, AgentSessionScopedRequest {
    var sessionId: ChatSessionID
    var path: String
    var content: String
}

struct AgentTerminalEnvironmentVariable: Codable, Sendable, Equatable {
    var name: String
    var value: String
}

struct AgentCreateTerminalRequest: Codable, Sendable, Equatable, AgentSessionScopedRequest {
    var sessionId: ChatSessionID
    var command: String
    var args: [String]
    var env: [AgentTerminalEnvironmentVariable]
    var cwd: String?
    var outputByteLimit: Int?

    init(
        sessionId: ChatSessionID,
        command: String,
        args: [String] = [],
        env: [AgentTerminalEnvironmentVariable] = [],
        cwd: String? = nil,
        outputByteLimit: Int? = nil
    ) {
        self.sessionId = sessionId
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.outputByteLimit = outputByteLimit
    }
}

struct AgentCreateTerminalResponse: Codable, Sendable, Equatable {
    var terminalId: String
}

struct AgentTerminalOutputRequest: Codable, Sendable, Equatable, AgentSessionScopedRequest {
    var sessionId: ChatSessionID
    var terminalId: String
}

struct AgentTerminalExitStatus: Codable, Sendable, Equatable {
    var exitCode: Int?
    var signal: String?
}

struct AgentTerminalOutputResponse: Codable, Sendable, Equatable {
    var output: String
    var truncated: Bool
    var exitStatus: AgentTerminalExitStatus?
}

struct AgentWaitForTerminalExitRequest: Codable, Sendable, Equatable, AgentSessionScopedRequest {
    var sessionId: ChatSessionID
    var terminalId: String
}

struct AgentWaitForTerminalExitResponse: Codable, Sendable, Equatable {
    var exitCode: Int?
    var signal: String?
}

struct AgentKillTerminalRequest: Codable, Sendable, Equatable, AgentSessionScopedRequest {
    var sessionId: ChatSessionID
    var terminalId: String
}

struct AgentReleaseTerminalRequest: Codable, Sendable, Equatable, AgentSessionScopedRequest {
    var sessionId: ChatSessionID
    var terminalId: String
}

enum AgentRequestPermissionOutcome: Codable, Sendable, Equatable {
    case cancelled
    case selected(optionId: String)

    private enum CodingKeys: String, CodingKey {
        case outcome
        case optionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .outcome) {
        case "cancelled":
            self = .cancelled
        case "selected":
            self = .selected(optionId: try container.decode(String.self, forKey: .optionId))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .outcome,
                in: container,
                debugDescription: "Unsupported permission outcome."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cancelled:
            try container.encode("cancelled", forKey: .outcome)
        case .selected(let optionId):
            try container.encode("selected", forKey: .outcome)
            try container.encode(optionId, forKey: .optionId)
        }
    }
}
