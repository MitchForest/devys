public import Foundation
import CryptoKit
import LocalAuthentication
import Security
import Synchronization

// MARK: - What employees ask the owner (askOwner)

/// An amount in minor units (cents) of a three-letter currency.
public struct Amount: Equatable, Sendable {
    public let cents: Int
    public let currency: String

    public init(cents: Int, currency: String) {
        self.cents = cents
        self.currency = currency
    }

    /// "$12.99", or "12.99 EUR" in another currency.
    public var text: String {
        let value = String(format: "%.2f", Double(cents) / 100)
        return currency == "USD" ? "$\(value)" : "\(value) \(currency)"
    }
}

/// An employee's `askOwner` request, as its decision's input carries it.
public enum OwnerRequest: Equatable, Sendable {
    /// A consequential action stated exactly; with an amount, a spend approval to sign.
    case approve(action: String, counterparty: String, amount: Amount?, renewal: String?)
    /// Something only the owner can do in the business's browser (sign in, 2FA, CAPTCHA).
    case takeOver(reason: String, url: String?)
    /// A secret the business lacks, by the name it will be used by; `spend` asks for a card.
    case secret(name: String, why: String, spend: Bool)
    /// An app to connect (its id, registry name or address), and why, in one line.
    case connect(app: String, why: String)
}

extension JSONValue {
    fileprivate subscript(_ key: String) -> JSONValue? {
        if case .object(let fields) = self { fields[key] } else { nil }
    }

    fileprivate var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    fileprivate var bool: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }

    fileprivate var integer: Int? {
        if case .number(let value) = self, value == value.rounded(), abs(value) < 1e15 { Int(value) } else { nil }
    }
}

extension Decision {
    /// The `askOwner` request this decision carries, if it is one.
    public var request: OwnerRequest? {
        switch kind {
        case .approve:
            guard let action = input["action"]?.string, let counterparty = input["counterparty"]?.string else { return nil }
            let amount = input["amount"].flatMap { value -> Amount? in
                guard let cents = value["cents"]?.integer, let currency = value["currency"]?.string else { return nil }
                return Amount(cents: cents, currency: currency)
            }
            return .approve(action: action, counterparty: counterparty, amount: amount, renewal: input["renewal"]?.string)
        case .takeOver:
            guard let reason = input["reason"]?.string else { return nil }
            return .takeOver(reason: reason, url: input["url"]?.string)
        case .secret:
            guard let name = input["name"]?.string, let why = input["why"]?.string else { return nil }
            return .secret(name: name, why: why, spend: input["spend"]?.bool ?? false)
        case .connect:
            guard let app = input["app"]?.string, let why = input["why"]?.string else { return nil }
            return .connect(app: app, why: why)
        case .decision, .unknown:
            return nil
        }
    }

    /// An approve with an amount: only a signature from one of the owner's devices answers it.
    public var isSpend: Bool {
        if case .approve(_, _, .some, _) = request { true } else { false }
    }
}

// MARK: - Canonical payloads (src/authority/signing.ts)

/// JSON with sorted keys and no whitespace, strings escaped exactly as `JSON.stringify` escapes
/// them, so a device signs the very bytes the server verifies.
enum CanonicalJSON {
    enum Value {
        case string(String)
        case integer(Int)
        case null
    }

    static func object(_ fields: [String: Value]) -> String {
        "{" + fields.keys.sorted().map { key in
            quote(key) + ":" + {
                switch fields[key]! {
                case .string(let text): quote(text)
                case .integer(let number): String(number)
                case .null: "null"
                }
            }()
        }.joined(separator: ",") + "}"
    }

    static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

/// What a spend approval binds, and the exact text its signature covers.
public struct SpendApproval: Equatable, Sendable {
    public let decisionID: String
    public let businessID: String
    public let workItemID: String
    public let action: String
    public let counterparty: String
    public let amount: Amount
    public let renewal: String?
    public let expiresAt: String

    /// The spend a decision asks the owner to sign; nil for anything else.
    public init?(_ decision: Decision, businessID: String) {
        guard case .approve(let action, let counterparty, .some(let amount), let renewal) = decision.request,
              let workItemID = decision.workItemID
        else { return nil }
        self.decisionID = decision.id
        self.businessID = businessID
        self.workItemID = workItemID
        self.action = action
        self.counterparty = counterparty
        self.amount = amount
        self.renewal = renewal
        self.expiresAt = decision.expiresAt
    }

