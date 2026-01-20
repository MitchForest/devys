import SwiftUI

// MARK: - Canvas Environment Key

/// Environment key for accessing CanvasState throughout the view hierarchy
private struct CanvasStateKey: EnvironmentKey {
    static let defaultValue: CanvasState? = nil
}

extension EnvironmentValues {
    /// The current canvas state (optional, will be nil if not provided)
    public var canvasState: CanvasState? {
        get { self[CanvasStateKey.self] }
        set { self[CanvasStateKey.self] = newValue }
    }
}

extension View {
    /// Injects a CanvasState into the environment
    public func canvasState(_ state: CanvasState) -> some View {
        environment(\.canvasState, state)
    }
}

// MARK: - Workspace Environment Key

/// Environment key for accessing WorkspaceState throughout the view hierarchy
private struct WorkspaceStateKey: EnvironmentKey {
    static let defaultValue: WorkspaceState? = nil
}

extension EnvironmentValues {
    /// The current workspace state (optional, will be nil if not provided)
    public var workspaceState: WorkspaceState? {
        get { self[WorkspaceStateKey.self] }
        set { self[WorkspaceStateKey.self] = newValue }
    }
}

extension View {
    /// Injects a WorkspaceState into the environment
    public func workspaceState(_ state: WorkspaceState) -> some View {
        environment(\.workspaceState, state)
    }
}
