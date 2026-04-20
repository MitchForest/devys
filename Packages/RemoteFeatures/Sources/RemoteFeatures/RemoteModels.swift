import Foundation
import RemoteCore
import SSH

public enum RemoteAuthenticationMode: String, CaseIterable, Sendable {
    case password
    case privateKey
}

public struct RemoteRepositoryRecord: Equatable, Sendable, Identifiable {
    public var authority: RemoteRepositoryAuthority
    public var connection: SSHConnectionConfiguration

    public init(
        authority: RemoteRepositoryAuthority,
        connection: SSHConnectionConfiguration
    ) {
        self.authority = authority
        self.connection = connection
    }

    public var id: RemoteRepositoryAuthority.ID {
        authority.id
    }
}

public struct RemoteRepositoryEditorDraft: Equatable, Sendable {
    public var originalRepositoryID: RemoteRepositoryAuthority.ID?
    public var sshTarget: String
    public var displayName: String
    public var repositoryPath: String
    public var host: String
    public var port: String
    public var username: String
    public var authenticationMode: RemoteAuthenticationMode
    public var password: String
    public var privateKeyPEM: String
    public var privateKeyPassphrase: String

    public init(
        originalRepositoryID: RemoteRepositoryAuthority.ID? = nil,
        sshTarget: String = "",
        displayName: String = "",
        repositoryPath: String = "",
        host: String = "",
        port: String = "22",
        username: String = "",
        authenticationMode: RemoteAuthenticationMode = .password,
        password: String = "",
        privateKeyPEM: String = "",
        privateKeyPassphrase: String = ""
    ) {
        self.originalRepositoryID = originalRepositoryID
        self.sshTarget = sshTarget
        self.displayName = displayName
        self.repositoryPath = repositoryPath
        self.host = host
        self.port = port
        self.username = username
        self.authenticationMode = authenticationMode
        self.password = password
        self.privateKeyPEM = privateKeyPEM
        self.privateKeyPassphrase = privateKeyPassphrase
    }

    public init(record: RemoteRepositoryRecord) {
        self.originalRepositoryID = record.id
        self.sshTarget = record.authority.sshTarget
        self.displayName = record.authority.displayName
        self.repositoryPath = record.authority.repositoryPath
        self.host = record.connection.host
        self.port = String(record.connection.port)
        self.username = record.connection.username
        switch record.connection.authentication {
        case .password(let password):
            self.authenticationMode = .password
            self.password = password
            self.privateKeyPEM = ""
            self.privateKeyPassphrase = ""
        case .privateKey(let privateKeyPEM, let passphrase):
            self.authenticationMode = .privateKey
            self.password = ""
            self.privateKeyPEM = privateKeyPEM
            self.privateKeyPassphrase = passphrase ?? ""
        }
    }

    public var isSaveEnabled: Bool {
        !resolvedSSHTarget.isEmpty &&
            !repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            Int(port) != nil &&
            authenticationIsValid
    }

    public var resolvedSSHTarget: String {
        let trimmedTarget = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTarget.isEmpty {
            return trimmedTarget
        }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return "" }
        guard !trimmedUsername.isEmpty else { return trimmedHost }
        return "\(trimmedUsername)@\(trimmedHost)"
    }

    public func makeRecord() -> RemoteRepositoryRecord? {
        guard isSaveEnabled, let resolvedPort = Int(port) else { return nil }

        let authority = RemoteRepositoryAuthority(
            sshTarget: resolvedSSHTarget,
            displayName: displayName,
            repositoryPath: repositoryPath
        )
        let authentication: SSHAuthenticationMethod
        switch authenticationMode {
        case .password:
            authentication = .password(password)
        case .privateKey:
            let trimmedPassphrase = privateKeyPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            authentication = .privateKey(
                privateKeyPEM: privateKeyPEM,
                passphrase: trimmedPassphrase.isEmpty ? nil : trimmedPassphrase
            )
        }

        return RemoteRepositoryRecord(
            authority: authority,
            connection: SSHConnectionConfiguration(
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: resolvedPort,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                authentication: authentication
            )
        )
    }

    private var authenticationIsValid: Bool {
        switch authenticationMode {
        case .password:
            !password.isEmpty
        case .privateKey:
            !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public struct ActiveRemoteSession: Equatable, Sendable, Identifiable {
    public var session: SSHRemoteShellSession
    public var remoteAttachCommand: String
    public var connectRequestID: UUID
    public var errorMessage: String?

    public init(
        session: SSHRemoteShellSession,
        remoteAttachCommand: String,
        connectRequestID: UUID,
        errorMessage: String? = nil
    ) {
        self.session = session
        self.remoteAttachCommand = remoteAttachCommand
        self.connectRequestID = connectRequestID
        self.errorMessage = errorMessage
    }

    public var id: String {
        session.id
    }

    public var repositoryID: RemoteRepositoryAuthority.ID {
        session.repositoryID
    }

    public var worktreeID: RemoteWorktree.ID {
        session.worktreeID
    }

    public var title: String {
        session.title
    }
}

public struct RemoteHostTrustPrompt: Equatable, Sendable {
    public var context: SSHHostKeyValidationContext

    public init(context: SSHHostKeyValidationContext) {
        self.context = context
    }
}

public enum RemotePendingOperation: Equatable, Sendable {
    case refreshRepository(RemoteRepositoryAuthority.ID)
    case fetchRepository(RemoteRepositoryAuthority.ID)
    case pullWorktree(repositoryID: RemoteRepositoryAuthority.ID, worktreeID: RemoteWorktree.ID)
    case pushWorktree(repositoryID: RemoteRepositoryAuthority.ID, worktreeID: RemoteWorktree.ID)
    case discoverShellSessions(RemoteRepositoryAuthority.ID)
    case createWorktree(RemoteWorktreeDraft)
    case openSession(repositoryID: RemoteRepositoryAuthority.ID, worktreeID: RemoteWorktree.ID)
    case reconnectActiveSession
}
