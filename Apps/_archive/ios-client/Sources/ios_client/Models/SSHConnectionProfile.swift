import Foundation

enum SSHAuthMethodKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case password
    case privateKey

    var id: String { rawValue }

    var label: String {
        switch self {
        case .password:
            return "Password"
        case .privateKey:
            return "Private Key"
        }
    }
}

struct SSHAuthDescriptor: Codable, Sendable, Equatable {
    var kind: SSHAuthMethodKind
    var passwordCredentialID: String?
    var privateKeyCredentialID: String?
    var passphraseCredentialID: String?

    static func password(credentialID: String) -> SSHAuthDescriptor {
        SSHAuthDescriptor(
            kind: .password,
            passwordCredentialID: credentialID,
            privateKeyCredentialID: nil,
            passphraseCredentialID: nil
        )
    }

    static func privateKey(
        keyCredentialID: String,
        passphraseCredentialID: String? = nil
    ) -> SSHAuthDescriptor {
        SSHAuthDescriptor(
            kind: .privateKey,
            passwordCredentialID: nil,
            privateKeyCredentialID: keyCredentialID,
            passphraseCredentialID: passphraseCredentialID
        )
    }
}

struct SSHConnectionProfile: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var host: String
    var port: Int
    var username: String
    var auth: SSHAuthDescriptor
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var notes: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        auth: SSHAuthDescriptor,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastUsedAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.auth = auth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.notes = notes
    }
}

extension SSHConnectionProfile {
    mutating func markUpdated(now: Date = .now) {
        updatedAt = now
    }

    mutating func markUsed(now: Date = .now) {
        lastUsedAt = now
        updatedAt = now
    }
}
