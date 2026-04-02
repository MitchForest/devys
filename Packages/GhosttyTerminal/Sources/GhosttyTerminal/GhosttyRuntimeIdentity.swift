import Foundation
import OSLog

public enum GhosttyRuntimeIdentity {
    public static let architectureVersion = "ghostty-boundary-v2"

    public static var summary: String {
        let bundlePath = Bundle.main.bundleURL.path
        let executablePath = Bundle.main.executableURL?.path ?? "unknown"
        let processID = ProcessInfo.processInfo.processIdentifier
        let shortCommit = GhosttyBootstrap.status.shortCommit

        return [
            "runtime=\(architectureVersion)",
            "ghostty_commit=\(shortCommit)",
            "pid=\(processID)",
            "bundle=\(bundlePath)",
            "exec=\(executablePath)",
        ].joined(separator: " ")
    }

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.devys.mac",
        category: "GhosttyTerminal"
    )
}
