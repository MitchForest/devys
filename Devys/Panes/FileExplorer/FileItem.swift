import Foundation
import UniformTypeIdentifiers

/// Represents a file or directory in the file tree.
///
/// This is a reference type (class) for efficient use with NSOutlineView
/// and to maintain parent-child relationships in the tree structure.
@MainActor
public final class FileItem: Identifiable, Hashable {
    /// Unique identifier
    public let id: UUID

    /// File system URL
    public let url: URL

    /// Whether this is a directory
    public let isDirectory: Bool

    /// Parent item (nil for root)
    public weak var parent: FileItem?

    /// Child items (nil = not loaded, empty = no children)
    public var children: [FileItem]?

    /// Whether the directory is expanded in the UI
    public var isExpanded: Bool = false

    /// Git status for this file
    public var gitStatus: GitFileStatus?

    // MARK: - Computed Properties

    /// File or folder name
    public var name: String {
        url.lastPathComponent
    }

    /// Whether this item has loadable children
    public var isExpandable: Bool {
        isDirectory
    }

    /// Whether children have been loaded
    public var isLoaded: Bool {
        children != nil
    }

    /// SF Symbol name for this file type
    public var iconName: String {
        if isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }
        return FileItem.iconName(for: url)
    }

    /// File extension (lowercased)
    public var fileExtension: String {
        url.pathExtension.lowercased()
    }

    /// Whether this is a hidden file (starts with dot)
    public var isHidden: Bool {
        name.hasPrefix(".")
    }

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        url: URL,
        isDirectory: Bool,
        parent: FileItem? = nil,
        gitStatus: GitFileStatus? = nil
    ) {
        self.id = id
        self.url = url
        self.isDirectory = isDirectory
        self.parent = parent
        self.gitStatus = gitStatus
    }

    /// Create a FileItem from a URL, detecting if it's a directory
    public convenience init(url: URL, parent: FileItem? = nil) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.init(url: url, isDirectory: isDir.boolValue, parent: parent)
    }

    // MARK: - Children Loading

    /// Load children from disk (for directories only)
    public func loadChildren(showHidden: Bool = false) {
        guard isDirectory else {
            children = nil
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: showHidden ? [] : [.skipsHiddenFiles]
            )

            children = contents
                .filter { !shouldIgnore($0) }
                .map { FileItem(url: $0, parent: self) }
                .sorted()

        } catch {
            children = []
        }
    }

    /// Reload children from disk
    public func reloadChildren(showHidden: Bool = false) {
        children = nil
        loadChildren(showHidden: showHidden)
    }

    /// Unload children to free memory
    public func unloadChildren() {
        children = nil
        isExpanded = false
    }

    // MARK: - File Filtering

    /// Files/folders to ignore in the tree
    private func shouldIgnore(_ url: URL) -> Bool {
        let name = url.lastPathComponent

        // Always ignore these
        let ignored: Set<String> = [
            ".DS_Store",
            ".git",
            ".svn",
            ".hg",
            "node_modules",
            ".build",
            "DerivedData",
            "Pods",
            ".swiftpm"
        ]

        return ignored.contains(name)
    }

    // MARK: - Icon Mapping

    /// Get SF Symbol name for a file URL
    private static func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        // Swift/Xcode files
        switch ext {
        case "swift": return "swift"
        case "xcodeproj", "xcworkspace": return "hammer"
        case "xib", "storyboard": return "uiwindow.split.2x1"
        case "xcconfig": return "gearshape"
        case "entitlements", "plist": return "list.bullet.rectangle"
        case "xcassets": return "photo.on.rectangle"
        default: break
        }

        // Web files
        switch ext {
        case "html", "htm": return "globe"
        case "css", "scss", "sass", "less": return "paintbrush"
        case "js", "jsx", "ts", "tsx": return "curlybraces"
        case "json": return "curlybraces.square"
        case "vue", "svelte": return "v.square"
        default: break
        }

        // Config files
        switch ext {
        case "yaml", "yml", "toml": return "doc.text"
        case "env": return "key"
        case "gitignore", "dockerignore": return "eye.slash"
        default: break
        }

        // Documentation
        switch ext {
        case "md", "markdown", "txt", "rtf": return "doc.text"
        case "pdf": return "doc.richtext"
        default: break
        }

        // Images
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "ico":
            return "photo"
        default: break
        }

        // Data files
        switch ext {
        case "sqlite", "db", "realm": return "cylinder"
        case "csv": return "tablecells"
        case "xml": return "chevron.left.forwardslash.chevron.right"
        default: break
        }

        // Other code
        switch ext {
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "rb": return "diamond"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "rs": return "gearshape.2"
        case "c", "cpp", "h", "hpp", "m", "mm": return "chevron.left.forwardslash.chevron.right"
        case "java", "kt", "kts": return "cup.and.saucer"
        case "sh", "bash", "zsh": return "terminal"
        case "sql": return "cylinder"
        default: break
        }

        // Archives
        switch ext {
        case "zip", "tar", "gz", "rar", "7z": return "doc.zipper"
        default: break
        }

        // Default
        return "doc"
    }

    // MARK: - Hashable & Equatable

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public nonisolated static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Comparable (for sorting)

extension FileItem: Comparable {
    public nonisolated static func < (lhs: FileItem, rhs: FileItem) -> Bool {
        // Directories first, then alphabetical (case-insensitive)
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }
        return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(
            rhs.url.lastPathComponent
        ) == .orderedAscending
    }
}

// MARK: - Git File Status

/// Git status for a file in the working tree
public enum GitFileStatus: String, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case ignored = "!"
    case unmerged = "U"

    /// Color for this status
    public var color: String {
        switch self {
        case .modified: return "orange"
        case .added, .untracked: return "green"
        case .deleted: return "red"
        case .renamed, .copied: return "blue"
        case .unmerged: return "purple"
        case .ignored: return "gray"
        }
    }

    /// SF Symbol for this status
    public var iconName: String {
        switch self {
        case .modified: return "pencil.circle.fill"
        case .added: return "plus.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        case .copied: return "doc.on.doc.fill"
        case .untracked: return "questionmark.circle.fill"
        case .unmerged: return "exclamationmark.triangle.fill"
        case .ignored: return "eye.slash.circle.fill"
        }
    }
}
