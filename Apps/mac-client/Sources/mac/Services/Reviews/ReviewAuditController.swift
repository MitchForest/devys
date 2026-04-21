import AppFeatures
import Foundation
import Workspace

actor ReviewAuditController {
    let repositorySettings: @MainActor @Sendable (URL) -> RepositorySettings
    let fileManager: FileManager
    let environment: [String: String]

    init(
        repositorySettings: @escaping @MainActor @Sendable (URL) -> RepositorySettings,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.repositorySettings = repositorySettings
        self.fileManager = fileManager
        self.environment = environment
    }

    func run(
        _ request: ReviewExecutionRequest
    ) async throws -> ReviewExecutionResult {
        let launcher = await resolvedAuditLauncher(for: request)
        let prepared = try await prepareAudit(
            request: request,
            repositoryRootURL: request.target.repositoryRootURL
        )

        guard prepared.context.hasChanges else {
            return try makeEmptyAuditResult(
                artifactSet: prepared.artifactSet,
                runDirectoryURL: prepared.runDirectoryURL
            )
        }

        let execution = try await runAuditCommand(
            request: request,
            launcher: launcher,
            promptURL: prepared.promptURL
        )

        let artifactSet = try persistedExecutionArtifacts(
            for: execution,
            artifactSet: prepared.artifactSet,
            runDirectoryURL: prepared.runDirectoryURL
        )

        guard execution.exitStatus == 0 else {
            throw ReviewExecutionFailure(
                message: reviewCommandFailureMessage(
                    status: execution.exitStatus,
                    stderr: execution.stderr,
                    stdout: execution.stdout
                ),
                artifactSet: artifactSet,
                rawOutputPreview: reviewRawPreview(
                    stdout: execution.stdout,
                    stderr: execution.stderr
                )
            )
        }

        let parsed = try parseAuditOutput(
            execution.stdout,
            runID: request.runID,
            artifactSet: artifactSet
        )

        return try makeCompletedAuditResult(
            parsed: parsed,
            execution: execution,
            artifactSet: artifactSet,
            runDirectoryURL: prepared.runDirectoryURL
        )
    }
}
private extension ReviewAuditController {
    func resolvedAuditLauncher(
        for request: ReviewExecutionRequest
    ) async -> LauncherTemplate {
        let settings = await MainActor.run {
            repositorySettings(request.target.repositoryRootURL)
        }
        return reviewAuditLauncher(
            settings: settings,
            profile: request.profile
        )
    }

    func prepareAudit(
        request: ReviewExecutionRequest,
        repositoryRootURL: URL
    ) async throws -> PreparedReviewAudit {
        let runDirectoryURL = ReviewStorageLocations.runDirectory(
            for: repositoryRootURL,
            runID: request.runID,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: runDirectoryURL, withIntermediateDirectories: true)

        let context = try await buildContext(for: request)
        let inputSnapshotURL = runDirectoryURL.appendingPathComponent(
            "input-snapshot.md",
            isDirectory: false
        )
        try context.snapshot.write(to: inputSnapshotURL, atomically: true, encoding: .utf8)

        let promptURL = runDirectoryURL.appendingPathComponent("audit-prompt.md", isDirectory: false)
        try makePrompt(for: request, context: context)
            .write(to: promptURL, atomically: true, encoding: .utf8)

        return PreparedReviewAudit(
            context: context,
            runDirectoryURL: runDirectoryURL,
            promptURL: promptURL,
            artifactSet: ReviewArtifactSet(
                inputSnapshotPath: inputSnapshotURL.path,
                auditPromptPath: promptURL.path
            )
        )
    }

    func makeEmptyAuditResult(
        artifactSet: ReviewArtifactSet,
        runDirectoryURL: URL
    ) throws -> ReviewExecutionResult {
        var artifactSet = artifactSet
        let parsedURL = runDirectoryURL.appendingPathComponent("parsed-result.json", isDirectory: false)
        let summaryURL = runDirectoryURL.appendingPathComponent("summary.md", isDirectory: false)
        try encodedEmptyResult().write(to: parsedURL, options: .atomic)
        try renderedSummary(for: []).write(to: summaryURL, atomically: true, encoding: .utf8)
        artifactSet.parsedResultPath = parsedURL.path
        artifactSet.renderedSummaryPath = summaryURL.path
        return ReviewExecutionResult(
            artifactSet: artifactSet,
            issues: [],
            rawOutputPreview: "No changes detected for this review target."
        )
    }

