import Foundation
import Testing
@testable import mac_client

@Suite("Review Trigger Hooks Tests")
struct ReviewTriggerHooksTests {
    @Test("Post-commit review hook installs for enabled repositories")
    func installsManagedHook() throws {
        let fixture = try TestReviewHookRepositoryFixture()
        defer { fixture.cleanup() }

        try ReviewTriggerHooks.syncPostCommitHooks(
            for: [
                ReviewPostCommitHookConfiguration(
                    repositoryRootURL: fixture.repositoryRoot,
                    isEnabled: true
                )
            ],
            executablePath: "/Applications/Devys.app/Contents/MacOS/Devys"
        )

        let hookContents = try fixture.readHook(named: "post-commit")
        #expect(hookContents.contains(ReviewTriggerHooks.reviewMarker))
        #expect(hookContents.contains("--review-trigger"))
        #expect(hookContents.contains("--trigger-source post-commit-hook"))
        #expect(hookContents.contains("--target last-commit"))
        #expect(hookContents.contains("--workspace-id \"$workspace_root\""))
        #expect(hookContents.contains(shellQuoted(fixture.repositoryRoot.path)))
        #expect(hookContents.contains("/Applications/Devys.app/Contents/MacOS/Devys"))
    }

    @Test("Managed review hook preserves and restores an existing post-commit hook")
    func preservesAndRestoresExistingHook() throws {
        let fixture = try TestReviewHookRepositoryFixture()
        defer { fixture.cleanup() }

        let originalScript = """
        #!/bin/zsh
        echo original-hook >> /tmp/devys-hook.log
        """
        try fixture.writeHook(named: "post-commit", contents: originalScript)

        try ReviewTriggerHooks.syncPostCommitHooks(
            for: [
                ReviewPostCommitHookConfiguration(
                    repositoryRootURL: fixture.repositoryRoot,
                    isEnabled: true
                )
            ],
            executablePath: "/Applications/Devys.app/Contents/MacOS/Devys"
        )

        let installedHook = try fixture.readHook(named: "post-commit")
        let backupHook = try fixture.readHook(named: "post-commit.devys-original")
        #expect(installedHook.contains(ReviewTriggerHooks.reviewMarker))
        #expect(backupHook == originalScript)

        try ReviewTriggerHooks.syncPostCommitHooks(
            for: [
                ReviewPostCommitHookConfiguration(
                    repositoryRootURL: fixture.repositoryRoot,
                    isEnabled: false
                )
            ],
            executablePath: nil
        )

        let restoredHook = try fixture.readHook(named: "post-commit")
        #expect(restoredHook == originalScript)
        #expect(fixture.hookExists(named: "post-commit.devys-original") == false)
    }
}

private struct TestReviewHookRepositoryFixture {
    let repositoryRoot: URL

    init() throws {
        repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-review-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
        try runGit(arguments: ["init", "-b", "main"])
        try runGit(arguments: ["config", "user.name", "Devys Tests"])
        try runGit(arguments: ["config", "user.email", "tests@devys.local"])
        try "notes\n".write(
            to: repositoryRoot.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(arguments: ["add", "notes.txt"])
        try runGit(arguments: ["commit", "-m", "Initial commit"])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: repositoryRoot)
    }

    func hookExists(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: hooksDirectoryURL().appendingPathComponent(name).path)
    }

    func writeHook(
        named name: String,
        contents: String
    ) throws {
        let hookURL = hooksDirectoryURL().appendingPathComponent(name, isDirectory: false)
        try contents.write(to: hookURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookURL.path
        )
    }

    func readHook(
        named name: String
    ) throws -> String {
        try String(
            contentsOf: hooksDirectoryURL().appendingPathComponent(name, isDirectory: false),
            encoding: .utf8
        )
    }

    private func hooksDirectoryURL() -> URL {
        let output = try? runGitAndCapture(arguments: ["rev-parse", "--git-path", "hooks"])
        let hooksPath = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ".git/hooks"
        return repositoryRoot
            .appendingPathComponent(hooksPath, isDirectory: true)
            .standardizedFileURL
    }

    private func runGit(
        arguments: [String]
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = repositoryRoot
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    private func runGitAndCapture(
        arguments: [String]
    ) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = repositoryRoot
        process.standardOutput = stdoutPipe
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    }
}
