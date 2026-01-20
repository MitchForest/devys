import Foundation
import SwiftUI

/// The type of content a pane displays.
///
/// Each pane type has its own state struct that holds
/// configuration and runtime state for that pane type.
public enum PaneType: Equatable {
    case terminal(TerminalPaneState)
    case browser(BrowserPaneState)
    case fileExplorer(FileExplorerPaneState)
    case codeEditor(CodeEditorPaneState)
    case git(GitPaneState)
    
    // MARK: - Properties
    
    /// SF Symbol name for this pane type
    public var iconName: String {
        switch self {
        case .terminal: return "terminal"
        case .browser: return "globe"
        case .fileExplorer: return "folder"
        case .codeEditor: return "doc.text"
        case .git: return "arrow.triangle.branch"
        }
    }
    
    /// Default title for new panes of this type
    public var defaultTitle: String {
        switch self {
        case .terminal: return "Terminal"
        case .browser(let state): return state.url?.host ?? "Browser"
        case .fileExplorer(let state): return state.rootURL?.lastPathComponent ?? "Files"
        case .codeEditor(let state): return state.fileURL?.lastPathComponent ?? "Untitled"
        case .git: return "Git"
        }
    }
}

// MARK: - Pane State Types

/// State for terminal panes
public struct TerminalPaneState: Equatable, Hashable {
    public var workingDirectory: URL?
    public var shell: String
    
    public init(
        workingDirectory: URL? = nil,
        shell: String = "/bin/zsh"
    ) {
        self.workingDirectory = workingDirectory
        self.shell = shell
    }
}

/// State for browser panes
public struct BrowserPaneState: Equatable, Hashable {
    public var url: URL?
    
    public init(url: URL? = URL(string: "http://localhost:3000")) {
        self.url = url
    }
}

/// State for file explorer panes
public struct FileExplorerPaneState: Equatable, Hashable {
    public var rootURL: URL?
    
    public init(rootURL: URL? = nil) {
        self.rootURL = rootURL
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
    
    public init(repositoryURL: URL? = nil) {
        self.repositoryURL = repositoryURL
    }
}