    func persistedExecutionArtifacts(
        for execution: ReviewCommandExecution,
        artifactSet: ReviewArtifactSet,
        runDirectoryURL: URL
    ) throws -> ReviewArtifactSet {
        var artifactSet = artifactSet
        let stdoutURL = runDirectoryURL.appendingPathComponent("stdout.txt", isDirectory: false)
        let stderrURL = runDirectoryURL.appendingPathComponent("stderr.txt", isDirectory: false)
        try execution.stdout.write(to: stdoutURL, atomically: true, encoding: .utf8)
        try execution.stderr.write(to: stderrURL, atomically: true, encoding: .utf8)
        artifactSet.rawStdoutPath = stdoutURL.path
        artifactSet.rawStderrPath = stderrURL.path
        return artifactSet
    }

    func runAuditCommand(
        request: ReviewExecutionRequest,
        launcher: LauncherTemplate,
        promptURL: URL
    ) async throws -> ReviewCommandExecution {
        let command = try makeHeadlessAuditCommand(
            harness: request.profile.auditHarness,
            launcher: launcher,
            promptURL: promptURL
        )
        return try await runCommand(
            command,
            currentDirectoryURL: request.workingDirectoryURL
        )
    }

    func makeCompletedAuditResult(
        parsed: ParsedReviewAudit,
        execution: ReviewCommandExecution,
        artifactSet: ReviewArtifactSet,
        runDirectoryURL: URL
    ) throws -> ReviewExecutionResult {
        var artifactSet = artifactSet
        let parsedURL = runDirectoryURL.appendingPathComponent("parsed-result.json", isDirectory: false)
        let summaryURL = runDirectoryURL.appendingPathComponent("summary.md", isDirectory: false)
        try encode(parsed.response).write(to: parsedURL, options: .atomic)
        try renderedSummary(for: parsed.issues).write(to: summaryURL, atomically: true, encoding: .utf8)
        artifactSet.parsedResultPath = parsedURL.path
        artifactSet.renderedSummaryPath = summaryURL.path

        return ReviewExecutionResult(
            artifactSet: artifactSet,
            overallRisk: parsed.response.overallRisk,
            issues: parsed.issues,
            rawOutputPreview: reviewRawPreview(stdout: execution.stdout, stderr: execution.stderr)
        )
    }
}
private extension ReviewAuditController {
    func makePrompt(
        for request: ReviewExecutionRequest,
        context: ReviewAuditContext
    ) -> String {
        let extraInstructions = reviewNormalizedOptionalString(
            request.profile.additionalInstructions
        ).map {
            """

            Additional review instructions:
            \($0)
            """
        } ?? ""

        return """
        You are Devys review audit mode. Review only the target described below.

        Before auditing, read the listed `AGENTS.md` files and canonical docs from the repository
        when they are relevant.

        Focus on correctness, regressions, risky behavior, missing validation, migration hazards,
        and code that violates the repo's simplicity rules. Do not produce style nits.

        Return only valid JSON with this exact shape:
        {
          "overallRisk": "low" | "medium" | "high" | null,
          "issues": [
            {
              "severity": "minor" | "major" | "critical",
              "confidence": "low" | "medium" | "high",
              "title": "short finding title",
              "summary": "one paragraph summary",
              "rationale": "why this matters and what can go wrong",
              "paths": ["relative/path.swift"],
              "locations": [{"path": "relative/path.swift", "line": 12, "column": 3}],
              "sourceReferences": ["AGENTS.md", ".docs/reference/architecture.md"],
              "dedupeKey": "stable-short-key"
            }
          ]
        }

        Rules:
        - Output JSON only.
        - Do not wrap the JSON in markdown fences.
        - If there are no actionable findings, return {"overallRisk": null, "issues": []}.
        - Only include file paths that are relevant to the finding.
        - Keep findings explicit and easy to act on.
        \(extraInstructions)

        Input snapshot:

        \(context.snapshot)
        """
    }

    func makeHeadlessAuditCommand(
        harness: BuiltInLauncherKind,
        launcher: LauncherTemplate,
        promptURL: URL
    ) throws -> String {
        let executable = launcher.executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executable.isEmpty else {
            throw ReviewExecutionFailure(message: "Review audit launcher executable is empty.")
        }

        let promptExpression = "\"$(cat \(shellQuoted(promptURL.path)))\""
        switch harness {
        case .claude:
            return ([executable]
                + claudeHeadlessArguments(for: launcher)
                + ["-p", promptExpression])
                .joined(separator: " ")

        case .codex:
            return ([executable, "exec"]
                + codexHeadlessArguments(for: launcher)
                + [promptExpression])
                .joined(separator: " ")
        }
    }
}
