import Foundation

#if os(macOS)
import Darwin
#endif

/// The process currently in the foreground process group of a PTY session.
///
/// Resolved via `tcgetpgrp(primaryFD)` to obtain the foreground process group ID, then
/// `proc_pidpath` to recover the executable path. The executable name is the basename
/// of that path, used as the primary signal for agent detection.
public struct TerminalForegroundProcess: Codable, Equatable, Hashable, Sendable {
    public var pid: Int32
    public var executableName: String
    public var executablePath: String

    public init(pid: Int32, executableName: String, executablePath: String) {
        self.pid = pid
        self.executableName = executableName
        self.executablePath = executablePath
    }
}

#if os(macOS)
enum TerminalForegroundProcessProbe {
    /// `<sys/proc_info.h>` defines `PROC_PIDPATHINFO_MAXSIZE` as `4 * MAXPATHLEN`.
    /// Hardcoded here because the symbol is not surfaced through the Swift `Darwin`
    /// overlay; the constant is fixed on macOS so the literal is safe.
    private static let pathBufferSize = 4 * 1024

    /// Reads the foreground process group ID from a PTY primary descriptor and resolves
    /// it to a `TerminalForegroundProcess`. Returns `nil` if the pgid is unavailable or
    /// the process has exited between the two syscalls.
    static func probe(primaryFD: Int32) -> TerminalForegroundProcess? {
        let pgid = tcgetpgrp(primaryFD)
        guard pgid > 0 else { return nil }

        var pathBuffer = [CChar](repeating: 0, count: pathBufferSize)
        let length = proc_pidpath(pgid, &pathBuffer, UInt32(pathBuffer.count))
        guard length > 0 else { return nil }

        let bytes = pathBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        let path = String(decoding: bytes, as: UTF8.self)
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }

        return TerminalForegroundProcess(
            pid: pgid,
            executableName: name,
            executablePath: path
        )
    }
}
#endif
