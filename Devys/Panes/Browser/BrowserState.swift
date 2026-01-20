import Foundation

/// State for a browser pane.
///
/// Contains both configuration (persisted) and runtime state (transient).
/// Only the URL is encoded/decoded for persistence.
public struct BrowserState: Equatable, Codable, Hashable {
    // MARK: - Configuration (Persisted)

    /// Current URL
    public var url: URL

    // MARK: - Runtime State (Transient)

    /// Page title
    public var title: String

    /// Whether page is currently loading
    public var isLoading: Bool

    /// Load progress (0.0 to 1.0)
    public var loadProgress: Double

    /// Whether browser can navigate back
    public var canGoBack: Bool

    /// Whether browser can navigate forward
    public var canGoForward: Bool

    /// Error message if load failed
    public var errorMessage: String?

    // MARK: - Initialization

    public init(
        url: URL = URL(string: "http://localhost:3000")!,  // swiftlint:disable:this force_unwrapping
        title: String = "Browser"
    ) {
        self.url = url
        self.title = title
        self.isLoading = false
        self.loadProgress = 0
        self.canGoBack = false
        self.canGoForward = false
        self.errorMessage = nil
    }

    /// Convenience initializer for localhost with specific port
    public static func localhost(port: Int) -> BrowserState {
        BrowserState(url: URL(string: "http://localhost:\(port)")!)  // swiftlint:disable:this force_unwrapping
    }

    // MARK: - Codable (Only persist URL)

    enum CodingKeys: String, CodingKey {
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        // Runtime state defaults
        title = "Browser"
        isLoading = false
        loadProgress = 0
        canGoBack = false
        canGoForward = false
        errorMessage = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
    }
}

// MARK: - URL Helpers

extension BrowserState {
    /// Normalize a URL string (add https:// if no scheme)
    public static func normalizeURLString(_ string: String) -> URL? {
        var urlString = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // If no scheme, add https:// (unless localhost)
        if !urlString.contains("://") {
            if urlString.hasPrefix("localhost") || urlString.hasPrefix("127.0.0.1") {
                urlString = "http://" + urlString
            } else {
                urlString = "https://" + urlString
            }
        }

        return URL(string: urlString)
    }

    /// Common localhost ports for dev servers
    public static let commonPorts: [(name: String, port: Int)] = [
        ("Next.js / React", 3000),
        ("Vite", 5173),
        ("Angular", 4200),
        ("Django / Python", 8000),
        ("Generic", 8080),
        ("Rails", 3001)
    ]
}
