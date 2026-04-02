import Foundation

struct TmuxControlSession {
    let process: Process
    let stdin: FileHandle
    let stdout: FileHandle
    let stderr: FileHandle
}

enum TmuxManagerError: Error, Sendable {
    case tmuxNotInstalled
    case commandFailed(String)
}

final class TmuxManager: @unchecked Sendable {
    private let binaryPath: String?
    private let serverLabel: String

    init(binaryPath: String? = nil, serverLabel: String = "devys") {
        if let binaryPath {
            self.binaryPath = binaryPath
        } else {
            self.binaryPath = Self.resolveBinaryPath()
        }
        self.serverLabel = serverLabel
    }

    var isAvailable: Bool {
        binaryPath != nil
    }

    func createSession(name: String, workingDirectory: String?) throws {
        if try hasSession(name: name) {
            return
        }

        var args = ["new-session", "-d", "-s", name]
        if let workingDirectory, !workingDirectory.isEmpty {
            args += ["-c", workingDirectory]
        }

        _ = try run(args)
    }

    func hasSession(name: String) throws -> Bool {
        do {
            _ = try run(["has-session", "-t", name])
            return true
        } catch let TmuxManagerError.commandFailed(message) {
            if
                message.contains("can't find session") ||
                message.contains("no server running") ||
                message.contains("error connecting to")
            {
                return false
            }
            throw TmuxManagerError.commandFailed(message)
        }
    }

    func sendKeys(sessionName: String, text: String, pressEnter: Bool) throws {
        if !text.isEmpty {
            _ = try run(["send-keys", "-t", "\(sessionName):0.0", "-l", text])
        }
        if pressEnter {
            _ = try run(["send-keys", "-t", "\(sessionName):0.0", "Enter"])
        }
    }

    func sendInterrupt(sessionName: String) throws {
        _ = try run(["send-keys", "-t", "\(sessionName):0.0", "C-c"])
    }

    func resizeWindow(sessionName: String, cols: Int, rows: Int) throws {
        _ = try run([
            "resize-window",
            "-t", "\(sessionName):0",
            "-x", String(cols),
            "-y", String(rows)
        ])
    }

    func startControlSession(name: String) throws -> TmuxControlSession {
        guard let binaryPath else {
            throw TmuxManagerError.tmuxNotInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["-L", serverLabel, "-C", "attach-session", "-t", name]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TMUX")
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw TmuxManagerError.commandFailed("Unable to start tmux control session: \(error.localizedDescription)")
        }

        return TmuxControlSession(
            process: process,
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading
        )
    }

    private func run(_ args: [String]) throws -> String {
        guard let binaryPath else {
            throw TmuxManagerError.tmuxNotInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["-L", serverLabel] + args
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TMUX")
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw TmuxManagerError.commandFailed("Unable to run tmux: \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw TmuxManagerError.commandFailed(stderrText.isEmpty ? stdoutText : stderrText)
        }

        return stdoutText
    }

    private static func resolveBinaryPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}
