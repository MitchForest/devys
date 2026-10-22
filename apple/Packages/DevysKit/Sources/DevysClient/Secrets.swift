public import Foundation

// MARK: - Secrets by name (the vault)

/// A business's secret as Settings lists it: its name and kind, never its value.
public struct SecretEntry: Equatable, Sendable, Decodable, Identifiable {
    public enum Kind: String, Equatable, Sendable, WireEnum {
        case secret, spend, unknown
    }

    public let name: String
    /// `spend` is a card, filled at a checkout only against a signed spend approval.
    public let kind: Kind
    /// The person who added it.
    public let addedBy: String
    public let addedAt: String
    /// When an employee last used it; nil until then.
    public let lastUsedAt: String?

    public var id: String { name }

    public init(name: String, kind: Kind, addedBy: String = "", addedAt: String = "2026-10-21T00:00:00.000Z", lastUsedAt: String? = nil) {
        self.name = name
        self.kind = kind
        self.addedBy = addedBy
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt
    }

    enum CodingKeys: String, CodingKey {
        case name, kind
        case addedBy = "added_by"
        case addedAt = "added_at"
        case lastUsedAt = "last_used_at"
    }
}

/// A card as the secure entry sheet takes it; stored as one `spend` secret.
public struct CardEntry: Equatable, Sendable, Encodable {
    public let number: String
    /// `MM/YY`.
    public let expiry: String
    /// Nil when the owner keeps the security code to themselves.
    public let cvc: String?
    public let name: String
    public let postal: String

    public init(number: String, expiry: String, cvc: String?, name: String, postal: String) {
        self.number = number
        self.expiry = expiry
        self.cvc = cvc
        self.name = name
        self.postal = postal
    }
}

/// What the secure entry sheet sends: a named value, or a card. Its `description` never shows
/// the value, so a stray log or debugger print can't either.
public struct NewSecret: Equatable, Sendable, Encodable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Value: Equatable, Sendable {
        case secret(String)
        case card(CardEntry)
    }

    /// The most a plain secret may hold.
    public static let maximumLength = 16_000

    public let name: String
    public let value: Value

    public init(name: String, value: Value) {
        self.name = name
        self.value = value
    }

    /// Capitals, digits and underscores, starting with a capital (how employees name it).
    public static func isName(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Z][A-Z0-9_]{0,63}/) != nil
    }

    public var description: String { "NewSecret(\(name), value hidden)" }
    public var debugDescription: String { description }

    enum CodingKeys: String, CodingKey { case name, kind, value, card }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        switch value {
        case .secret(let text):
            try container.encode("secret", forKey: .kind)
            try container.encode(text, forKey: .value)
        case .card(let card):
            try container.encode("spend", forKey: .kind)
            try container.encode(card, forKey: .card)
        }
    }
}

/// `GET`, `POST …/secrets` and `DELETE …/secrets/:name`.
struct SecretsPage: Decodable {
    let secrets: [SecretEntry]
}

extension DevysHTTPClient {
    public func secrets(_ session: DeviceSession, businessID: String) async throws -> [SecretEntry] {
        let page: SecretsPage = try await send(authorized(session, path: "api/businesses/\(businessID)/secrets"))
        return page.secrets
    }

    /// Adds (or replaces) a secret; the value goes straight to the vault and is never answered back.
    public func addSecret(_ session: DeviceSession, businessID: String, _ secret: NewSecret) async throws -> [SecretEntry] {
        let page: SecretsPage = try await send(json(session, path: "api/businesses/\(businessID)/secrets", method: "POST", body: secret))
        return page.secrets
    }

    public func removeSecret(_ session: DeviceSession, businessID: String, name: String) async throws -> [SecretEntry] {
        let page: SecretsPage = try await send(authorized(session, path: "api/businesses/\(businessID)/secrets/\(name)", method: "DELETE"))
        return page.secrets
    }
}
