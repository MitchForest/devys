import Foundation
import Darwin

extension TerminalHostSocketIO {
    static func readAvailableBytes(from fd: Int32) throws -> TerminalHostStreamRead {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
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
}
