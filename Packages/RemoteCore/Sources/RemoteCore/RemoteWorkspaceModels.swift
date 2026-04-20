import CryptoKit
import Foundation

public struct RemoteRepositoryAuthority: Equatable, Sendable, Codable, Identifiable {
    public typealias ID = String

    public let id: ID
    public var sshTarget: String
    public var displayName: String
    public var repositoryPath: String

    public init(
        sshTarget: String,
        displayName: String? = nil,
        repositoryPath: String
    ) {
        let trimmedTarget = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName = (displayName?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? URL(fileURLWithPath: trimmedPath).lastPathComponent

        self.id = Self.makeID(sshTarget: trimmedTarget, repositoryPath: trimmedPath)
        self.sshTarget = trimmedTarget
        self.displayName = resolvedDisplayName
        self.repositoryPath = trimmedPath
    }

    public var hostLabel: String {
        sshTarget
    }

    public var railDisplayName: String {
        "\(displayName) (\(hostLabel))"
    }

    public static func makeID(
        sshTarget: String,
        repositoryPath: String
    ) -> ID {
        let trimmedTarget = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmedTarget)::\(trimmedPath)"
    }
}

public struct RemoteWorktreeStatus: Equatable, Sendable, Codable {
    public var isDirty: Bool

    public init(isDirty: Bool = false) {
        self.isDirty = isDirty
    }
}

public struct RemoteWorktree: Equatable, Sendable, Codable, Identifiable {
    public typealias ID = String

    public let id: ID
    public var repositoryID: RemoteRepositoryAuthority.ID
    public var branchName: String
    public var remotePath: String
    public var detail: String
    public var isPrimary: Bool
    public var headSHA: String?
    public var status: RemoteWorktreeStatus

    public init(
        repositoryID: RemoteRepositoryAuthority.ID,
        branchName: String,
        remotePath: String,
        detail: String? = nil,
        isPrimary: Bool,
        headSHA: String? = nil,
        status: RemoteWorktreeStatus = RemoteWorktreeStatus()
    ) {
        let trimmedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = Self.makeID(repositoryID: repositoryID, remotePath: trimmedPath)
        self.repositoryID = repositoryID
        self.branchName = branchName
        self.remotePath = trimmedPath
        self.detail = detail ?? URL(fileURLWithPath: trimmedPath).lastPathComponent
        self.isPrimary = isPrimary
        self.headSHA = headSHA
        self.status = status
    }

    public static func makeID(
        repositoryID: RemoteRepositoryAuthority.ID,
        remotePath: String
    ) -> ID {
        "\(repositoryID)::\(remotePath.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

public struct RemoteWorktreeDraft: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var repositoryID: RemoteRepositoryAuthority.ID
    public var branchName: String
    public var startPoint: String
    public var directoryName: String

    public init(
        repositoryID: RemoteRepositoryAuthority.ID,
        branchName: String = "",
        startPoint: String = "origin/main",
        directoryName: String = "",
        id: UUID = UUID()
    ) {
        self.id = id
        self.repositoryID = repositoryID
        self.branchName = branchName
        self.startPoint = startPoint
        self.directoryName = directoryName
    }
}

public enum RemoteSessionNaming {
    public static func normalizedRemotePath(_ path: String) -> String {
        NSString(string: path).standardizingPath
    }

    public static func shellSessionName(
        target: String,
        remotePath: String,
        prefix: String = "devys"
    ) -> String {
        let source = "\(target)|\(normalizedRemotePath(remotePath))|shell"
        let digest = Insecure.MD5.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(prefix)-shell-\(digest.prefix(10))"
    }

    public static func defaultRemoteDirectoryName(
        repositoryName: String,
        branchName: String
    ) -> String {
        let sanitizedRepository = repositoryName.replacingOccurrences(
            of: "[^A-Za-z0-9._-]+",
            with: "-",
            options: .regularExpression
        )
        let sanitizedBranch = branchName.replacingOccurrences(
            of: "[^A-Za-z0-9._-]+",
            with: "-",
            options: .regularExpression
        )
        return "\(sanitizedRepository)-\(sanitizedBranch)"
    }
}
