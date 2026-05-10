import Foundation

final class GitPipeReader: @unchecked Sendable {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var storage = Data()

    init(fileHandle: FileHandle) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = fileHandle.readDataToEndOfFile()
            self.lock.lock()
            self.storage = data
            self.lock.unlock()
            self.group.leave()
        }
    }

    func data() -> Data {
        group.wait()
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct GitCommandRunner: Sendable {
    let repositoryURL: URL

    func run(arguments: [String]) async throws -> String {
        let data = try await runData(arguments: arguments)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func runData(arguments: [String]) async throws -> Data {
        let repositoryURL = repositoryURL
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = repositoryURL

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            let outputReader = GitPipeReader(fileHandle: outputPipe.fileHandleForReading)
            let errorReader = GitPipeReader(fileHandle: errorPipe.fileHandleForReading)
            process.waitUntilExit()

            let output = outputReader.data()
            let error = String(data: errorReader.data(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw GitError.commandFailed(
                    message: error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "git \(arguments.joined(separator: " ")) failed."
                        : error.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            return output
        }.value
    }
}