    public var canonical: String {
        CanonicalJSON.object([
            "action": .string(action),
            "amount_cents": .integer(amount.cents),
            "business": .string(businessID),
            "counterparty": .string(counterparty),
            "currency": .string(amount.currency),
            "decision": .string(decisionID),
            "expires_at": .string(expiresAt),
            "renewal": renewal.map(CanonicalJSON.Value.string) ?? .null,
            "type": .string("spend_approval"),
            "work_item": .string(workItemID)
        ])
    }

    /// What the Face ID or Touch ID prompt says: merchant and amount, then the action.
    public var reason: String {
        "approve \(amount.text) to \(counterparty): \(action)"
    }
}

/// The text an active key signs to let another of the person's devices sign.
public func keyEndorsement(person: String, key: DeviceKey) -> String {
    CanonicalJSON.object([
        "device": .string(key.device),
        "key": .string(key.id),
        "person": .string(person),
        "public_key": .string(key.publicKey),
        "type": .string("device_key")
    ])
}

// MARK: - Device keys

/// One of the person's devices' signing keys: active, or pending until an active one allows it.
public struct DeviceKey: Equatable, Sendable, Decodable, Identifiable {
    public enum Status: String, Equatable, Sendable, WireEnum { case pending, active, unknown }

    public let id: String
    /// The signed-in device it belongs to (`Device.id`).
    public let device: String
    public let label: String?
    /// X9.63 uncompressed P-256 public key, base64.
    public let publicKey: String
    public let status: Status
    public let createdAt: String
    /// This device's key.
    public let current: Bool

    public init(id: String, device: String, label: String? = nil, publicKey: String, status: Status, createdAt: String = "2026-10-21T00:00:00.000Z", current: Bool = false) {
        self.id = id
        self.device = device
        self.label = label
        self.publicKey = publicKey
        self.status = status
        self.createdAt = createdAt
        self.current = current
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        device = try container.decode(String.self, forKey: .device)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        publicKey = try container.decode(String.self, forKey: .publicKey)
        status = try container.decode(Status.self, forKey: .status)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        current = try container.decodeIfPresent(Bool.self, forKey: .current) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case id, device, label, status, current
        case publicKey = "public_key"
        case createdAt = "created_at"
    }
}

/// Why this device can't sign.
public enum SigningError: Error, Equatable, Sendable {
    /// No Secure Enclave (or no way to protect the key) on this device.
    case unavailable
    /// The key waits for an enrolled device to allow it (Settings → Devices there).
    case notAllowed
    /// Face ID or Touch ID was cancelled or failed.
    case cancelled
}

/// This device's signing key: a Secure Enclave P-256 key that never leaves the device, unlocked
/// by Face ID or Touch ID (or the device's password where it has no biometrics) for each
/// signature. Only its public key and its signatures are sent.
public struct DeviceSigner: Sendable {
    /// The public key (X9.63), creating the key on first use.
    public var publicKey: @Sendable () throws -> Data
    /// Signs after the system prompt shows `reason`; the signature is DER (X9.62).
    public var sign: @Sendable (_ payload: Data, _ reason: String) async throws -> Data

    public init(
        publicKey: @escaping @Sendable () throws -> Data,
        sign: @escaping @Sendable (Data, String) async throws -> Data
    ) {
        self.publicKey = publicKey
        self.sign = sign
    }

