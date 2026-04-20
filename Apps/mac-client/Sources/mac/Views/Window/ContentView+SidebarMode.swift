import AppFeatures

extension WindowFeature.Sidebar {
    var workspaceSidebarMode: WorkspaceSidebarMode {
        switch self {
        case .files:
            .files
        case .agents:
            .agents
        }
    }
}
