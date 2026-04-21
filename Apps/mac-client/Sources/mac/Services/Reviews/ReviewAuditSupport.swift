import AppFeatures
import Foundation
import Workspace

struct ReviewAuditContext {
    var snapshot: String
    var hasChanges: Bool
}

struct ReviewCommandExecution {
    var stdout: String
    var stderr: String
    var exitStatus: Int32
}

struct ParsedReviewAudit {
    var response: ReviewAuditResponsePayload
    var issues: [ReviewIssue]
}

struct PreparedReviewAudit {
    var context: ReviewAuditContext
    var runDirectoryURL: URL
    var promptURL: URL
    var artifactSet: ReviewArtifactSet
}

struct ReviewAuditResponsePayload: Codable, Equatable {
    var overallRisk: ReviewOverallRisk?
    var issues: [ReviewAuditIssuePayload]
}

struct ReviewAuditIssuePayload: Codable, Equatable {
    var severity: ReviewIssueSeverity
    var confidence: ReviewIssueConfidence
    var title: String
    var summary: String
    var rationale: String
    var paths: [String]?
    var locations: [ReviewIssueLocation]?
    var sourceReferences: [String]?
    var dedupeKey: String?
}

struct ReviewGitContext {
    var changedPaths: [String]
    var diffStat: String
    var diffPatch: String
    var hasChanges: Bool
    var baseDescription: String?
}

extension ReviewAuditController {
    func renderedSummary(
        for issues: [ReviewIssue]
    ) -> String {
        guard !issues.isEmpty else {
            return """
            # Review Summary

            No actionable issues were reported.
            """
        }

        let body = issues.map { issue in
            """
            ## [\(issue.severity.rawValue.uppercased())] \(issue.title)

            \(issue.summary)

            \(issue.rationale)
            """
        }
        .joined(separator: "\n\n")

        return """
        # Review Summary

        Total issues: \(issues.count)

        \(body)
        """
    }

    func readToEnd(
        _ handle: FileHandle
    ) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }

    func encode<T: Encodable>(
        _ value: T
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    func encodedEmptyResult() throws -> Data {
        try encode(
            ReviewAuditResponsePayload(
                overallRisk: nil,
                issues: []
            )
        )
    }
}

func reviewAuditLauncher(
    settings: RepositorySettings,
    profile: ReviewProfile
) -> LauncherTemplate {
    var launcher = switch profile.auditHarness {
    case .claude:
        settings.claudeLauncher
    case .codex:
        settings.codexLauncher
    }

    if let model = reviewNormalizedOptionalString(profile.auditModelOverride) {
        launcher.model = model
    }
    if let reasoning = reviewNormalizedOptionalString(profile.auditReasoningOverride) {
        launcher.reasoningLevel = reasoning
    }
    if let dangerousPermissions = profile.auditDangerousPermissionsOverride {
        launcher.dangerousPermissions = dangerousPermissions
    }
    return launcher
}

func claudeHeadlessArguments(
    for launcher: LauncherTemplate
) -> [String] {
    var arguments: [String] = []
    if let model = reviewNormalizedOptionalString(launcher.model) {
        arguments.append(contentsOf: ["--model", shellQuoted(model)])
    }
    if let reasoning = reviewNormalizedOptionalString(launcher.reasoningLevel) {
        arguments.append(contentsOf: ["--effort", shellQuoted(reasoning)])
    }
    if launcher.dangerousPermissions {
        arguments.append("--dangerously-skip-permissions")
    }
    arguments.append(contentsOf: launcher.extraArguments.map(shellQuoted))
    return arguments
}

func codexHeadlessArguments(
    for launcher: LauncherTemplate
) -> [String] {
    var arguments: [String] = []
    if let model = reviewNormalizedOptionalString(launcher.model) {
        arguments.append(contentsOf: ["-m", shellQuoted(model)])
    }
    if let reasoning = reviewNormalizedOptionalString(launcher.reasoningLevel) {
        arguments.append(contentsOf: ["-c", shellQuoted("model_reasoning_effort=\"\(reasoning)\"")])
    }
    if launcher.dangerousPermissions {
        arguments.append("--dangerously-bypass-approvals-and-sandbox")
    }
    arguments.append(contentsOf: launcher.extraArguments.map(shellQuoted))
    return arguments
}

