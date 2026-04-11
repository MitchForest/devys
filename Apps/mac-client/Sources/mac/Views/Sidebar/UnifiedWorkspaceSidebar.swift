// UnifiedWorkspaceSidebar.swift
// Devys - Unified workspace sidebar with collapsible sections.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Git
import UI

struct UnifiedWorkspaceSidebar<
    FilesContent: View,
    ChangesContent: View,
    PortsContent: View,
    AgentsContent: View
>: View {
    @Environment(\.devysTheme) private var theme

    let hasChanges: Bool
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarSection(
                    title: "Files",
                    systemImage: "folder",
                    isExpanded: $isFilesExpanded
                ) {
                    filesContent()
                }

                sectionDivider

                sidebarSection(
                    title: "Changes",
                    systemImage: "arrow.triangle.branch",
                    isExpanded: $isChangesExpanded,
                    badge: hasChanges ? "" : nil
                ) {
                    changesContent()
                }

                if portCount > 0 {
                    sectionDivider

                    sidebarSection(
                        title: "Ports",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        isExpanded: $isPortsExpanded,
                        badge: "\(portCount)"
                    ) {
                        portsContent()
                    }
                }

                sectionDivider

                sidebarSection(
                    title: "Agents",
                    systemImage: "message.badge.waveform",
                    isExpanded: $isAgentsExpanded,
                    badge: agentCount > 0 ? "\(agentCount)" : nil
                ) {
                    agentsContent()
                }
            }
        }
        .background(theme.surface)
        .onChange(of: portCount) { _, newCount in
            if newCount > 0, !isPortsExpanded {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isPortsExpanded = true
                }
            }
        }
        .onChange(of: hasChanges) { _, hasChanges in
            if hasChanges, !isChangesExpanded {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isChangesExpanded = true
                }
            }
        }
        .onChange(of: agentCount) { _, agentCount in
            if agentCount > 0, !isAgentsExpanded {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isAgentsExpanded = true
                }
            }
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(theme.borderSubtle)
            .frame(height: 1)
    }

    private func sidebarSection<Content: View>(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        badge: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 10)

                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textSecondary)

                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.accent)
                    }

                    Spacer()
                }
                .padding(.horizontal, DevysSpacing.space3)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
    }
}