    /// The Secure Enclave key, its opaque blob kept in the Keychain (useless off this device).
    /// The iOS simulator has no Secure Enclave: debug simulator builds use a software key.
    public static func secureEnclave(store: SecretStore = .keychain(account: "signing-key")) -> Self {
        #if DEBUG && targetEnvironment(simulator)
            return software(store: store)
        #else
            @Sendable func accessControl() throws -> SecAccessControl {
                // Face ID or Touch ID enrolled now; without biometrics (a Mac mini without a Touch ID
                // keyboard), the device's own password.
                let biometric = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
                guard let access = SecAccessControlCreateWithFlags(
                    nil,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    biometric ? [.privateKeyUsage, .biometryCurrentSet] : [.privateKeyUsage, .userPresence],
                    nil
                ) else { throw SigningError.unavailable }
                return access
            }
            @Sendable func key(_ context: LAContext? = nil) throws -> SecureEnclave.P256.Signing.PrivateKey {
                guard SecureEnclave.isAvailable else { throw SigningError.unavailable }
                if let blob = store.load() {
                    return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context)
                }
                let created = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl(), authenticationContext: context)
                try store.save(created.dataRepresentation)
                return created
            }
            return Self(
                publicKey: { try key().publicKey.x963Representation },
                sign: { payload, reason in
                    let context = LAContext()
                    context.localizedReason = reason
                    do {
                        // The prompt names the exact spend; the key then signs without asking again.
                        _ = try await context.evaluateAccessControl(accessControl(), operation: .useKeySign, localizedReason: reason)
                        return try key(context).signature(for: payload).derRepresentation
                    } catch let error as LAError {
                        throw error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel ? SigningError.cancelled : error
                    }
                }
            )
        #endif
    }

    #if DEBUG
        /// A software P-256 key, for the simulator and tests only.
        public static func software(store: SecretStore = .inMemory()) -> Self {
            @Sendable func key() throws -> P256.Signing.PrivateKey {
                if let raw = store.load() { return try P256.Signing.PrivateKey(rawRepresentation: raw) }
                let created = P256.Signing.PrivateKey()
                try store.save(created.rawRepresentation)
                return created
            }
            return Self(
                publicKey: { try key().publicKey.x963Representation },
                sign: { payload, _ in try key().signature(for: payload).derRepresentation }
            )
        }
    #endif
}

/// One small secret in the Keychain, this device only, never synced. The signing key outlives
/// sign-outs: signing back in enrolls the same key again (allowed again if others exist).
public struct SecretStore: Sendable {
    public var load: @Sendable () -> Data?
    public var save: @Sendable (Data) throws -> Void

    public init(load: @escaping @Sendable () -> Data?, save: @escaping @Sendable (Data) throws -> Void) {
        self.load = load
        self.save = save
    }

    /// Like the device session: the data-protection Keychain, or the app-scoped login Keychain
    /// for a Mac build without the keychain-access-groups entitlement.
    public static func keychain(service: String = "com.mitchwhite.Devys.signing", account: String) -> Self {
        @Sendable func query(_ dataProtection: Bool) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecUseDataProtectionKeychain as String: dataProtection
            ]
        }
        @Sendable func read(_ dataProtection: Bool) -> Data? {
            var lookup = query(dataProtection)
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            return SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess ? item as? Data : nil
        }
        @Sendable func write(_ data: Data, _ dataProtection: Bool) -> OSStatus {
            SecItemDelete(query(dataProtection) as CFDictionary)
            var item = query(dataProtection)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(item as CFDictionary, nil)
        }
        return Self(
            load: { read(true) ?? read(false) },
            save: { data in
                var status = write(data, true)
                if status == errSecMissingEntitlement { status = write(data, false) }
                guard status == errSecSuccess else { throw DeviceSessionStoreError(status: status) }
            }
        )
    }

    public static func inMemory(_ initial: Data? = nil) -> Self {
        let box = DataBox(initial)
        return Self(
            load: { box.value.withLock { $0 } },
            save: { data in box.value.withLock { $0 = data } }
        )
    }
}

private final class DataBox: Sendable {
    let value: Mutex<Data?>
    init(_ initial: Data?) { value = Mutex(initial) }
}

// MARK: - The API

extension DevysHTTPClient {
    /// The signed-in person's device keys; `current` is this device's.
    public func deviceKeys(_ session: DeviceSession) async throws -> [DeviceKey] {
        struct Page: Decodable { let keys: [DeviceKey] }
        let page: Page = try await send(authorized(session, path: "api/device-keys"))
        return page.keys
    }

    /// Enrolls this device's public key: active if it is the person's first, else pending.
    public func enrollKey(_ session: DeviceSession, publicKey: Data) async throws -> DeviceKey {
        struct Body: Encodable {
            let publicKey: String
            enum CodingKeys: String, CodingKey { case publicKey = "public_key" }
        }
        return try await send(json(session, path: "api/device-keys", method: "POST", body: Body(publicKey: publicKey.base64EncodedString())))
    }

