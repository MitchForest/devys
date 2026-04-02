import Foundation
import Security

enum SSHCredentialStoreError: Error, LocalizedError {
    case invalidEncoding
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Credential value must be UTF-8 encodable."
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown keychain error."
            return "Keychain operation failed (\(status)): \(message)"
        }
    }
}

final class SSHCredentialStore {
    enum Kind: String, CaseIterable, Sendable {
        case password
        case privateKey
        case passphrase
    }

    private let servicePrefix: String

    init(servicePrefix: String = "com.devys.ios.ssh") {
        self.servicePrefix = servicePrefix
    }

    func setSecret(_ value: String, id: String, kind: Kind) throws {
        guard let data = value.data(using: .utf8) else {
            throw SSHCredentialStoreError.invalidEncoding
        }

        let query = baseQuery(id: id, kind: kind)
        let updateAttributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw SSHCredentialStoreError.keychain(updateStatus)
        }

        var createAttributes = query
        createAttributes[kSecValueData as String] = data
        let createStatus = SecItemAdd(createAttributes as CFDictionary, nil)
        guard createStatus == errSecSuccess else {
            throw SSHCredentialStoreError.keychain(createStatus)
        }
    }

    func getSecret(id: String, kind: Kind) throws -> String? {
        var query = baseQuery(id: id, kind: kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SSHCredentialStoreError.keychain(status)
        }
        guard let data = item as? Data else {
            throw SSHCredentialStoreError.invalidEncoding
        }
        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(id: String, kind: Kind) throws {
        let status = SecItemDelete(baseQuery(id: id, kind: kind) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw SSHCredentialStoreError.keychain(status)
    }

    func deleteAllSecrets(for id: String) throws {
        for kind in Kind.allCases {
            try deleteSecret(id: id, kind: kind)
        }
    }
}

private extension SSHCredentialStore {
    func baseQuery(id: String, kind: Kind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(servicePrefix).\(kind.rawValue)",
            kSecAttrAccount as String: id
        ]
    }
}
