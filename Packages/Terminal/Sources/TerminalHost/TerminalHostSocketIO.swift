import Darwin
import Foundation

struct TerminalHostStreamRead: Sendable {
    let data: Data
    let reachedEOF: Bool
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

    static func withResponseTimeout<T>(
        fileDescriptor: Int32,
        seconds: Int = 2,
        _ body: () throws -> T
    ) throws -> T {
        try setResponseTimeout(seconds, on: fileDescriptor)
        defer {
            try? setResponseTimeout(nil, on: fileDescriptor)
        }
        return try body()
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
        setBlocking(fd)
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

        let length = header.dropFirst().reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        let payload = try readExact(count: Int(length), from: fileHandle)
        return (type, payload)
    }

    static func readAvailable(from fd: Int32) throws -> TerminalHostStreamRead {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = Darwin.recv(fd, &buffer, buffer.count, MSG_DONTWAIT)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(Int(count)))
                continue
            }

            if count == 0 {
                return TerminalHostStreamRead(data: data, reachedEOF: true)
            }

            if errno == EWOULDBLOCK || errno == EAGAIN {
                return TerminalHostStreamRead(data: data, reachedEOF: false)
            }

            if errno == EINTR {
                continue
            }

            throw TerminalHostSocketError.readFailed(errno)
        }
    }

    static func parseFrame(
        from buffer: inout Data
    ) throws -> (TerminalHostStreamFrameType, Data)? {
        guard buffer.count >= 5 else { return nil }

        let typeByte = buffer[buffer.startIndex]
        guard let type = TerminalHostStreamFrameType(rawValue: typeByte) else {
            throw TerminalHostSocketError.invalidResponse
        }

        let length = buffer[buffer.startIndex + 1..<buffer.startIndex + 5]
            .reduce(UInt32(0)) { partial, byte in
                (partial << 8) | UInt32(byte)
            }
        let frameLength = 5 + Int(length)
        guard buffer.count >= frameLength else { return nil }

        let payload = Data(buffer[buffer.startIndex + 5..<buffer.startIndex + frameLength])
        buffer.removeSubrange(buffer.startIndex..<buffer.startIndex + frameLength)
        return (type, payload)
    }

    private static func setResponseTimeout(
        _ seconds: Int?,
        on fileDescriptor: Int32
    ) throws {
        var timeout = timeval()
        if let seconds {
            timeout.tv_sec = __darwin_time_t(seconds)
            timeout.tv_usec = 0
        }

        guard setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            throw TerminalHostSocketError.socketOptionFailed(errno)
        }

        guard setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            throw TerminalHostSocketError.socketOptionFailed(errno)
        }
    }
}

private func setBlocking(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFL)
    guard flags >= 0 else { return }
    _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
}