    /// Allows another device's pending key with this device's signature.
    public func endorseKey(_ session: DeviceSession, keyID: String, by signer: String, signature: Data) async throws {
        _ = try await raw(json(session, path: "api/device-keys/\(keyID)/endorse", method: "POST", body: Signed(keyID: signer, signature: signature)))
    }

    /// Approves a spend with this device's signature over its canonical payload.
    public func approveSpend(_ session: DeviceSession, businessID: String, decisionID: String, keyID: String, signature: Data) async throws {
        _ = try await raw(json(
            session,
            path: "api/businesses/\(businessID)/decisions/\(decisionID)/approve",
            method: "POST",
            body: Signed(keyID: keyID, signature: signature)
        ))
    }
}

private struct Signed: Encodable {
    let keyID: String
    let signature: String

    init(keyID: String, signature: Data) {
        self.keyID = keyID
        self.signature = signature.base64EncodedString()
    }

    enum CodingKeys: String, CodingKey {
        case keyID = "key_id"
        case signature
    }
}

// MARK: - Signing, as features use it

/// Signs as the owner from this device: enrolls its key once, then signs spend approvals and
/// allows the person's other devices. Features never see the key.
public struct SigningClient: Sendable {
    /// The person's device keys, this device's marked `current`.
    public var keys: @Sendable () async throws -> [DeviceKey]
    /// This device's key as the server knows it, enrolling it first if it isn't.
    public var enroll: @Sendable () async throws -> DeviceKey
    /// Signs the spend after Face ID or Touch ID and sends the approval.
    public var approveSpend: @Sendable (SpendApproval) async throws -> Void
    /// Allows another of the person's devices to sign.
    public var allow: @Sendable (_ key: DeviceKey, _ person: String) async throws -> Void
    /// Whether this device can sign at all (it has a Secure Enclave), and with what.
    public var biometry: @Sendable () -> String

    public init(
        keys: @escaping @Sendable () async throws -> [DeviceKey] = { [] },
        enroll: @escaping @Sendable () async throws -> DeviceKey,
        approveSpend: @escaping @Sendable (SpendApproval) async throws -> Void,
        allow: @escaping @Sendable (DeviceKey, String) async throws -> Void,
        biometry: @escaping @Sendable () -> String = { "Face ID" }
    ) {
        self.keys = keys
        self.enroll = enroll
        self.approveSpend = approveSpend
        self.allow = allow
        self.biometry = biometry
    }

    public static func live(_ hub: SessionHub, signer: DeviceSigner) -> Self {
        @Sendable func enrolled() async throws -> DeviceKey {
            let publicKey = try signer.publicKey().base64EncodedString()
            let keys = try await hub.call { api, session in try await api.deviceKeys(session) }
            if let mine = keys.first(where: { $0.current && $0.publicKey == publicKey }) { return mine }
            return try await hub.call { api, session in try await api.enrollKey(session, publicKey: Data(base64Encoded: publicKey)!) }
        }
        return Self(
            keys: { try await hub.call { api, session in try await api.deviceKeys(session) } },
            enroll: enrolled,
            approveSpend: { approval in
                let key = try await enrolled()
                guard key.status == .active else { throw SigningError.notAllowed }
                let signature = try await signer.sign(Data(approval.canonical.utf8), approval.reason)
                try await hub.call { api, session in
                    try await api.approveSpend(session, businessID: approval.businessID, decisionID: approval.decisionID, keyID: key.id, signature: signature)
                }
            },
            allow: { other, person in
                let key = try await enrolled()
                guard key.status == .active else { throw SigningError.notAllowed }
                let signature = try await signer.sign(Data(keyEndorsement(person: person, key: other).utf8), "allow \(other.label ?? "another device") to approve spending")
                try await hub.call { api, session in try await api.endorseKey(session, keyID: other.id, by: key.id, signature: signature) }
            },
            biometry: {
                let context = LAContext()
                _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
                return switch context.biometryType {
                case .faceID: "Face ID"
                case .touchID: "Touch ID"
                case .opticID: "Optic ID"
                default: "your password"
                }
            }
        )
    }

    public static let unimplemented = Self(
        enroll: { throw SigningError.unavailable },
        approveSpend: { _ in throw SigningError.unavailable },
        allow: { _, _ in throw SigningError.unavailable }
    )
}
