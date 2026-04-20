import Darwin
import Foundation
import Testing
@testable import mac_client

@Suite("Terminal Host Transport Tests")
struct TerminalHostTransportTests {
    @Test("Client stream parsing tolerates partial frames")
    func parsePartialFramesFromBufferedSocketReads() throws {
        let (reader, writer) = try makeSocketPair()
        defer {
            Darwin.close(reader)
            Darwin.close(writer)
        }

        let payload = Data("resize".utf8)
        let frame = makeFrame(type: .resize, payload: payload)
        let splitIndex = 3
        let firstChunk = Data(frame.prefix(splitIndex))
        let secondChunk = Data(frame.dropFirst(splitIndex))

        _ = firstChunk.withUnsafeBytes { pointer in
            Darwin.write(writer, pointer.baseAddress, firstChunk.count)
        }

        var buffer = Data()
        let firstRead = try TerminalHostSocketIO.readAvailable(from: reader)
        buffer.append(firstRead.data)
        #expect(firstRead.reachedEOF == false)
        #expect(try TerminalHostSocketIO.parseFrame(from: &buffer) == nil)

        _ = secondChunk.withUnsafeBytes { pointer in
            Darwin.write(writer, pointer.baseAddress, secondChunk.count)
        }

        let secondRead = try TerminalHostSocketIO.readAvailable(from: reader)
        buffer.append(secondRead.data)
        let parsed = try TerminalHostSocketIO.parseFrame(from: &buffer)

        #expect(parsed?.0 == .resize)
        #expect(parsed?.1 == payload)
        #expect(buffer.isEmpty)
    }

    @Test("Client stream parsing drains multiple frames from one read")
    func parseMultipleFramesFromSingleBufferedRead() throws {
        let (reader, writer) = try makeSocketPair()
        defer {
            Darwin.close(reader)
            Darwin.close(writer)
        }

        let firstFrame = makeFrame(type: .input, payload: Data("one".utf8))
        let secondFrame = makeFrame(type: .close, payload: Data("two".utf8))
        let combined = firstFrame + secondFrame

        _ = combined.withUnsafeBytes { pointer in
            Darwin.write(writer, pointer.baseAddress, combined.count)
        }

        var buffer = Data()
        let read = try TerminalHostSocketIO.readAvailable(from: reader)
        buffer.append(read.data)

        let firstParsed = try TerminalHostSocketIO.parseFrame(from: &buffer)
        let secondParsed = try TerminalHostSocketIO.parseFrame(from: &buffer)

        #expect(firstParsed?.0 == .input)
        #expect(firstParsed?.1 == Data("one".utf8))
        #expect(secondParsed?.0 == .close)
        #expect(secondParsed?.1 == Data("two".utf8))
        #expect(buffer.isEmpty)
    }
}

private func makeSocketPair() throws -> (Int32, Int32) {
    var descriptors: [Int32] = [0, 0]
    let result = socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors)
    guard result == 0 else {
        throw TerminalHostSocketError.socketCreationFailed(errno)
    }
    return (descriptors[0], descriptors[1])
}

private func makeFrame(type: TerminalHostStreamFrameType, payload: Data) -> Data {
    var frame = Data([type.rawValue])
    var length = UInt32(payload.count).bigEndian
    withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
    frame.append(payload)
    return frame
}
