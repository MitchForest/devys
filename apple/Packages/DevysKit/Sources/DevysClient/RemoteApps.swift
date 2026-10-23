public import Foundation

/// Where a remote app stands: added, signed in and waiting for the owner's Turn on, on, or its
/// sign-in stopped working (the owner reconnects).
public enum RemoteState: String, Equatable, Sendable, WireEnum {
    case connecting, review, lapsed, unknown
    /// Turned on: the owner's acceptance is its policy.
    case turnedOn = "on"
}

/// A remote app tool's line, as the owner sets it: on its own, asks first, or never.
public enum ToolLine: String, Equatable, Sendable, WireEnum, Encodable {
    case own, ask, never, unknown
}

/// A remote app as Needs you names it: its id, name and logo.
public struct AppBadge: Equatable, Sendable, Decodable {
    public let id: String
    public let name: String
    /// A path on the server (`/api/businesses/…/apps/logos/…`); nil draws a letter tile.
    public let logo: String?

    public init(id: String, name: String, logo: String? = nil) {
        self.id = id
        self.name = name
        self.logo = logo
    }
}

/// An app a search found: the business's own, or one in the MCP Registry.
public struct FoundApp: Equatable, Sendable, Decodable, Identifiable {
    /// What adding it takes: its id, its registry name or its address.
    public let app: String
    public let name: String
    public let description: String
    public let logo: String?
    public let installed: Bool
    public var id: String { app }
}

/// An app in the Connect apps list (outside services Devys knows well), its category and logo,
/// and whether the business has it on.
public struct ListedApp: Equatable, Sendable, Decodable, Identifiable {
    /// What adding it takes (its address), or the business's app id once added.
    public let app: String
    public let name: String
    public let description: String
    public let category: String
    /// A path on the server, loaded with this device's sign-in.
    public let logo: String
    public let installed: Bool
    public var id: String { app }

    public init(app: String, name: String, description: String, category: String, logo: String, installed: Bool = false) {
        self.app = app
        self.name = name
        self.description = description
        self.category = category
        self.logo = logo
        self.installed = installed
    }
}

/// The one review card: each tool's line and who uses the app.
public struct AppReview: Equatable, Sendable, Decodable {
    public struct Tool: Equatable, Sendable, Decodable, Identifiable {
        public let capability: String
        public let title: String
        public let description: String
        public let line: ToolLine
        /// Never available, whatever the owner chooses (it hands out payment credentials).
        public let fixed: Bool
        public var id: String { capability }
    }

    public struct User: Equatable, Sendable, Decodable, Identifiable {
        public let id: String
        public let name: String
        public let uses: Bool
    }

    public let app: AppEntry
    public let tools: [Tool]
    public let employees: [User]
}

/// What turning an app on sends: each tool's line, and who uses it.
public struct AppAcceptance: Equatable, Sendable, Encodable {
    public let lines: [String: ToolLine]
    public let employees: [String]

    public init(lines: [String: ToolLine], employees: [String]) {
        self.lines = lines
        self.employees = employees
    }
}

/// Connecting an app: the provider's sign-in page, or nil when it needed none.
public struct Connecting: Equatable, Sendable, Decodable {
    public let url: URL?
    public let app: AppEntry
}

extension DevysHTTPClient {
    public func searchApps(_ session: DeviceSession, businessID: String, query: String) async throws -> [FoundApp] {
        struct Page: Decodable { let apps: [FoundApp] }
        var request = authorized(session, path: "api/businesses/\(businessID)/apps/search")
        request.url?.append(queryItems: [URLQueryItem(name: "q", value: query)])
        let page: Page = try await send(request)
        return page.apps
    }

    /// The Connect apps list, in its order.
    public func listedApps(_ session: DeviceSession, businessID: String) async throws -> [ListedApp] {
        struct Page: Decodable { let apps: [ListedApp] }
        let page: Page = try await send(authorized(session, path: "api/businesses/\(businessID)/apps/listed"))
        return page.apps
    }

    public func addApp(_ session: DeviceSession, businessID: String, app: String) async throws -> AppEntry {
        struct Body: Encodable { let app: String }
        struct Changed: Decodable { let app: AppEntry }
        let changed: Changed = try await send(json(session, path: "api/businesses/\(businessID)/apps/add", method: "POST", body: Body(app: app)))
        return changed.app
    }

    /// Starts the provider's sign-in; its callback comes back to the app as `devys://apps/…`.
    public func connectApp(_ session: DeviceSession, businessID: String, appID: String) async throws -> Connecting {
        struct Body: Encodable { let native: Bool }
        return try await send(json(session, path: "api/businesses/\(businessID)/apps/\(appID)/connect", method: "POST", body: Body(native: true)))
    }

    public func appReview(_ session: DeviceSession, businessID: String, appID: String) async throws -> AppReview {
        try await send(authorized(session, path: "api/businesses/\(businessID)/apps/\(appID)/review"))
    }

    public func acceptApp(_ session: DeviceSession, businessID: String, appID: String, _ acceptance: AppAcceptance) async throws -> AppEntry {
        struct Changed: Decodable { let app: AppEntry }
        let changed: Changed = try await send(json(session, path: "api/businesses/\(businessID)/apps/\(appID)/accept", method: "POST", body: acceptance))
        return changed.app
    }

    /// An app's logo bytes (a path from the server), with this device's sign-in.
    public func appLogo(_ session: DeviceSession, path: String) async throws -> Data {
        try await raw(authorized(session, path: path.hasPrefix("/") ? String(path.dropFirst()) : path))
    }
}
