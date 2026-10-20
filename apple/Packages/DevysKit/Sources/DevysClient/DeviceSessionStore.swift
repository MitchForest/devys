import Foundation
import Security
import Synchronization

public struct DeviceSessionStoreError: Error, Equatable, Sendable {
    public let status: Int32
}

/// Keeps the device session in the Keychain, readable after first unlock and
/// never synced or migrated to another device.
public struct DeviceSessionStore: Sendable {
    public var load: @Sendable () -> DeviceSession?
    public var save: @Sendable (DeviceSession) throws -> Void
    public var clear: @Sendable () -> Void

    public init(
        load: @escaping @Sendable () -> DeviceSession?,
        save: @escaping @Sendable (DeviceSession) throws -> Void,
        clear: @escaping @Sendable () -> Void
    ) {
        self.load = load
        self.save = save
        self.clear = clear
    }

    /// Prefers the data-protection Keychain. A Mac build without a
    /// keychain-access-groups entitlement (ad-hoc local signing) falls back to
    /// the app-scoped login Keychain rather than silently losing the session.
    public static func keychain(service: String = "com.mitchwhite.Devys.session") -> Self {
        @Sendable func query(dataProtection: Bool) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "device",
                kSecUseDataProtectionKeychain as String: dataProtection
            ]
        }
        @Sendable func read(dataProtection: Bool) -> DeviceSession? {
            var lookup = query(dataProtection: dataProtection)
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            // Never show a Keychain password prompt. An item the system won't hand
            // over silently reads as signed out, and the device enrolls again.
            // The login keychain honours only this older flag, not an LAContext.
            lookup[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            var item: CFTypeRef?
            guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data
            else { return nil }
            return try? JSONDecoder().decode(DeviceSession.self, from: data)
        }
        @Sendable func write(_ data: Data, dataProtection: Bool) -> OSStatus {
            SecItemDelete(query(dataProtection: dataProtection) as CFDictionary)
            var item = query(dataProtection: dataProtection)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(item as CFDictionary, nil)
        }
        return Self(
            load: { read(dataProtection: true) ?? read(dataProtection: false) },
            save: { session in
                let data = try JSONEncoder().encode(session)
                var status = write(data, dataProtection: true)
                if status == errSecMissingEntitlement { status = write(data, dataProtection: false) }
                guard status == errSecSuccess else { throw DeviceSessionStoreError(status: status) }
            },
            clear: {
                SecItemDelete(query(dataProtection: true) as CFDictionary)
                SecItemDelete(query(dataProtection: false) as CFDictionary)
            }
        )
    }

    public static func inMemory(_ initial: DeviceSession? = nil) -> Self {
        let box = SessionBox(initial)
        return Self(
            load: { box.stored.withLock { $0 } },
            save: { session in box.stored.withLock { $0 = session } },
            clear: { box.stored.withLock { $0 = nil } }
        )
    }
}

private final class SessionBox: Sendable {
    let stored: Mutex<DeviceSession?>

    init(_ value: DeviceSession?) {
        stored = Mutex(value)
    }
}
