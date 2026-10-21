public import Dependencies
public import Foundation

/// The business's browser at a glance: open, where, and which work drives it.
public struct BrowserStatus: Equatable, Sendable, Decodable {
    public let open: Bool
    public let url: String?
    public let title: String?
    /// The work item (or conversation) the last employee action served.
    public let driver: String?

    public init(open: Bool, url: String? = nil, title: String? = nil, driver: String? = nil) {
        self.open = open
        self.url = url
        self.title = title
        self.driver = driver
    }
}

/// A picture of the visible page: a JPEG in CSS pixels, so a tap maps straight to a click.
public struct BrowserPicture: Equatable, Sendable, Decodable {
    public let jpeg: String
    public let width: Double
    public let height: Double

    public var data: Data? { Data(base64Encoded: jpeg) }
}

/// The owner acting on the page directly; not recorded.
public enum BrowserInput: Sendable, Encodable {
    case click(x: Double, y: Double)
    case type(String)
    case key(String)

    private enum Key: String, CodingKey { case kind, x, y, text, key }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case let .click(x, y):
            try container.encode("click", forKey: .kind)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case let .type(text):
            try container.encode("type", forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .key(key):
            try container.encode("key", forKey: .kind)
            try container.encode(key, forKey: .key)
        }
    }
}

extension DevysHTTPClient {
    public func browserStatus(_ session: DeviceSession, businessID: String) async throws -> BrowserStatus {
        try await send(authorized(session, path: "api/businesses/\(businessID)/browser"))
    }

    public func browserPicture(_ session: DeviceSession, businessID: String) async throws -> BrowserPicture {
        try await send(authorized(session, path: "api/businesses/\(businessID)/browser/screenshot"))
    }

    public func browserInput(_ session: DeviceSession, businessID: String, _ input: BrowserInput) async throws {
        _ = try await raw(json(session, path: "api/businesses/\(businessID)/browser/input", method: "POST", body: input))
    }
}

/// The business's browser: status, a live picture, and the owner's own input.
public struct BrowserClient: Sendable {
    public var status: @Sendable (_ businessID: String) async throws -> BrowserStatus
    public var picture: @Sendable (_ businessID: String) async throws -> BrowserPicture
    public var input: @Sendable (_ businessID: String, BrowserInput) async throws -> Void

    public init(
        status: @escaping @Sendable (String) async throws -> BrowserStatus,
        picture: @escaping @Sendable (String) async throws -> BrowserPicture,
        input: @escaping @Sendable (String, BrowserInput) async throws -> Void
    ) {
        self.status = status
        self.picture = picture
        self.input = input
    }

    public static func live(_ hub: SessionHub) -> Self {
        Self(
            status: { business in try await hub.call { api, session in try await api.browserStatus(session, businessID: business) } },
            picture: { business in try await hub.call { api, session in try await api.browserPicture(session, businessID: business) } },
            input: { business, input in try await hub.call { api, session in try await api.browserInput(session, businessID: business, input) } }
        )
    }

    /// No browser: tests and previews.
    public static let none = Self(
        status: { _ in BrowserStatus(open: false) },
        picture: { _ in throw DevysHTTPError.rejected(status: 503, message: "No browser.") },
        input: { _, _ in }
    )
}

nonisolated enum BrowserClientKey: DependencyKey {
    static let liveValue = BrowserClient.live(.shared)
    static let testValue = BrowserClient.none
    static let previewValue = BrowserClient.none
}

extension DependencyValues {
    public var browserClient: BrowserClient {
        get { self[BrowserClientKey.self] }
        set { self[BrowserClientKey.self] = newValue }
    }
}
