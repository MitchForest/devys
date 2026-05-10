// TerminalHostTransport.swift
// Devys - Local terminal host transport and socket framing.

import Foundation
import Darwin

public struct TerminalHostedSessionRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let workspaceID: String
    public let workingDirectory: URL?
    public let launchCommand: String?
    public let viewportSize: HostedTerminalViewportSize?
    public let processID: Int32?
    public let createdAt: Date

    public init(
        id: UUID,
        workspaceID: String,
        workingDirectory: URL?,
        launchCommand: String?,
        viewportSize: HostedTerminalViewportSize? = nil,
        processID: Int32? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.workingDirectory = workingDirectory
        self.launchCommand = launchCommand
        self.viewportSize = viewportSize
        self.processID = processID
        self.createdAt = createdAt
    }
}

public struct TerminalHostAttachReplayBudget: Codable, Equatable, Sendable {
    public static let defaultRecentOutputBytes = 64 * 1024
    static let retainedOutputLimitBytes = 512 * 1024

    public static let none = TerminalHostAttachReplayBudget(recentOutputBytes: 0)
    public static let hostedTerminalDefault = TerminalHostAttachReplayBudget(
        recentOutputBytes: defaultRecentOutputBytes
    )

    public let recentOutputBytes: Int

    public init(recentOutputBytes: Int) {
        self.recentOutputBytes = max(0, recentOutputBytes)
    }

    public func replayPayload(from outputBuffer: Data) -> Data {
        guard recentOutputBytes > 0 else { return Data() }
        guard outputBuffer.count > recentOutputBytes else { return outputBuffer }
        return Data(outputBuffer.suffix(recentOutputBytes))
    }
}

struct TerminalHostDaemonMetadata: Codable, Sendable, Equatable {
    let executablePath: String
    let executableFingerprint: String?

    func matches(
        executablePath: String,
        executableFingerprint: String?
    ) -> Bool {
        self.executablePath == executablePath
            && self.executableFingerprint == executableFingerprint
    }
}

func terminalHostMetadataPath(for socketPath: String) -> String {
    "\(socketPath).metadata.json"
}

func terminalHostCurrentExecutablePath() -> String? {
    if let executablePath = Bundle.main.executableURL?.path(percentEncoded: false),
       !executablePath.isEmpty {
        return executablePath
    }

    if let executablePath = CommandLine.arguments.first,
       executablePath.hasPrefix("/"),
       !executablePath.isEmpty {
        return executablePath
    }

    return nil
}

func terminalHostExecutableFingerprint(at executablePath: String) -> String? {
    let attributes = try? FileManager.default.attributesOfItem(atPath: executablePath)
    guard let attributes else { return nil }

    let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    let modifiedAt = (attributes[.modificationDate] as? Date)?
        .timeIntervalSinceReferenceDate
        ?? 0
    return "\(size)-\(modifiedAt)"
}

