import Foundation

/// State for a terminal pane.
///
/// Contains both configuration (persisted) and runtime state (transient).
/// Only configuration properties are encoded/decoded for persistence.
public struct TerminalState: Equatable, Codable, Hashable {
    // MARK: - Configuration (Persisted)

    /// Current working directory
    public var workingDirectory: URL

    /// Shell executable path
    public var shell: String

    /// Scrollback buffer size
    public var scrollbackLines: Int

    // MARK: - Runtime State (Transient)

    /// Terminal title (from shell escape sequence)
    public var title: String

    /// Whether the shell process has exited
    public var hasExited: Bool

    /// Exit code (if exited)
    public var exitCode: Int32?

    // MARK: - Initialization

    public init(
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        title: String = "Terminal",
        scrollbackLines: Int = 10_000
    ) {
        self.workingDirectory = workingDirectory
        self.shell = shell
        self.title = title
        self.scrollbackLines = scrollbackLines
        self.hasExited = false
        self.exitCode = nil
    }

    // MARK: - Codable (Only persist configuration)

    enum CodingKeys: String, CodingKey {
        case workingDirectory
        case shell
        case scrollbackLines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workingDirectory = try container.decode(URL.self, forKey: .workingDirectory)
        shell = try container.decode(String.self, forKey: .shell)
        scrollbackLines = try container.decode(Int.self, forKey: .scrollbackLines)
        // Runtime state defaults
        title = "Terminal"
        hasExited = false
        exitCode = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workingDirectory, forKey: .workingDirectory)
        try container.encode(shell, forKey: .shell)
        try container.encode(scrollbackLines, forKey: .scrollbackLines)
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(workingDirectory)
        hasher.combine(shell)
        hasher.combine(scrollbackLines)
        hasher.combine(title)
        hasher.combine(hasExited)
        hasher.combine(exitCode)
    }
}

// MARK: - Path Escaping Helper

extension TerminalState {
    /// Escape a file path for safe insertion into terminal
    /// Handles spaces and special characters
    public static func escapePath(_ path: String) -> String {
        // Characters that need escaping in shell
        let specialChars = CharacterSet(charactersIn: " '\"\\$`!&;|<>()[]{}*?#~")

        var escaped = ""
        for char in path.unicodeScalars {
            if specialChars.contains(char) {
                escaped += "\\"
            }
            escaped += String(char)
        }
        return escaped
    }

    /// Escape multiple paths and join with spaces
    public static func escapePaths(_ paths: [String]) -> String {
        paths.map { escapePath($0) }.joined(separator: " ")
    }
}
