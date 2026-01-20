import SwiftUI
import Observation

// MARK: - Workspace Tab

/// Represents a single project tab in the workspace.
///
/// Each tab contains a project reference and its own canvas state,
/// allowing users to switch between projects while preserving layout.
@MainActor
public struct WorkspaceTab: Identifiable, Equatable {
    /// The project this tab represents
    public let project: Project

    /// Canvas state for this tab (panes, viewport, etc.)
    public var canvasState: CanvasState

    /// Unique identifier (delegates to project.id)
    public nonisolated var id: UUID { project.id }

    public init(project: Project, canvasState: CanvasState? = nil) {
        self.project = project
        // Create canvas state with project ID for auto-scoping panes
        self.canvasState = canvasState ?? CanvasState(currentProjectId: project.id)
    }

    public nonisolated static func == (lhs: WorkspaceTab, rhs: WorkspaceTab) -> Bool {
        lhs.project.id == rhs.project.id
    }
}

// MARK: - Viewport State

/// Captures the viewport position and zoom for saving/restoring.
public struct ViewportState: Codable, Equatable, Sendable {
    public var offset: CGPoint
    public var scale: CGFloat

    public init(offset: CGPoint = .zero, scale: CGFloat = 1.0) {
        self.offset = offset
        self.scale = scale
    }
}

// MARK: - Workspace State

/// Root state object managing multiple project tabs.
///
/// The workspace maintains a collection of tabs, each containing
/// a project and its associated canvas state. This enables:
/// - Multiple projects open simultaneously
/// - Independent canvas layouts per project
/// - Quick switching between projects
@MainActor
@Observable
public final class WorkspaceState {

    // MARK: - Properties

    /// All open project tabs
    public var tabs: [WorkspaceTab] = []

    /// ID of the currently active tab
    public var activeTabId: UUID?

    // MARK: - Computed Properties

    /// The currently active tab
    public var activeTab: WorkspaceTab? {
        guard let id = activeTabId else { return nil }
        return tabs.first { $0.id == id }
    }

    /// The currently active project
    public var activeProject: Project? {
        activeTab?.project
    }

    /// The canvas state for the active tab
    public var activeCanvasState: CanvasState? {
        guard let id = activeTabId,
              let index = tabIndex(withId: id) else { return nil }
        return tabs[index].canvasState
    }

    /// Whether the workspace has any open tabs
    public var hasTabs: Bool {
        !tabs.isEmpty
    }

    /// Number of open tabs
    public var tabCount: Int {
        tabs.count
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Tab Queries

    /// Find a tab by ID
    public func tab(withId id: UUID) -> WorkspaceTab? {
        tabs.first { $0.id == id }
    }

    /// Find the index of a tab by ID
    public func tabIndex(withId id: UUID) -> Int? {
        tabs.firstIndex { $0.id == id }
    }

    /// Find a project by ID
    public func project(withId id: UUID) -> Project? {
        tabs.first { $0.project.id == id }?.project
    }

    /// Check if a project is already open
    public func isProjectOpen(_ projectId: UUID) -> Bool {
        tabs.contains { $0.project.id == projectId }
    }

    /// Check if a folder is already open as a project
    public func isPathOpen(_ url: URL) -> Bool {
        tabs.contains { $0.project.rootURL == url }
    }

    // MARK: - Tab Management

    /// Add a new tab for a project.
    ///
    /// If the project is already open, switches to that tab instead.
    /// - Parameter project: The project to open
    /// - Returns: The tab that was created or switched to
    @discardableResult
    public func addTab(for project: Project) -> WorkspaceTab {
        // Check if already open
        if let existingTab = tabs.first(where: { $0.project.id == project.id }) {
            activeTabId = existingTab.id
            return existingTab
        }

        let tab = WorkspaceTab(project: project)
        tabs.append(tab)
        activeTabId = tab.id
        return tab
    }

    /// Close a tab by ID.
    ///
    /// If the closed tab was active, selects an adjacent tab.
    /// - Parameter id: The ID of the tab to close
    public func closeTab(_ id: UUID) {
        guard let index = tabIndex(withId: id) else { return }

        let wasActive = activeTabId == id
        tabs.remove(at: index)

        // Select adjacent tab if needed
        if wasActive {
            if tabs.isEmpty {
                activeTabId = nil
            } else if index < tabs.count {
                activeTabId = tabs[index].id
            } else {
                activeTabId = tabs[tabs.count - 1].id
            }
        }
    }

    /// Switch to a specific tab.
    /// - Parameter id: The ID of the tab to activate
    public func switchToTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    /// Switch to the next tab (wraps around).
    public func switchToNextTab() {
        guard tabs.count > 1,
              let currentId = activeTabId,
              let currentIndex = tabIndex(withId: currentId) else { return }

        let nextIndex = (currentIndex + 1) % tabs.count
        activeTabId = tabs[nextIndex].id
    }

    /// Switch to the previous tab (wraps around).
    public func switchToPreviousTab() {
        guard tabs.count > 1,
              let currentId = activeTabId,
              let currentIndex = tabIndex(withId: currentId) else { return }

        let previousIndex = (currentIndex - 1 + tabs.count) % tabs.count
        activeTabId = tabs[previousIndex].id
    }

    /// Move a tab to a new position.
    /// - Parameters:
    ///   - fromIndex: Current index of the tab
    ///   - toIndex: Destination index
    public func moveTab(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < tabs.count,
              toIndex >= 0, toIndex < tabs.count else { return }

        let tab = tabs.remove(at: fromIndex)
        tabs.insert(tab, at: toIndex)
    }

    // MARK: - Project Operations

    /// Open a folder as a new project.
    ///
    /// - Parameter url: The folder URL to open
    /// - Returns: The created project
    /// - Throws: `ProjectError` if the folder is invalid
    @discardableResult
    public func openProject(at url: URL) throws -> Project {
        // Check if already open
        if let existingTab = tabs.first(where: { $0.project.rootURL == url }) {
            activeTabId = existingTab.id
            return existingTab.project
        }

        let project = try Project.create(from: url)
        addTab(for: project)
        return project
    }

    /// Update the canvas state for a tab.
    /// - Parameters:
    ///   - id: The tab ID
    ///   - canvasState: The new canvas state
    public func updateCanvasState(for id: UUID, canvasState: CanvasState) {
        guard let index = tabIndex(withId: id) else { return }
        tabs[index].canvasState = canvasState
    }
}