func reviewGovernanceFiles(
    for changedPaths: [String],
    rootURL: URL,
    fileManager: FileManager
) -> [String] {
    let candidatePaths = changedPaths.isEmpty ? [""] : changedPaths
    var ordered: [String] = []

    for path in candidatePaths {
        var directoryURL = rootURL.appendingPathComponent(path, isDirectory: false)
        if !path.isEmpty {
            directoryURL.deleteLastPathComponent()
        }

        while directoryURL.path.hasPrefix(rootURL.path) {
            let agentsURL = directoryURL.appendingPathComponent("AGENTS.md", isDirectory: false)
            if fileManager.fileExists(atPath: agentsURL.path) {
                let relativePath = reviewRelativePath(agentsURL, rootURL: rootURL)
                if !ordered.contains(relativePath) {
                    ordered.append(relativePath)
                }
            }
            guard directoryURL.path != rootURL.path else { break }
            directoryURL.deleteLastPathComponent()
        }
    }

    return ordered
}

func reviewCanonicalDocs(
    rootURL: URL,
    fileManager: FileManager
) -> [String] {
    [
        ".docs/reference/architecture.md",
        ".docs/reference/ui-ux.md",
        ".docs/reference/terminal-runtime.md",
        ".docs/reference/legacy-inventory.md"
    ]
    .filter { relativePath in
        fileManager.fileExists(
            atPath: rootURL.appendingPathComponent(relativePath, isDirectory: false).path
        )
    }
}

func reviewChangedPaths(
    from nameStatus: String
) -> [String] {
    nameStatus
        .split(whereSeparator: \.isNewline)
        .compactMap { line in
            String(line).split(separator: "\t").last.map(String.init)
        }
}

func reviewRelativePath(
    _ fileURL: URL,
    rootURL: URL
) -> String {
    let path = fileURL.standardizedFileURL.path
    let rootPath = rootURL.standardizedFileURL.path
    guard path.hasPrefix(rootPath) else { return path }
    return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}

func reviewTruncated(
    _ value: String,
    limit: Int
) -> String {
    guard value.count > limit else {
        return value.isEmpty ? "None" : value
    }
    return String(value.prefix(limit)) + "\n\n[truncated]"
}

func reviewJSONPayload(
    from output: String
) throws -> String {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw ReviewExecutionFailure(message: "Review audit returned no output.")
    }
    if trimmed.hasPrefix("```"), trimmed.hasSuffix("```") {
        let lines = trimmed.split(whereSeparator: \.isNewline)
        guard lines.count >= 3 else {
            throw ReviewExecutionFailure(message: "Review audit returned malformed fenced output.")
        }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }
    return trimmed
}

func reviewRawPreview(
    stdout: String,
    stderr: String
) -> String? {
    let preview = [stdout, stderr]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    return preview.map { reviewTruncated($0, limit: 500) }
}

func reviewCommandFailureMessage(
    status: Int32,
    stderr: String,
    stdout: String
) -> String {
    let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedStderr.isEmpty {
        return trimmedStderr
    }
    let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedStdout.isEmpty {
        return trimmedStdout
    }
    return "Review audit command failed with exit status \(status)."
}

func reviewRequiredText(
    _ value: String
) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Missing detail from audit output." : trimmed
}

func reviewNormalizedPaths(
    _ paths: [String]?
) -> [String] {
    (paths ?? [])
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func reviewNormalizedLocations(
    _ locations: [ReviewIssueLocation]?
) -> [ReviewIssueLocation] {
    (locations ?? []).filter { !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

func reviewNormalizedReferences(
    _ references: [String]?
) -> [String] {
    (references ?? [])
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func reviewDedupeKey(
    for issue: ReviewAuditIssuePayload
) -> String {
    if let dedupeKey = reviewNormalizedOptionalString(issue.dedupeKey) {
        return dedupeKey
    }
    let path = reviewNormalizedPaths(issue.paths).first ?? "global"
    let title = reviewRequiredText(issue.title).lowercased().replacingOccurrences(of: " ", with: "-")
    return "\(path)#\(title)"
}

func reviewNormalizedOptionalString(
    _ value: String?
) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
