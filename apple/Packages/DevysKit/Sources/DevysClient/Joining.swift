public import Foundation
import CryptoKit
import Network

// MARK: - Signing in without codes (.docs/AUTHORITY.md "Signing in")

/// A Mac running Devys: its name for the one button, "Connect to <name>", and its address.
public struct FoundMac: Equatable, Sendable, Codable {
    public let name: String
    public let server: URL

    public init(name: String, server: URL) {
        self.name = name
        self.server = server
    }
}

/// This device's request to join, waiting on the Mac: the two emoji both screens show.
/// The session token it chose stays in the session hub.
public struct JoinTicket: Equatable, Sendable {
    public let id: String
    public let mac: FoundMac
    public let match: [String]

    public init(id: String, mac: FoundMac, match: [String]) {
        self.id = id
        self.mac = mac
        self.match = match
    }
}

/// How a request to join ended. Allowed signs this device in; the others leave it at its button.
public enum JoinOutcome: Equatable, Sendable {
    case allowed
    case denied
    case expired
}

/// Another device asking to join, as signed-in devices are asked about it (`GET /api/joins`).
public struct JoinRequest: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let match: [String]

    public init(id: String, name: String, match: [String]) {
        self.id = id
        self.name = name
        self.match = match
    }
}

/// What a Devys server calls itself, and the address other devices reach it at (`GET /api/hello`).
public struct Hello: Equatable, Sendable, Decodable {
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

/// `devys://connect?server=<url>&name=<Mac>`: the QR code in Settings › Devices. It opens the
/// app on its one button, for a device the local network can't show the Mac to (Tailscale only).
public struct ConnectLink: Equatable, Sendable {
    public let mac: FoundMac

    public init(mac: FoundMac) {
        self.mac = mac
    }

    /// Only an http(s) server is accepted; a missing name reads as "your Mac".
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "devys", url.host()?.lowercased() == "connect",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "server" })?.value,
              let server = URL(string: raw), let scheme = server.scheme?.lowercased(),
              ["http", "https"].contains(scheme), server.host() != nil
        else { return nil }
        let name = items.first(where: { $0.name == "name" })?.value ?? ""
        self.init(mac: FoundMac(name: name.isEmpty ? "your Mac" : String(name.prefix(80)), server: server))
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "devys"
        components.host = "connect"
        components.queryItems = [
            URLQueryItem(name: "server", value: mac.server.absoluteString),
            URLQueryItem(name: "name", value: mac.name)
        ]
        // A server URL carries ":" and "/"; encode them so the link survives cameras.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: "/", with: "%2F")
        return components.url!
    }
}

/// On the Mac running Devys: the server's address and the key that signs the Mac app in as the
/// Mac's owner. `bun run local install` writes it (0600) in the server folder; only the owner's
/// macOS user reads it, and every process an employee starts is denied the folder. The app's
/// sandbox may read this one file (a read-only temporary exception for its path).
public struct OwnerFile: Equatable, Sendable, Decodable {
    public let server: URL
    public let key: String

    public init(server: URL, key: String) {
        self.server = server
        self.key = key
    }

    /// The file's path, under the user's real home (a sandboxed app's own home is its container).
    static var path: String {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return "\(home)/Library/Application Support/Devys Server/owner.json"
    }

    /// The owner file on this Mac, or nil on any other device.
    public static func read() -> Self? {
        #if DEBUG
            // QA: sign in as a development server's owner without its file.
            let environment = ProcessInfo.processInfo.environment
            if let raw = environment["DEVYS_LOCAL_SERVER"], let server = URL(string: raw), let key = environment["DEVYS_LOCAL_KEY"] {
                return Self(server: server, key: key)
            }
        #endif
        #if os(macOS)
            guard let data = FileManager.default.contents(atPath: path) else { return nil }
            return try? JSONDecoder().decode(Self.self, from: data)
        #else
            return nil
        #endif
    }
}

/// A session token this device chooses for itself, and the hash it sends: allowed, the server
/// makes that hash a session, so the token never leaves this device until it is used.
struct ChosenToken {
    let token: String
    let hash: String

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        token = bytes.map { String(format: "%02x", $0) }.joined()
        hash = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Finding the Mac

/// Finds Macs running Devys: announced on the local network (`_devys._tcp`, with the address in its
/// TXT record) and the last one this device used.
public struct DiscoveryClient: Sendable {
    /// Each Mac found on the local network, as it is found.
    public var macs: @Sendable () -> AsyncStream<FoundMac>
    public var lastKnown: @Sendable () -> FoundMac?
    public var remember: @Sendable (FoundMac) -> Void

