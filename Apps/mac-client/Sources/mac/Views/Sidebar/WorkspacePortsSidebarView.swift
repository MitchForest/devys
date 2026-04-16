// WorkspacePortsSidebarView.swift
// Devys - Active workspace listening ports.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import SwiftUI
import Workspace
import UI

struct WorkspacePortsSidebarView: View {
    @Environment(\.devysTheme) private var theme

    let ports: [WorkspacePort]
    let labelsByPort: [Int: RepositoryPortLabel]
    let onOpen: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onCopyURL: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onStopProcess: (WorkspacePort, Int32) -> Void

    var body: some View {
        if ports.isEmpty {
            EmptyState(
                icon: "point.3.connected.trianglepath.dotted",
                title: "No listening ports",
                description: "Start a server in the active workspace and it will appear here."
            )
            .background(theme.card)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ports) { port in
                        PortRow(
                            port: port,
                            label: labelsByPort[port.port],
                            onOpen: onOpen,
                            onCopyURL: onCopyURL,
                            onStopProcess: onStopProcess
                        )

                        if port.id != ports.last?.id {
                            Separator()
                                .padding(.horizontal, DevysSpacing.space3)
                        }
                    }
                }
                .padding(.vertical, DevysSpacing.space1)
            }
        }
    }
}

private struct PortRow: View {
    @Environment(\.devysTheme) private var theme

    let port: WorkspacePort
    let label: RepositoryPortLabel?
    let onOpen: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onCopyURL: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onStopProcess: (WorkspacePort, Int32) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label?.label ?? "Port")
                    .font(DevysTypography.label)
                    .foregroundStyle(theme.text)

                Text(":\(port.port)")
                    .font(DevysTypography.micro)
                    .foregroundStyle(theme.textSecondary)

                if port.ownership == .conflicted {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                        .help("Port conflict")
                }

                Spacer()

                if isHovered {
                    rowActions
                }
            }

            if isHovered {
                Text(urlString)
                    .font(DevysTypography.micro)
                    .foregroundStyle(theme.textTertiary)
                    .textSelection(.enabled)

                if !port.processDescriptions.isEmpty {
                    Text(port.processDescriptions.joined(separator: " \u{2022} "))
                        .font(DevysTypography.micro)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DevysSpacing.space3)
        .padding(.vertical, DevysSpacing.space2)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowActions: some View {
        HStack(spacing: 6) {
            Button("Open") {
                onOpen(port, label)
            }
            .buttonStyle(.plain)
            .font(DevysTypography.micro)
            .foregroundStyle(theme.accent)

            Button("Copy") {
                onCopyURL(port, label)
            }
            .buttonStyle(.plain)
            .font(DevysTypography.micro)
            .foregroundStyle(theme.textSecondary)

            if !port.processIDs.isEmpty {
                Menu {
                    ForEach(
                        Array(zip(port.processIDs, port.processDisplayNames)),
                        id: \.0
                    ) { processID, processName in
                        Button("Stop \(processName) (\(processID))") {
                            onStopProcess(port, processID)
                        }
                    }
                } label: {
                    Text("Stop")
                        .font(DevysTypography.micro)
                        .foregroundStyle(DevysColors.error)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var urlString: String {
        resolvedURL?.absoluteString ?? "http://localhost:\(port.port)"
    }

    private var resolvedURL: URL? {
        let scheme = label?.scheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .nilIfEmpty ?? "http"
        let path = normalizedPath(label?.path ?? "")
        return URL(string: "\(scheme)://localhost:\(port.port)\(path)")
    }

    private func normalizedPath(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }
}

private extension WorkspacePort {
    var processDisplayNames: [String] {
        if processNames.count == processIDs.count {
            return processNames
        }

        let fallbackCount = max(processIDs.count - processNames.count, 0)
        return processNames + Array(repeating: "process", count: fallbackCount)
    }

    var processDescriptions: [String] {
        Array(zip(processIDs, processDisplayNames)).map { processID, processName in
            "\(processName) (\(processID))"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