public enum TerminalHostControlRequest: Codable, Sendable {
    case ping
    case listSessions
    case createSession(
        id: UUID,
        workspaceID: String,
        workingDirectoryPath: String?,
        launchCommand: String?,
        initialSize: HostedTerminalViewportSize?,
        launchProfile: TerminalSessionLaunchProfile,
        persistOnDisconnect: Bool
    )
    case terminateSession(id: UUID)
    case attach(
        sessionID: UUID,
        cols: Int,
        rows: Int,
        replayBudget: TerminalHostAttachReplayBudget
    )

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
        case workspaceID
        case workingDirectoryPath
        case launchCommand
        case initialSize
        case launchProfile
        case persistOnDisconnect
        case sessionID
        case cols
        case rows
        case replayBudget
    }

    private enum Kind: String, Codable {
        case ping
        case listSessions
        case createSession
        case terminateSession
        case attach
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .ping:
            self = .ping
        case .listSessions:
            self = .listSessions
        case .createSession:
            self = .createSession(
                id: try container.decode(UUID.self, forKey: .id),
                workspaceID: try container.decode(String.self, forKey: .workspaceID),
                workingDirectoryPath: try container.decodeIfPresent(String.self, forKey: .workingDirectoryPath),
                launchCommand: try container.decodeIfPresent(String.self, forKey: .launchCommand),
                initialSize: try container.decodeIfPresent(HostedTerminalViewportSize.self, forKey: .initialSize),
                launchProfile: try container.decode(TerminalSessionLaunchProfile.self, forKey: .launchProfile),
                persistOnDisconnect: try container.decode(Bool.self, forKey: .persistOnDisconnect)
            )
        case .terminateSession:
            self = .terminateSession(id: try container.decode(UUID.self, forKey: .id))
        case .attach:
            self = .attach(
                sessionID: try container.decode(UUID.self, forKey: .sessionID),
                cols: try container.decode(Int.self, forKey: .cols),
                rows: try container.decode(Int.self, forKey: .rows),
                replayBudget: try container.decode(
                    TerminalHostAttachReplayBudget.self,
                    forKey: .replayBudget
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ping:
            try container.encode(Kind.ping, forKey: .kind)
        case .listSessions:
            try container.encode(Kind.listSessions, forKey: .kind)
        case .createSession(
            let id,
            let workspaceID,
            let workingDirectoryPath,
            let launchCommand,
            let initialSize,
            let launchProfile,
            let persistOnDisconnect
        ):
            try container.encode(Kind.createSession, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(workspaceID, forKey: .workspaceID)
            try container.encodeIfPresent(workingDirectoryPath, forKey: .workingDirectoryPath)
            try container.encodeIfPresent(launchCommand, forKey: .launchCommand)
            try container.encodeIfPresent(initialSize, forKey: .initialSize)
            try container.encode(launchProfile, forKey: .launchProfile)
            try container.encode(persistOnDisconnect, forKey: .persistOnDisconnect)
        case .terminateSession(let id):
            try container.encode(Kind.terminateSession, forKey: .kind)
            try container.encode(id, forKey: .id)
        case .attach(let sessionID, let cols, let rows, let replayBudget):
            try container.encode(Kind.attach, forKey: .kind)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(cols, forKey: .cols)
            try container.encode(rows, forKey: .rows)
            try container.encode(replayBudget, forKey: .replayBudget)
        }
    }
}
public enum TerminalHostControlResponse: Codable, Sendable {
    case pong
    case sessions([TerminalHostedSessionRecord])
    case created(TerminalHostedSessionRecord)
    case terminated
    case attached
    case failure(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case sessions
        case record
        case message
    }

    private enum Kind: String, Codable {
        case pong
        case sessions
        case created
        case terminated
        case attached
        case failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .pong:
            self = .pong
        case .sessions:
            self = .sessions(try container.decode([TerminalHostedSessionRecord].self, forKey: .sessions))
        case .created:
            self = .created(try container.decode(TerminalHostedSessionRecord.self, forKey: .record))
        case .terminated:
            self = .terminated
        case .attached:
            self = .attached
        case .failure:
            self = .failure(try container.decode(String.self, forKey: .message))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pong:
            try container.encode(Kind.pong, forKey: .kind)
        case .sessions(let sessions):
            try container.encode(Kind.sessions, forKey: .kind)
            try container.encode(sessions, forKey: .sessions)
        case .created(let record):
            try container.encode(Kind.created, forKey: .kind)
            try container.encode(record, forKey: .record)
        case .terminated:
            try container.encode(Kind.terminated, forKey: .kind)
        case .attached:
            try container.encode(Kind.attached, forKey: .kind)
        case .failure(let message):
            try container.encode(Kind.failure, forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }
}

public enum TerminalHostStreamFrameType: UInt8, Sendable {
    case input = 1
    case output = 2
    case resize = 3
    case close = 4
}

public struct TerminalHostResizeFrame: Codable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }
}

public struct TerminalHostExitFrame: Codable, Sendable {
    public let exitCode: Int?
    public let signal: String?

    public init(exitCode: Int?, signal: String?) {
        self.exitCode = exitCode
        self.signal = signal
    }
}

public enum TerminalHostSocketError: LocalizedError {
    case invalidSocketPath
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case acceptFailed(Int32)
    case readFailed(Int32)
    case writeFailed(Int32)
    case invalidResponse
    case unexpectedEOF
    case socketOptionFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidSocketPath:
            return "Invalid terminal host socket path."
        case .socketCreationFailed(let code):
            return "Could not create terminal host socket (\(code))."
        case .bindFailed(let code):
            return "Could not bind terminal host socket (\(code))."
        case .listenFailed(let code):
            return "Could not listen on terminal host socket (\(code))."
        case .connectFailed(let code):
            return "Could not connect to terminal host socket (\(code))."
        case .acceptFailed(let code):
            return "Could not accept terminal host connection (\(code))."
        case .readFailed(let code):
            return "Could not read terminal host data (\(code))."
        case .writeFailed(let code):
            return "Could not write terminal host data (\(code))."
        case .invalidResponse:
            return "The terminal host returned an invalid response."
        case .unexpectedEOF:
            return "The terminal host connection closed unexpectedly."
        case .socketOptionFailed(let code):
            return "Could not configure terminal host socket options (\(code))."
        }
    }
}