    public init(
        macs: @escaping @Sendable () -> AsyncStream<FoundMac>,
        lastKnown: @escaping @Sendable () -> FoundMac?,
        remember: @escaping @Sendable (FoundMac) -> Void
    ) {
        self.macs = macs
        self.lastKnown = lastKnown
        self.remember = remember
    }

    private static let lastKey = "devys.lastMac"

    public static let live = Self(
        macs: {
            AsyncStream { continuation in
                let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_devys._tcp", domain: nil), using: .tcp)
                browser.browseResultsChangedHandler = { results, _ in
                    for result in results {
                        guard case .service(let name, _, _, _) = result.endpoint,
                              case .bonjour(let record) = result.metadata,
                              let raw = record["url"], let server = URL(string: raw)
                        else { continue }
                        continuation.yield(FoundMac(name: name, server: server))
                    }
                }
                browser.start(queue: DispatchQueue(label: "com.mitchwhite.Devys.discovery"))
                continuation.onTermination = { _ in browser.cancel() }
            }
        },
        lastKnown: {
            UserDefaults.standard.data(forKey: lastKey).flatMap { try? JSONDecoder().decode(FoundMac.self, from: $0) }
        },
        remember: { mac in
            if let data = try? JSONEncoder().encode(mac) { UserDefaults.standard.set(data, forKey: lastKey) }
        }
    )

    public static let none = Self(macs: { AsyncStream { $0.finish() } }, lastKnown: { nil }, remember: { _ in })
}

// MARK: - The API

extension DevysHTTPClient {
    /// What the server calls itself (no session).
    public func hello(server: URL) async throws -> Hello {
        try await send(URLRequest(url: server.appending(path: "api/hello")))
    }

    /// The Mac's owner's session, for the Mac app on the Mac running Devys (`OwnerFile`).
    public func localSession(_ owner: OwnerFile, name: String, label: String?) async throws -> DeviceSession {
        struct Body: Encodable { let key: String; let name: String; let label: String? }
        struct Issued: Decodable {
            let sessionToken: String
            enum CodingKeys: String, CodingKey { case sessionToken = "session_token" }
        }
        var request = URLRequest(url: owner.server.appending(path: "api/local/session"))
        request.httpMethod = "POST"
        let issued: Issued = try await send(withJSON(request, Body(key: owner.key, name: name, label: label)))
        return DeviceSession(server: owner.server, token: issued.sessionToken)
    }

    /// Asks the Mac to let this device join with the hash of a token it chose; returns the
    /// request's id and its two emoji.
    public func askToJoin(server: URL, name: String, sessionHash: String, publicKey: String?) async throws -> JoinRequest {
        struct Body: Encodable {
            let name: String
            let sessionHash: String
            let publicKey: String?
            enum CodingKeys: String, CodingKey {
                case name
                case sessionHash = "session_hash"
                case publicKey = "public_key"
            }
        }
        var request = URLRequest(url: server.appending(path: "api/joins"))
        request.httpMethod = "POST"
        return try await send(withJSON(request, Body(name: name, sessionHash: sessionHash, publicKey: publicKey)))
    }

    /// Where this device's request stands, asked with the token it chose.
    public func joinStatus(server: URL, id: String, token: String) async throws -> String {
        struct Status: Decodable { let status: String }
        var request = URLRequest(url: server.appending(path: "api/joins/\(id)"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        let status: Status = try await send(request)
        return status.status
    }

    /// Devices asking to join now.
    public func joins(_ session: DeviceSession) async throws -> [JoinRequest] {
        struct Page: Decodable { let joins: [JoinRequest] }
        let page: Page = try await send(authorized(session, path: "api/joins"))
        return page.joins
    }

    /// Allows or denies a device; allowed with an app's key, that key (to endorse at once).
    public func answerJoin(_ session: DeviceSession, id: String, allow: Bool) async throws -> DeviceKey? {
        struct Answered: Decodable { let key: DeviceKey? }
        let answered: Answered = try await send(authorized(session, path: "api/joins/\(id)/\(allow ? "allow" : "deny")", method: "POST"))
        return answered.key
    }

    /// A one-time link that signs a browser in as this person: `<server>/#signin=<token>`.
    public func signInLink(_ session: DeviceSession) async throws -> URL {
        struct Link: Decodable { let token: String }
        let link: Link = try await send(authorized(session, path: "api/devices/link", method: "POST"))
        var components = URLComponents(url: session.server, resolvingAgainstBaseURL: false)!
        components.path = "/"
        components.fragment = "signin=\(link.token)"
        return components.url!
    }
}
