import Foundation
import SwiftUI

/// The type of content a pane displays.
///
/// Each pane type has its own state struct that holds
/// configuration and runtime state for that pane type.
public enum PaneType: Equatable {
    case terminal(TerminalState)
    case browser(BrowserPaneState)
    case fileExplorer(FileExplorerPaneState)
    case codeEditor(CodeEditorPaneState)
    case git(GitPaneState)
    case diff(DiffPaneState)

    // MARK: - Properties

    /// SF Symbol name for this pane type
    public var iconName: String {
        switch self {
        case .terminal: return "terminal"
        case .browser: return "globe"
        case .fileExplorer: return "folder"
        case .codeEditor: return "doc.text"
        case .git: return "arrow.triangle.branch"
        case .diff: return "doc.text.magnifyingglass"
        }
    }

    /// Default title for new panes of this type
    public var defaultTitle: String {
        switch self {
        case .terminal: return "Terminal"
        case .browser(let state): return state.url.host ?? "Browser"
        case .fileExplorer(let state): return state.rootURL?.lastPathComponent ?? "Files"
        case .codeEditor(let state): return state.fileURL?.lastPathComponent ?? "Untitled"
        case .git: return "Git"
        case .diff(let state): return state.filePath ?? "Diff"
        }
    }

    /// Whether this pane type should be scoped to a project
    ///
    /// Project-scoped panes will:
    /// - Inherit the active project's root URL
    /// - Show a project indicator in the title bar
    /// - Be associated with a specific project tab
    public var isProjectScoped: Bool {
        switch self {
        case .terminal, .fileExplorer, .git, .diff:
            return true
        case .browser, .codeEditor:
            return false
        }
    }
}

// MARK: - Pane State Types

// Note: TerminalState is defined in Panes/Terminal/TerminalState.swift

// Note: BrowserState is defined in Panes/Browser/BrowserState.swift
// Keeping BrowserPaneState as a typealias for backwards compatibility
public typealias BrowserPaneState = BrowserState

/// State for file explorer panes
public struct FileExplorerPaneState: Equatable, Hashable {
    public var rootURL: URL?

    /// The ID of the code editor pane that this file explorer opens files into.
    /// If nil, a new editor will be created and linked on first file open.
    public var linkedEditorPaneId: UUID?

    public init(rootURL: URL? = nil, linkedEditorPaneId: UUID? = nil) {
        self.rootURL = rootURL
        self.linkedEditorPaneId = linkedEditorPaneId
    }
}

/// State for code editor panes
public struct CodeEditorPaneState: Equatable, Hashable {
    public var fileURL: URL?
    public var content: String

    public init(fileURL: URL? = nil, content: String = "") {
        self.fileURL = fileURL
        self.content = content
    }
}

/// State for git panes
public struct GitPaneState: Equatable, Hashable {
    public var repositoryURL: URL?

    /// The ID of the diff pane that this git pane shows diffs in.
    /// If nil, a new diff pane will be created on first file click.
    public var linkedDiffPaneId: UUID?

    public init(repositoryURL: URL? = nil, linkedDiffPaneId: UUID? = nil) {
        self.repositoryURL = repositoryURL
        self.linkedDiffPaneId = linkedDiffPaneId
    }
}
