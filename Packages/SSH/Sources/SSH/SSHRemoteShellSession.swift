import Foundation
import RemoteCore

public struct SSHRemoteShellSession: Sendable, Equatable, Identifiable {
    public let repositoryID: RemoteRepositoryAuthority.ID
    public let worktreeID: RemoteWorktree.ID
    public let branchName: String
    public let remotePath: String
    public let sessionName: String
    public let attachedClientCount: Int
    public let createdAt: Date?

    public init(
        repositoryID: RemoteRepositoryAuthority.ID,
        worktreeID: RemoteWorktree.ID,
        branchName: String,
        remotePath: String,
        sessionName: String,
        attachedClientCount: Int = 0,
        createdAt: Date? = nil
    ) {
        self.repositoryID = repositoryID
        self.worktreeID = worktreeID
        self.branchName = branchName
        self.remotePath = remotePath
        self.sessionName = sessionName
        self.attachedClientCount = max(0, attachedClientCount)
        self.createdAt = createdAt
    }

    public var id: String {
        "\(repositoryID)::\(worktreeID)"
    }

    public var title: String {
        "\(branchName) • Shell"
    }

    public var isAttached: Bool {
        attachedClientCount > 0
    }
}

public struct SSHRemotePreparedShellSession: Sendable, Equatable {
    public let session: SSHRemoteShellSession
    public let remoteAttachCommand: String

    public init(
        session: SSHRemoteShellSession,
        remoteAttachCommand: String
    ) {
        self.session = session
        self.remoteAttachCommand = remoteAttachCommand
    }
}
