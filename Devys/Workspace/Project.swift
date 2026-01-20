import Foundation

/// Represents a project context (a rooted folder with optional git context).
///
/// Projects are the primary organizational unit in Devys. Each project
/// corresponds to a folder on disk and can have associated git metadata.
public struct Project: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Unique identifier for this project
    public let id: UUID

    /// Display name for the project (defaults to folder name)
    public var name: String

    /// Root folder URL for the project
    public var rootURL: URL

    /// When the project was first opened
    public var createdAt: Date

    /// Current git branch name (nil if not a git repo)
    public var gitBranch: String?

    /// Git remote URL (nil if no remote configured)
    public var gitRemoteURL: URL?

    // MARK: - Computed Properties

    /// Whether this is a git repository
    public var isGitRepository: Bool {
        gitBranch != nil
    }

    /// Short display name for tabs (folder name only)
    public var shortName: String {
        rootURL.lastPathComponent
    }

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        rootURL: URL,
        name: String? = nil,
        createdAt: Date = Date(),
        gitBranch: String? = nil,
        gitRemoteURL: URL? = nil
    ) {
        self.id = id
        self.rootURL = rootURL
        self.name = name ?? rootURL.lastPathComponent
        self.createdAt = createdAt
        self.gitBranch = gitBranch
        self.gitRemoteURL = gitRemoteURL
    }

    // MARK: - Factory Methods

    /// Create a project from a folder URL, validating it exists.
    ///
    /// - Parameter url: The folder URL to create a project from
    /// - Returns: A new Project instance
    /// - Throws: `ProjectError` if the URL is not a valid directory
    public static func create(from url: URL) throws -> Project {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ProjectError.folderNotFound(url)
        }
        guard isDirectory.boolValue else {
            throw ProjectError.notADirectory(url)
        }

        var project = Project(rootURL: url)

        // Attempt to detect git branch
        project.gitBranch = detectGitBranch(at: url)
        project.gitRemoteURL = detectGitRemoteURL(at: url)

        return project
    }

    // MARK: - Git Detection

    /// Detect the current git branch for a repository.
    private static func detectGitBranch(at url: URL) -> String? {
        let gitHeadURL = url.appendingPathComponent(".git/HEAD")
        guard let headContents = try? String(contentsOf: gitHeadURL, encoding: .utf8) else {
            return nil
        }

        // HEAD file contains "ref: refs/heads/branch-name" or a commit hash
        let trimmed = headContents.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }

        // Detached HEAD - return short hash
        if trimmed.count >= 7 {
            return String(trimmed.prefix(7))
        }

        return nil
    }

    /// Detect the git remote URL for a repository.
    private static func detectGitRemoteURL(at url: URL) -> URL? {
        let gitConfigURL = url.appendingPathComponent(".git/config")
        guard let configContents = try? String(contentsOf: gitConfigURL, encoding: .utf8) else {
            return nil
        }

        // Simple parsing: look for [remote "origin"] section and url =
        let lines = configContents.components(separatedBy: .newlines)
        var inOriginSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "[remote \"origin\"]" {
                inOriginSection = true
                continue
            }

            if inOriginSection {
                if trimmed.hasPrefix("[") {
                    // Entered a new section, stop looking
                    break
                }

                if trimmed.hasPrefix("url = ") {
                    let urlString = String(trimmed.dropFirst("url = ".count))
                    return URL(string: urlString)
                }
            }
        }

        return nil
    }
}

// MARK: - Project Error

/// Errors that can occur when creating or validating projects.
public enum ProjectError: LocalizedError, Equatable, Sendable {
    case notADirectory(URL)
    case folderNotFound(URL)
    case permissionDenied(URL)

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let url):
            return "'\(url.lastPathComponent)' is not a folder"
        case .folderNotFound(let url):
            return "Folder not found: \(url.path)"
        case .permissionDenied(let url):
            return "Permission denied: \(url.path)"
        }
    }
}
