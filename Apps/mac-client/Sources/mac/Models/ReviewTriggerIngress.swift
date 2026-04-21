// ReviewTriggerIngress.swift
// Devys - Cross-process review trigger ingress.

import AppFeatures
import Foundation

enum ReviewTriggerIngress {
    static let userInfoPayloadKey = "payload"

    struct PayloadInput: Sendable {
        let workspaceID: String?
        let repositoryRootPath: String?
        let triggerSource: String
        let targetKind: String
        let commitSHA: String?
        let branchName: String?
        let title: String?
    }

    enum Error: LocalizedError {
        case missingRepositoryRoot
        case invalidTriggerSource(String)
        case invalidTargetKind(String)
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .missingRepositoryRoot:
                return "A repository root is required for review triggers."
            case .invalidTriggerSource(let value):
                return "Invalid review trigger source: \(value)"
            case .invalidTargetKind(let value):
                return "Invalid review target kind: \(value)"
            case .invalidPayload:
                return "Review trigger payload is missing or malformed."
            }
        }
    }

    static func makePayload(
        _ input: PayloadInput
    ) throws -> ReviewTriggerRequest {
        let normalizedRepositoryRoot = normalizedOptionalString(input.repositoryRootPath)
            ?? FileManager.default.currentDirectoryPath
        guard !normalizedRepositoryRoot.isEmpty else {
            throw Error.missingRepositoryRoot
        }

        guard let decodedSource = reviewTriggerSource(from: input.triggerSource) else {
            throw Error.invalidTriggerSource(input.triggerSource)
        }
        guard let decodedTargetKind = reviewTargetKind(from: input.targetKind) else {
            throw Error.invalidTargetKind(input.targetKind)
        }

        let normalizedWorkspaceID = normalizedOptionalString(input.workspaceID)
        let normalizedBranchName = normalizedOptionalString(input.branchName)
        let normalizedCommitSHA = normalizedOptionalString(input.commitSHA)
        let repositoryRootURL = URL(fileURLWithPath: normalizedRepositoryRoot).standardizedFileURL
        let resolvedTitle = reviewTargetTitle(
            explicitTitle: input.title,
            targetKind: decodedTargetKind,
            commitSHA: normalizedCommitSHA,
            branchName: normalizedBranchName
        )

        let target = ReviewTarget(
            id: reviewTargetID(
                workspaceID: normalizedWorkspaceID,
                repositoryRootPath: repositoryRootURL.path,
                targetKind: decodedTargetKind,
                commitSHA: normalizedCommitSHA
            ),
            kind: decodedTargetKind,
            workspaceID: normalizedWorkspaceID,
            repositoryRootURL: repositoryRootURL,
            title: resolvedTitle,
            branchName: normalizedBranchName,
            commitShas: normalizedCommitSHA.map { [$0] } ?? []
        )

        let trigger = ReviewTrigger(
            source: decodedSource,
            createdAt: Date(),
            isUserVisible: true
        )

        return ReviewTriggerRequest(
            workspaceID: normalizedWorkspaceID,
            repositoryRootURL: repositoryRootURL,
            target: target,
            trigger: trigger
        )
    }

    static func encode(_ request: ReviewTriggerRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        guard let encodedPayload = String(bytes: data, encoding: .utf8) else {
            throw Error.invalidPayload
        }
        return encodedPayload
    }

    static func decode(userInfo: [AnyHashable: Any]?) throws -> ReviewTriggerRequest {
        guard let payloadString = userInfo?[userInfoPayloadKey] as? String,
              let data = payloadString.data(using: .utf8)
        else {
            throw Error.invalidPayload
        }
        return try JSONDecoder().decode(ReviewTriggerRequest.self, from: data)
    }

    private static func reviewTriggerSource(
        from rawValue: String
    ) -> ReviewTriggerSource? {
        switch normalizedIdentifier(rawValue) {
        case "manual":
            return .manual
        case "postcommithook":
            return .postCommitHook
        case "pullrequestcommand":
            return .pullRequestCommand
        case "pullrequesthook":
            return .pullRequestHook
        case "workspaceopen":
            return .workspaceOpen
        case "scheduled":
            return .scheduled
        case "remotehost":
            return .remoteHost
        default:
            return nil
        }
    }

    private static func reviewTargetKind(
        from rawValue: String
    ) -> ReviewTargetKind? {
        switch normalizedIdentifier(rawValue) {
        case "unstagedchanges":
            return .unstagedChanges
        case "stagedchanges":
            return .stagedChanges
        case "lastcommit":
            return .lastCommit
        case "currentbranch":
            return .currentBranch
        case "commitrange":
            return .commitRange
        case "pullrequest":
            return .pullRequest
        case "selection":
            return .selection
        default:
            return nil
        }
    }

    private static func reviewTargetTitle(
        explicitTitle: String?,
        targetKind: ReviewTargetKind,
        commitSHA: String?,
        branchName: String?
    ) -> String {
        if let explicitTitle = normalizedOptionalString(explicitTitle) {
            return explicitTitle
        }
        switch targetKind {
        case .currentBranch:
            return branchName ?? targetKind.displayTitle
        case .lastCommit:
            if let commitSHA {
                return "Commit \(String(commitSHA.prefix(7)))"
            }
            return targetKind.displayTitle
        default:
            return targetKind.displayTitle
        }
    }

    private static func reviewTargetID(
        workspaceID: String?,
        repositoryRootPath: String,
        targetKind: ReviewTargetKind,
        commitSHA: String?
    ) -> String {
        let prefix = workspaceID ?? repositoryRootPath
        if let commitSHA {
            return "\(prefix):\(targetKind.rawValue):\(commitSHA)"
        }
        return "\(prefix):\(targetKind.rawValue)"
    }
}

private func normalizedIdentifier(
    _ value: String
) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .filter { $0.isLetter || $0.isNumber }
}

private func normalizedOptionalString(
    _ value: String?
) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
