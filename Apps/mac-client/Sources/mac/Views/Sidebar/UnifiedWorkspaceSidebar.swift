// UnifiedWorkspaceSidebar.swift
// Devys - Canonical two-tab content sidebar.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct UnifiedWorkspaceSidebar<
    FilesContent: View,
    ChangesContent: View,
    PortsContent: View,
    AgentsContent: View
>: View {
    @Environment(\.devysTheme) private var theme

    let selection: WorkspaceSidebarMode
    let onSelect: (WorkspaceSidebarMode) -> Void
    let changeCount: Int
    let portCount: Int
    let agentCount: Int
    @ViewBuilder let filesContent: () -> FilesContent
    @ViewBuilder let changesContent: () -> ChangesContent
    @ViewBuilder let portsContent: () -> PortsContent
    @ViewBuilder let agentsContent: () -> AgentsContent

    @State private var isFilesExpanded = true
    @State private var isChangesExpanded = true
    @State private var isPortsExpanded = false
    @State private var isAgentsExpanded = true
    @State private var isWorkflowsExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            SegmentedControl(
                options: ["Files", "Agents"],
                selectedIndex: selectionIndex
            )
            .padding(.horizontal, DevysSpacing.space3)
            .padding(.vertical, DevysSpacing.space3)

            Separator()

            Group {
                switch selection {
                case .files:
                    filesTab
                case .agents:
                    agentsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(theme.card)
        .onChange(of: portCount) { _, newCount in
            if newCount > 0, !isPortsExpanded {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isPortsExpanded = true
                }
            }
        }
        .onChange(of: changeCount) { _, newCount in
            if newCount > 0, !isChangesExpanded {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isChangesExpanded = true
                }
            }
        }
    }

    private var selectionIndex: Binding<Int> {
        Binding(
            get: {
                switch selection {
                case .files:
                    return 0
                case .agents:
                    return 1
                }
            },
            set: { newValue in
                onSelect(newValue == 0 ? .files : .agents)
            }
        )
    }

    private var filesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SidebarSection(
                    "Files",
                    icon: "folder",
                    isExpanded: $isFilesExpanded
                ) {
                    filesContent()
                }

                Separator()

                SidebarSection(
                    "Changes",
                    icon: "arrow.triangle.branch",
                    count: changeCount > 0 ? changeCount : nil,
                    isExpanded: $isChangesExpanded
                ) {
                    changesContent()
                }

                if portCount > 0 {
                    Separator()

                    SidebarSection(
                        "Ports",
                        icon: "point.3.connected.trianglepath.dotted",
                        count: portCount,
                        isExpanded: $isPortsExpanded
                    ) {
                        portsContent()
                    }
                }
            }
        }
    }

    private var agentsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SidebarSection(
                    "Agents",
                    icon: "message.badge.waveform",
                    count: agentCount > 0 ? agentCount : nil,
                    isExpanded: $isAgentsExpanded
                ) {
                    agentsContent()
                }

                Separator()

                SidebarSection(
                    "Workflows",
                    icon: "sparkles",
                    isExpanded: $isWorkflowsExpanded
                ) {
                    EmptyState(
                        icon: "sparkles",
                        title: "Workflows coming soon",
                        description: "Multi-step automated agent pipelines will live here."
                    )
                    .frame(maxHeight: 220)
                }
            }
        }
    }
}
