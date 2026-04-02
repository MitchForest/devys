import Foundation

/// Represents an attachment in the chat composer.
///
/// Attachments can be files, git diffs, URLs, or code snippets.
/// They appear as removable chips above the text input.
public enum ComposerAttachment: Identifiable, Equatable, Sendable {
    /// A file attachment.
    case file(url: URL)

    /// A git diff attachment (staged or unstaged changes).
    case gitDiff(path: String, isStaged: Bool)

    /// A URL attachment.
    case url(URL)

    /// A code snippet attachment.
    case codeSnippet(content: String, language: String?, filename: String?)

    // MARK: - Identifiable

    public var id: String {
        switch self {
        case .file(let url):
            return "file:\(url.absoluteString)"
        case .gitDiff(let path, let isStaged):
            return "diff:\(path):\(isStaged)"
        case .url(let url):
            return "url:\(url.absoluteString)"
        case .codeSnippet(let content, _, let filename):
            return "snippet:\(filename ?? String(content.prefix(20).hashValue))"
        }
    }

    // MARK: - Display

    /// Display name shown in the chip.
    public var displayName: String {
        switch self {
        case .file(let url):
            return url.lastPathComponent
        case .gitDiff(let path, _):
            return (path as NSString).lastPathComponent
        case .url(let url):
            return url.host ?? url.absoluteString
        case .codeSnippet(_, _, let filename):
            return filename ?? "Code Snippet"
        }
    }

    /// SF Symbol icon name for the chip.
    public var iconName: String {
        switch self {
        case .file(let url):
            return fileIcon(for: url)
        case .gitDiff:
            return "arrow.left.arrow.right"
        case .url:
            return "link"
        case .codeSnippet:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Subtitle for additional context.
    public var subtitle: String? {
        switch self {
        case .file(let url):
            return url.deletingLastPathComponent().lastPathComponent
        case .gitDiff(_, let isStaged):
            return isStaged ? "Staged" : "Changes"
        case .url:
            return nil
        case .codeSnippet(_, let language, _):
            return language
        }
    }

    // MARK: - Helpers

    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift", "rs", "go", "py", "js", "ts", "java", "c", "cpp", "h":
            return "doc.text"
        case "json", "yaml", "yml", "toml", "xml":
            return "doc.badge.gearshape"
        case "md", "txt", "rtf":
            return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg", "webp":
            return "photo"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }
}
