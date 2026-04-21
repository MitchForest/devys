import Foundation

struct ReviewPostCommitHookConfiguration: Equatable, Sendable {
    var repositoryRootURL: URL
    var isEnabled: Bool
}

enum ReviewTriggerHooks {
    static let reviewMarker = "DEVYS_MANAGED_REVIEW_POST_COMMIT_HOOK"
    private static let hookName = "post-commit"
    private static let backupHookName = "post-commit.devys-original"

    struct SyncFailure: LocalizedError {
        var messages: [String]

        var errorDescription: String? {
            messages.joined(separator: "\n")
        }
    }

    static func syncPostCommitHooks(
        for configurations: [ReviewPostCommitHookConfiguration],
        executablePath: String?,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        var failures: [String] = []

        for configuration in configurations {
            do {
                try syncPostCommitHook(
                    configuration,
                    executablePath: executablePath,
                    fileManager: fileManager,
                    environment: environment
                )
            } catch {
                failures.append(
                    "\(configuration.repositoryRootURL.path): \(error.localizedDescription)"
                )
            }
        }

        guard failures.isEmpty == false else { return }
        throw SyncFailure(messages: failures)
    }

    private static func syncPostCommitHook(
        _ configuration: ReviewPostCommitHookConfiguration,
        executablePath: String?,
        fileManager: FileManager,
        environment: [String: String]
    ) throws {
        let hooksDirectoryURL = try resolveHooksDirectory(
            for: configuration.repositoryRootURL,
            fileManager: fileManager,
            environment: environment
        )
        try fileManager.createDirectory(at: hooksDirectoryURL, withIntermediateDirectories: true)

        if configuration.isEnabled {
            guard let executablePath else {
                throw NSError(
                    domain: "ReviewTriggerHooks",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Devys executable path is unavailable."]
                )
            }
            try ensurePostCommitHookInstalled(
                in: hooksDirectoryURL,
                repositoryRootURL: configuration.repositoryRootURL,
                executablePath: executablePath,
                fileManager: fileManager
            )
        } else {
            try removePostCommitHookIfNeeded(
                from: hooksDirectoryURL,
                fileManager: fileManager
            )
        }
    }

    private static func resolveHooksDirectory(
        for repositoryRootURL: URL,
        fileManager _: FileManager,
        environment: [String: String]
    ) throws -> URL {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "rev-parse", "--git-path", "hooks"]
        process.currentDirectoryURL = repositoryRootURL
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0, stdout.isEmpty == false else {
            throw NSError(
                domain: "ReviewTriggerHooks",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: stderr.isEmpty
                        ? "Unable to resolve git hooks directory."
                        : stderr
                ]
            )
        }

        let hooksPath = NSString(string: stdout).expandingTildeInPath
        if NSString(string: hooksPath).isAbsolutePath {
            return URL(fileURLWithPath: hooksPath).standardizedFileURL
        }
        return repositoryRootURL
            .appendingPathComponent(hooksPath, isDirectory: true)
            .standardizedFileURL
    }

    private static func ensurePostCommitHookInstalled(
        in hooksDirectoryURL: URL,
        repositoryRootURL: URL,
        executablePath: String,
        fileManager: FileManager
    ) throws {
        let hookURL = hooksDirectoryURL.appendingPathComponent(hookName, isDirectory: false)
        let backupURL = hooksDirectoryURL.appendingPathComponent(backupHookName, isDirectory: false)

        if fileManager.fileExists(atPath: hookURL.path) {
            let existingScript = try String(contentsOf: hookURL, encoding: .utf8)
            if existingScript.contains(reviewMarker) == false {
                guard fileManager.fileExists(atPath: backupURL.path) == false else {
                    throw NSError(
                        domain: "ReviewTriggerHooks",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Found an unmanaged post-commit hook while a Devys backup already exists."
                        ]
                    )
                }
                try fileManager.moveItem(at: hookURL, to: backupURL)
            }
        }

        let backupScriptURL: URL? = fileManager.fileExists(atPath: backupURL.path) ? backupURL : nil
        let script = makeHookScript(
            executablePath: executablePath,
            repositoryRootURL: repositoryRootURL,
            backupHookURL: backupScriptURL
        )

        try script.write(to: hookURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookURL.path
        )
    }

    private static func removePostCommitHookIfNeeded(
        from hooksDirectoryURL: URL,
        fileManager: FileManager
    ) throws {
        let hookURL = hooksDirectoryURL.appendingPathComponent(hookName, isDirectory: false)
        let backupURL = hooksDirectoryURL.appendingPathComponent(backupHookName, isDirectory: false)

        guard fileManager.fileExists(atPath: hookURL.path) else { return }
        let existingScript = try String(contentsOf: hookURL, encoding: .utf8)
        guard existingScript.contains(reviewMarker) else { return }

        try fileManager.removeItem(at: hookURL)

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.moveItem(at: backupURL, to: hookURL)
        }
    }

    private static func makeHookScript(
        executablePath: String,
        repositoryRootURL: URL,
        backupHookURL: URL?
    ) -> String {
        let backupSection: String
        if let backupHookURL {
            let quotedBackupPath = shellQuoted(backupHookURL.path)
            backupSection = """
            original_status=0
            if [[ -x \(quotedBackupPath) ]]; then
              \(quotedBackupPath) "$@" || original_status=$?
            elif [[ -f \(quotedBackupPath) ]]; then
              /bin/zsh \(quotedBackupPath) "$@" || original_status=$?
            fi

            """
        } else {
            backupSection = "original_status=0\n\n"
        }

        let quotedExecutablePath = shellQuoted(executablePath)
        let quotedRepositoryRoot = shellQuoted(repositoryRootURL.path)
        let commandPrefix = [
            quotedExecutablePath,
            "--review-trigger",
            "--trigger-source", "post-commit-hook",
            "--target", "last-commit",
            "--workspace-id", "\"$workspace_root\"",
            "--repository-root", quotedRepositoryRoot,
            "--commit-sha", "\"$commit_sha\""
        ]
        .joined(separator: " ")

        return """
        #!/bin/zsh
        # \(reviewMarker)

        \(backupSection)workspace_root="$(/usr/bin/env git rev-parse --show-toplevel 2>/dev/null || pwd)"
        commit_sha="$(/usr/bin/env git rev-parse HEAD 2>/dev/null || true)"
        branch_name="$(/usr/bin/env git branch --show-current 2>/dev/null || true)"

        if [[ -n "$commit_sha" ]]; then
          if [[ -n "$branch_name" ]]; then
            \(commandPrefix) --branch-name "$branch_name" >/dev/null 2>&1 || true
          else
            \(commandPrefix) >/dev/null 2>&1 || true
          fi
        fi

        exit "$original_status"
        """
    }
}
