import AppFeatures
import Foundation

extension ReviewAuditController {
    func buildContext(
        for request: ReviewExecutionRequest
    ) async throws -> ReviewAuditContext {
        let target = request.target
        let gitContext = try await makeGitContext(
            for: target,
            workingDirectoryURL: request.workingDirectoryURL
        )
        let agents = reviewGovernanceFiles(
            for: gitContext.changedPaths,
            rootURL: target.repositoryRootURL,
            fileManager: fileManager
        )
        let canonicalDocs = reviewCanonicalDocs(
            rootURL: target.repositoryRootURL,
            fileManager: fileManager
        )
        let snapshot = makeAuditSnapshot(
            request: request,
            gitContext: gitContext,
            governanceSection: reviewBulletSection(agents),
            docsSection: reviewBulletSection(canonicalDocs),
            changedFilesSection: reviewBulletSection(gitContext.changedPaths)
        )

        return ReviewAuditContext(
            snapshot: snapshot
                .replacingOccurrences(of: "\n\n\n", with: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            hasChanges: gitContext.hasChanges
        )
    }

    func makeAuditSnapshot(
        request: ReviewExecutionRequest,
        gitContext: ReviewGitContext,
        governanceSection: String,
        docsSection: String,
        changedFilesSection: String
    ) -> String {
        let target = request.target
        return """
        # Review Target
        - Kind: \(target.kind.displayTitle)
        - Title: \(target.displayTitle)
        - Trigger: \(request.trigger.source.rawValue)
        - Working Directory: \(request.workingDirectoryURL.path)
        - Repository Root: \(target.repositoryRootURL.path)
        \(target.branchName.map { "- Branch: \($0)" } ?? "")
        \(gitContext.baseDescription.map { "- Base: \($0)" } ?? "")

        # Governing AGENTS.md Files
        \(governanceSection)

        # Canonical Docs To Read
        \(docsSection)

        # Changed Files
        \(changedFilesSection)

        # Diff Stat
        \(reviewTruncated(gitContext.diffStat, limit: 8_000))

        # Diff
        \(reviewTruncated(gitContext.diffPatch, limit: 60_000))
        """
    }

    func reviewBulletSection(
        _ items: [String]
    ) -> String {
        items.isEmpty ? "None" : items.map { "- \($0)" }.joined(separator: "\n")
    }

    func makeGitContext(
        for target: ReviewTarget,
        workingDirectoryURL: URL
    ) async throws -> ReviewGitContext {
        switch target.kind {
        case .unstagedChanges:
            return try await reviewGitContext(
                workingDirectoryURL: workingDirectoryURL,
                nameStatusArguments: ["diff", "--name-status", "--no-ext-diff", "--"],
                diffStatArguments: ["diff", "--stat", "--no-ext-diff", "--"],
                diffPatchArguments: ["diff", "--no-ext-diff", "--binary", "--"]
            )

        case .stagedChanges:
            return try await reviewGitContext(
                workingDirectoryURL: workingDirectoryURL,
                nameStatusArguments: ["diff", "--cached", "--name-status", "--no-ext-diff", "--"],
                diffStatArguments: ["diff", "--cached", "--stat", "--no-ext-diff", "--"],
                diffPatchArguments: ["diff", "--cached", "--no-ext-diff", "--binary", "--"]
            )

        case .lastCommit:
            _ = try await runGit(
                ["rev-parse", "--verify", "HEAD"],
                in: workingDirectoryURL
            )
            return try await reviewGitContext(
                workingDirectoryURL: workingDirectoryURL,
                nameStatusArguments: ["show", "--format=", "--name-status", "HEAD", "--"],
                diffStatArguments: ["show", "--stat", "--format=fuller", "--no-ext-diff", "HEAD", "--"],
                diffPatchArguments: ["show", "--format=fuller", "--no-ext-diff", "--binary", "HEAD", "--"]
            )

        case .currentBranch:
            return try await makeCurrentBranchContext(
                workingDirectoryURL: workingDirectoryURL
            )

        case .pullRequest:
            return try await makePullRequestContext(
                target: target,
                workingDirectoryURL: workingDirectoryURL
            )

        case .commitRange, .selection:
            throw ReviewExecutionFailure(
                message: "\(target.kind.displayTitle) is not implemented in the current review executor."
            )
        }
    }

    func reviewGitContext(
        workingDirectoryURL: URL,
        nameStatusArguments: [String],
        diffStatArguments: [String],
        diffPatchArguments: [String]
    ) async throws -> ReviewGitContext {
        async let nameStatusOutput = runGit(nameStatusArguments, in: workingDirectoryURL)
        async let diffStatOutput = runGit(diffStatArguments, in: workingDirectoryURL)
        async let diffPatchOutput = runGit(diffPatchArguments, in: workingDirectoryURL)

        let nameStatus = try await nameStatusOutput
        let diffStat = try await diffStatOutput
        let diffPatch = try await diffPatchOutput

        return ReviewGitContext(
            changedPaths: reviewChangedPaths(from: nameStatus),
            diffStat: diffStat.trimmingCharacters(in: .whitespacesAndNewlines),
            diffPatch: diffPatch.trimmingCharacters(in: .whitespacesAndNewlines),
            hasChanges: !diffPatch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    func makeCurrentBranchContext(
        workingDirectoryURL: URL
    ) async throws -> ReviewGitContext {
        let upstream = try await runGit(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            in: workingDirectoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !upstream.isEmpty else {
            throw ReviewExecutionFailure(
                message: "Current Branch review requires an upstream branch."
            )
        }
        let mergeBase = try await runGit(
            ["merge-base", "HEAD", upstream],
            in: workingDirectoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let range = "\(mergeBase)...HEAD"
        var context = try await reviewGitContext(
            workingDirectoryURL: workingDirectoryURL,
            nameStatusArguments: ["diff", "--name-status", "--no-ext-diff", range, "--"],
            diffStatArguments: ["diff", "--stat", "--no-ext-diff", range, "--"],
            diffPatchArguments: ["diff", "--no-ext-diff", "--binary", range, "--"]
        )
        context.baseDescription = "Merge base \(mergeBase) against \(upstream)"
        return context
    }

    func makePullRequestContext(
        target: ReviewTarget,
        workingDirectoryURL: URL
    ) async throws -> ReviewGitContext {
        guard let baseBranchName = reviewNormalizedOptionalString(target.baseBranchName) else {
            throw ReviewExecutionFailure(
                message: "Pull Request review requires a base branch."
            )
        }

        let baseReference = try await resolveReviewBaseReference(
            baseBranchName,
            workingDirectoryURL: workingDirectoryURL
        )
        let mergeBase = try await runGit(
            ["merge-base", "HEAD", baseReference],
            in: workingDirectoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let range = "\(mergeBase)...HEAD"
        var context = try await reviewGitContext(
            workingDirectoryURL: workingDirectoryURL,
            nameStatusArguments: ["diff", "--name-status", "--no-ext-diff", range, "--"],
            diffStatArguments: ["diff", "--stat", "--no-ext-diff", range, "--"],
            diffPatchArguments: ["diff", "--no-ext-diff", "--binary", range, "--"]
        )

        let pullRequestLabel = target.pullRequestNumber.map { "#\($0)" } ?? target.displayTitle
        context.baseDescription = "Pull request \(pullRequestLabel) against \(baseReference)"
        return context
    }

    func resolveReviewBaseReference(
        _ baseBranchName: String,
        workingDirectoryURL: URL
    ) async throws -> String {
        let remoteReference = "origin/\(baseBranchName)"
        if try await reviewGitReferenceExists(remoteReference, workingDirectoryURL: workingDirectoryURL) {
            return remoteReference
        }

        if try await reviewGitReferenceExists(baseBranchName, workingDirectoryURL: workingDirectoryURL) {
            return baseBranchName
        }

        throw ReviewExecutionFailure(
            message: "Review target requires base branch \(baseBranchName), but it is not available locally."
        )
    }

    func reviewGitReferenceExists(
        _ reference: String,
        workingDirectoryURL: URL
    ) async throws -> Bool {
        do {
            let output = try await runGit(
                ["rev-parse", "--verify", "--quiet", reference],
                in: workingDirectoryURL
            )
            return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } catch {
            return false
        }
    }

    func runCommand(
        _ command: String,
        currentDirectoryURL: URL
    ) async throws -> ReviewCommandExecution {
        try Task.checkCancellation()

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = Dictionary(
            uniqueKeysWithValues: environment.filter { $0.key != "NO_COLOR" }
        )
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ReviewExecutionFailure(message: error.localizedDescription)
        }

        async let stdoutData = readToEnd(stdoutPipe.fileHandleForReading)
        async let stderrData = readToEnd(stderrPipe.fileHandleForReading)
        let exitStatus = try await waitForExit(process)

        return ReviewCommandExecution(
            stdout: String(data: await stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: await stderrData, encoding: .utf8) ?? "",
            exitStatus: exitStatus
        )
    }

    func waitForExit(
        _ process: Process
    ) async throws -> Int32 {
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return process.terminationStatus
    }

    func runGit(
        _ arguments: [String],
        in workingDirectoryURL: URL
    ) async throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ReviewExecutionFailure(message: error.localizedDescription)
        }

        async let stdoutData = readToEnd(stdoutPipe.fileHandleForReading)
        async let stderrData = readToEnd(stderrPipe.fileHandleForReading)
        let exitStatus = try await waitForExit(process)
        let stdout = String(data: await stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: await stderrData, encoding: .utf8) ?? ""

        guard exitStatus == 0 else {
            throw ReviewExecutionFailure(
                message: reviewCommandFailureMessage(
                    status: exitStatus,
                    stderr: stderr,
                    stdout: stdout
                )
            )
        }

        return stdout
    }

    func parseAuditOutput(
        _ output: String,
        runID: UUID,
        artifactSet: ReviewArtifactSet
    ) throws -> ParsedReviewAudit {
        let jsonText = try reviewJSONPayload(from: output)
        let data = Data(jsonText.utf8)

        let response: ReviewAuditResponsePayload
        do {
            response = try JSONDecoder().decode(ReviewAuditResponsePayload.self, from: data)
        } catch {
            throw ReviewExecutionFailure(
                message: "Review audit returned malformed JSON.",
                artifactSet: artifactSet,
                rawOutputPreview: reviewRawPreview(stdout: output, stderr: "")
            )
        }

        let issues = response.issues.map { issue in
            ReviewIssue(
                runID: runID,
                severity: issue.severity,
                confidence: issue.confidence,
                title: reviewRequiredText(issue.title),
                summary: reviewRequiredText(issue.summary),
                rationale: reviewRequiredText(issue.rationale),
                paths: reviewNormalizedPaths(issue.paths),
                locations: reviewNormalizedLocations(issue.locations),
                sourceReferences: reviewNormalizedReferences(issue.sourceReferences),
                dedupeKey: reviewDedupeKey(for: issue)
            )
        }

        return ParsedReviewAudit(response: response, issues: issues)
    }
}
