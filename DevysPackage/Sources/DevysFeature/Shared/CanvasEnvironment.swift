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
