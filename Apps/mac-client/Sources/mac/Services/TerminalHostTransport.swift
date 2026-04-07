// TerminalHostTransport.swift
// Devys - Local terminal host transport and socket framing.

import Foundation
import Darwin

enum TerminalHostControlRequest: Codable, Sendable {
    case ping
    case listSessions
    case createSession(
        id: UUID,
        workspaceID: String,
        workingDirectoryPath: String?,
        launchCommand: String?
    )
    case terminateSession(id: UUID)
    case attach(sessionID: UUID, cols: Int, rows: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
        case workspaceID
        case workingDirectoryPath
        case launchCommand
        case sessionID
        case cols
        case rows
    }

    private enum Kind: String, Codable {
        case ping
        case listSessions
        case createSession
        case terminateSession
        case attach
    }

    init(from decoder: Decoder) throws {
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
                launchCommand: try container.decodeIfPresent(String.self, forKey: .launchCommand)
            )
        case .terminateSession:
            self = .terminateSession(id: try container.decode(UUID.self, forKey: .id))
        case .attach:
            self = .attach(
                sessionID: try container.decode(UUID.self, forKey: .sessionID),
                cols: try container.decode(Int.self, forKey: .cols),
                rows: try container.decode(Int.self, forKey: .rows)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ping:
            try container.encode(Kind.ping, forKey: .kind)
        case .listSessions:
            try container.encode(Kind.listSessions, forKey: .kind)
        case .createSession(let id, let workspaceID, let workingDirectoryPath, let launchCommand):
            try container.encode(Kind.createSession, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(workspaceID, forKey: .workspaceID)
            try container.encodeIfPresent(workingDirectoryPath, forKey: .workingDirectoryPath)
            try container.encodeIfPresent(launchCommand, forKey: .launchCommand)
        case .terminateSession(let id):
            try container.encode(Kind.terminateSession, forKey: .kind)
            try container.encode(id, forKey: .id)
        case .attach(let sessionID, let cols, let rows):
            try container.encode(Kind.attach, forKey: .kind)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(cols, forKey: .cols)
            try container.encode(rows, forKey: .rows)
        }
    }
}
enum TerminalHostControlResponse: Codable, Sendable {
    case pong
    case sessions([HostedTerminalSessionRecord])
    case created(HostedTerminalSessionRecord)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .pong:
            self = .pong
        case .sessions:
            self = .sessions(try container.decode([HostedTerminalSessionRecord].self, forKey: .sessions))
        case .created:
            self = .created(try container.decode(HostedTerminalSessionRecord.self, forKey: .record))
        case .terminated:
            self = .terminated
        case .attached:
            self = .attached
        case .failure:
            self = .failure(try container.decode(String.self, forKey: .message))
        }
    }

    func encode(to encoder: Encoder) throws {
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

enum TerminalHostStreamFrameType: UInt8 {
    case input = 1
    case output = 2
    case resize = 3
    case close = 4
}

struct TerminalHostResizeFrame: Codable, Sendable {
    let cols: Int
    let rows: Int
}

enum TerminalHostSocketError: LocalizedError {
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

    var errorDescription: String? {
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
        }
    }
}

enum TerminalHostSocketIO {
    static func makeSocketAddress(for path: String) throws -> sockaddr_un {
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw TerminalHostSocketError.invalidSocketPath
        }

        var address = sockaddr_un()
        #if os(macOS)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutablePointer(to: &address.sun_path.0) { pointer in
            for (index, byte) in bytes.enumerated() {
                pointer.advanced(by: index).pointee = Int8(bitPattern: byte)
            }
            pointer.advanced(by: bytes.count).pointee = 0
        }
        return address
    }

    static func connect(to socketPath: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw TerminalHostSocketError.socketCreationFailed(errno)
        }

        do {
            var address = try makeSocketAddress(for: socketPath)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else {
                let code = errno
                Darwin.close(fd)
                throw TerminalHostSocketError.connectFailed(code)
            }
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    static func bindAndListen(at socketPath: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw TerminalHostSocketError.socketCreationFailed(errno)
        }

        unlink(socketPath)

        do {
            var address = try makeSocketAddress(for: socketPath)
            let bindResult = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindResult == 0 else {
                let code = errno
                Darwin.close(fd)
                throw TerminalHostSocketError.bindFailed(code)
            }
            guard listen(fd, SOMAXCONN) == 0 else {
                let code = errno
                Darwin.close(fd)
                throw TerminalHostSocketError.listenFailed(code)
            }
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    static func accept(on listenerFD: Int32) throws -> Int32 {
        let fd = Darwin.accept(listenerFD, nil, nil)
        guard fd >= 0 else {
            throw TerminalHostSocketError.acceptFailed(errno)
        }
        return fd
    }

    static func readLine(from fileHandle: FileHandle) throws -> Data {
        var buffer = Data()
        while true {
            let chunk = try fileHandle.read(upToCount: 1) ?? Data()
            if chunk.isEmpty {
                if buffer.isEmpty {
                    throw TerminalHostSocketError.unexpectedEOF
                }
                return buffer
            }
            if chunk[chunk.startIndex] == 0x0A {
                return buffer
            }
            buffer.append(chunk)
        }
    }

    static func writeLine(_ data: Data, to fileHandle: FileHandle) throws {
        try fileHandle.write(contentsOf: data + Data([0x0A]))
    }

    static func writeFrame(
        type: TerminalHostStreamFrameType,
        payload: Data,
        to fileHandle: FileHandle
    ) throws {
        var header = Data([type.rawValue])
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }
        try fileHandle.write(contentsOf: header + payload)
    }

    static func readExact(count: Int, from fileHandle: FileHandle) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            let chunk = try fileHandle.read(upToCount: count - data.count) ?? Data()
            if chunk.isEmpty {
                throw TerminalHostSocketError.unexpectedEOF
            }
            data.append(chunk)
        }
        return data
    }

    static func readFrame(from fileHandle: FileHandle) throws -> (TerminalHostStreamFrameType, Data) {
        let header = try readExact(count: 5, from: fileHandle)
        guard let type = TerminalHostStreamFrameType(rawValue: header[header.startIndex]) else {
            throw TerminalHostSocketError.invalidResponse
        }

        let lengthData = header.suffix(4)
        let length = lengthData.withUnsafeBytes { pointer in
            pointer.load(as: UInt32.self).bigEndian
        }
        let payload = try readExact(count: Int(length), from: fileHandle)
        return (type, payload)
    }
}
