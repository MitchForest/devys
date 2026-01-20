import SwiftUI
import UniformTypeIdentifiers

/// Native macOS-style tab bar for switching between project tabs.
///
/// Displays open projects as tabs with:
/// - Project name and git branch
/// - Close button on hover
/// - Add new tab button
/// - Tab selection and reordering
public struct ProjectTabBar: View {
    @Environment(\.workspaceState) private var _workspace
    private var workspace: WorkspaceState { _workspace ?? WorkspaceState() }

    /// Callback when user requests to open a new project
    var onAddTab: () -> Void = {}

    public init(onAddTab: @escaping () -> Void = {}) {
        self.onAddTab = onAddTab
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Tab list
            tabList

            Spacer()

            // Right-side controls
            rightControls
        }
        .frame(height: 36)
        .background(Theme.paneTitleBar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Tab List

    private var tabList: some View {
        HStack(spacing: 1) {
            ForEach(workspace.tabs) { tab in
                ProjectTabItem(
                    tab: tab,
                    isSelected: workspace.activeTabId == tab.id,
                    onSelect: { workspace.switchToTab(tab.id) },
                    onClose: { workspace.closeTab(tab.id) }
                )
            }

            // Add tab button
            addTabButton
        }
    }

    private var addTabButton: some View {
        Button(action: onAddTab) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Project (⇧⌘O)")
    }

    // MARK: - Right Controls

    private var rightControls: some View {
        HStack(spacing: 8) {
            // Layouts dropdown (placeholder for Sprint 11)
            Menu {
                Text("Layouts coming in Sprint 11")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 11))
                    Text("Layouts")
                        .font(.system(size: 11))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.trailing, 12)
    }
}

// MARK: - Project Tab Item

/// Individual tab in the project tab bar.
struct ProjectTabItem: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // Git branch indicator
            if let branch = tab.project.gitBranch {
                GitBranchBadge(branch: branch)
            }

            // Project name
            Text(tab.project.shortName)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)

            // Close button (visible on hover)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(Color.gray.opacity(isHovered ? 0.2 : 0))
                    )
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Close Tab")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 80)
        .background(tabBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            tabContextMenu
        }
    }

    private var tabBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.15)
            } else if isHovered {
                Color.gray.opacity(0.1)
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var tabContextMenu: some View {
        Button("Close Tab") {
            onClose()
        }

        Button("Close Other Tabs") {
            // TODO: Implement close other tabs
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: tab.project.rootURL.path)
        }

        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tab.project.rootURL.path, forType: .string)
        }
    }
}

// MARK: - Git Branch Badge

/// Small pill showing the current git branch.
struct GitBranchBadge: View {
    let branch: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
            Text(branch)
                .font(.system(size: 10))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Empty Workspace View

/// Shown when no projects are open.
public struct EmptyWorkspaceView: View {
    var onOpenProject: () -> Void

    public init(onOpenProject: @escaping () -> Void) {
        self.onOpenProject = onOpenProject
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("No Project Open")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text("Open a folder to get started")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            Button(action: onOpenProject) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("Open Project...")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Text("⇧⌘O")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvasBackground)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFolderDrop(providers)
        }
    }

    private func handleFolderDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.hasDirectoryPath else { return }

                Task { @MainActor in
                    // Post notification to open project
                    NotificationCenter.default.post(name: .openProjectAtURL, object: url)
                }
            }
        }
        return true
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Request to open a project at a specific URL
    static let openProjectAtURL = Notification.Name("devys.openProjectAtURL")

    /// Request to show the open project dialog
    static let showOpenProjectDialog = Notification.Name("devys.showOpenProjectDialog")
}

// MARK: - Preview

#Preview("Tab Bar with Tabs") {
    let workspace = WorkspaceState()
    let _ = workspace.addTab(for: Project(rootURL: URL(fileURLWithPath: "/Users/dev/my-app"), gitBranch: "main"))
    let _ = workspace.addTab(for: Project(rootURL: URL(fileURLWithPath: "/Users/dev/api-server"), gitBranch: "feature/auth"))

    return VStack(spacing: 0) {
        ProjectTabBar()
            .workspaceState(workspace)

        Color.gray.opacity(0.2)
    }
    .frame(width: 600, height: 400)
}

#Preview("Empty Workspace") {
    EmptyWorkspaceView(onOpenProject: {})
        .frame(width: 600, height: 400)
}
