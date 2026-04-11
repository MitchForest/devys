import Foundation

public struct ACPProtocolVersion:
    RawRepresentable,
    Codable,
    Hashable,
    Sendable,
    Comparable,
    CustomStringConvertible,
    ExpressibleByIntegerLiteral
{
    public let rawValue: Int

    public static let current: ACPProtocolVersion = 1

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: Int) {
        self.init(rawValue: value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let integer = try? container.decode(Int.self) {
            self.init(rawValue: integer)
            return
        }

        let stringValue = try container.decode(String.self)
        guard let integer = Int(stringValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ACP protocol version to decode as an integer."
            )
        }
        self.init(rawValue: integer)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        String(rawValue)
    }

    public static func < (lhs: ACPProtocolVersion, rhs: ACPProtocolVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ACPRequestID: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self.init(rawValue: stringValue)
            return
        }

        self.init(rawValue: String(try container.decode(Int.self)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue
    }
}

public struct ACPSessionID: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self.init(rawValue: stringValue)
            return
        }

        self.init(rawValue: String(try container.decode(Int.self)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue
    }
}

public struct ACPImplementationInfo: Codable, Sendable, Equatable {
    public var name: String
    public var version: String?

    public init(name: String, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

public struct ACPClientCapabilities: Codable, Sendable, Equatable {
    public var values: ACPObject

    public init(values: ACPObject = [:]) {
        self.values = values
    }

    private enum CodingKeys: String, CodingKey {
        case values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let wrappedValues = try container.decodeIfPresent(ACPObject.self, forKey: .values) {
            self.values = wrappedValues
            return
        }

        self.values = try decoder.singleValueContainer().decode(ACPObject.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    public subscript(key: String) -> ACPValue? {
        values[key]
    }

    public static func standard(
        fileSystem: ACPFileSystemCapabilities = ACPFileSystemCapabilities(),
        terminal: Bool = false
    ) -> ACPClientCapabilities {
        ACPClientCapabilities(values: [
            "fs": .object([
                "readTextFile": .bool(fileSystem.readTextFile),
                "writeTextFile": .bool(fileSystem.writeTextFile)
            ]),
            "terminal": .bool(terminal)
        ])
    }
}

public struct ACPServerCapabilities: Codable, Sendable, Equatable {
    public var values: ACPObject

    public init(values: ACPObject = [:]) {
        self.values = values
    }

    private enum CodingKeys: String, CodingKey {
        case values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let wrappedValues = try container.decodeIfPresent(ACPObject.self, forKey: .values) {
            self.values = wrappedValues
            return
        }

        self.values = try decoder.singleValueContainer().decode(ACPObject.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    public subscript(key: String) -> ACPValue? {
        values[key]
    }

    public func supports(_ capability: String) -> Bool {
        let components = capability.split(separator: ".").map(String.init)
        guard let value = value(at: components) else { return false }
        if value == .null {
            return false
        }
        if value.boolValue == false {
            return false
        }
        return true
    }

    public var promptCapabilities: ACPPromptCapabilities {
        (try? ACPValue.decode(ACPPromptCapabilities.self, from: values["promptCapabilities"]))
            ?? ACPPromptCapabilities()
    }

    public var sessionCapabilities: ACPValue? {
        values["sessionCapabilities"]
    }

    public var loadSession: Bool {
        values["loadSession"]?.boolValue ?? false
    }

    private func value(at path: [String]) -> ACPValue? {
        guard let head = path.first else { return nil }
        let initial = values[head]
        guard path.count > 1 else { return initial }

        return path.dropFirst().reduce(initial) { partial, component in
            partial?[component]
        }
    }
}

public struct ACPFileSystemCapabilities: Codable, Sendable, Equatable {
    public var readTextFile: Bool
    public var writeTextFile: Bool

    public init(
        readTextFile: Bool = false,
        writeTextFile: Bool = false
    ) {
        self.readTextFile = readTextFile
        self.writeTextFile = writeTextFile
    }
}

public struct ACPPromptCapabilities: Codable, Sendable, Equatable {
    public var audio: Bool
    public var embeddedContext: Bool
    public var image: Bool

    public init(
        audio: Bool = false,
        embeddedContext: Bool = false,
        image: Bool = false
    ) {
        self.audio = audio
        self.embeddedContext = embeddedContext
        self.image = image
    }

    private enum CodingKeys: String, CodingKey {
        case audio
        case embeddedContext
        case image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audio = try container.decodeIfPresent(Bool.self, forKey: .audio) ?? false
        embeddedContext = try container.decodeIfPresent(Bool.self, forKey: .embeddedContext) ?? false
        image = try container.decodeIfPresent(Bool.self, forKey: .image) ?? false
    }
}

public struct ACPInitializeParams: Codable, Sendable, Equatable {
    public var protocolVersion: ACPProtocolVersion
    public var clientInfo: ACPImplementationInfo?
    public var clientCapabilities: ACPClientCapabilities

    public init(
        protocolVersion: ACPProtocolVersion = ACPProtocolVersion.current,
        clientInfo: ACPImplementationInfo?,
        clientCapabilities: ACPClientCapabilities = ACPClientCapabilities()
    ) {
        self.protocolVersion = protocolVersion
        self.clientInfo = clientInfo
        self.clientCapabilities = clientCapabilities
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case clientInfo
        case clientCapabilities
        case capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decode(ACPProtocolVersion.self, forKey: .protocolVersion)
        clientInfo = try container.decodeIfPresent(ACPImplementationInfo.self, forKey: .clientInfo)
        clientCapabilities = try container.decodeIfPresent(ACPClientCapabilities.self, forKey: .clientCapabilities)
            ?? container.decodeIfPresent(ACPClientCapabilities.self, forKey: .capabilities)
            ?? ACPClientCapabilities()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encodeIfPresent(clientInfo, forKey: .clientInfo)
        try container.encode(clientCapabilities, forKey: .clientCapabilities)
    }
}

public struct ACPInitializeResult: Codable, Sendable, Equatable {
    public var protocolVersion: ACPProtocolVersion?
    public var capabilities: ACPServerCapabilities
    public var serverInfo: ACPImplementationInfo?

    public init(
        protocolVersion: ACPProtocolVersion?,
        capabilities: ACPServerCapabilities = ACPServerCapabilities(),
        serverInfo: ACPImplementationInfo? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case capabilities
        case serverInfo
        case agentCapabilities
        case agentInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decodeIfPresent(ACPProtocolVersion.self, forKey: .protocolVersion)
        capabilities = try container.decodeIfPresent(ACPServerCapabilities.self, forKey: .agentCapabilities)
            ?? container.decodeIfPresent(ACPServerCapabilities.self, forKey: .capabilities)
            ?? ACPServerCapabilities()
        serverInfo = try container.decodeIfPresent(ACPImplementationInfo.self, forKey: .agentInfo)
            ?? container.decodeIfPresent(ACPImplementationInfo.self, forKey: .serverInfo)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(protocolVersion, forKey: .protocolVersion)
        try container.encode(capabilities, forKey: .agentCapabilities)
        try container.encodeIfPresent(serverInfo, forKey: .agentInfo)
    }
}

public struct ACPNotification: Sendable, Equatable {
    public var method: String
    public var params: ACPValue?

    public init(method: String, params: ACPValue? = nil) {
        self.method = method
        self.params = params
    }
}

public struct ACPIncomingRequest: Sendable, Equatable {
    public var id: ACPRequestID
    public var method: String
    public var params: ACPValue?

    public init(
        id: ACPRequestID,
        method: String,
        params: ACPValue? = nil
    ) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct ACPRemoteError: Error, Sendable, Equatable, Codable {
    public var code: Int
    public var message: String
    public var data: ACPValue?

    public init(code: Int, message: String, data: ACPValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

extension ACPRemoteError: LocalizedError {
    public var errorDescription: String? {
        "Adapter error \(code): \(message)"
    }
}
