// WorkspaceNotificationsPanel.swift
// Devys - Pending workspace notifications panel.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct WorkspaceNotificationsPanel: View {
    @Environment(\.devysTheme) private var theme

    let items: [WorkspaceNotificationPanelItem]
    let onOpen: (WorkspaceNotificationPanelItem) -> Void
    let onClear: (WorkspaceNotificationPanelItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: DevysSpacing.space2) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                    .padding(DevysSpacing.space3)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(theme.base)
    }

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(Typography.heading)
                .foregroundStyle(theme.text)

            Spacer()

            Text("\(items.count)")
                .font(Typography.caption.weight(.medium))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, DevysSpacing.space4)
        .padding(.vertical, DevysSpacing.space3)
        .background(theme.card)
    }

    private var emptyState: some View {
        VStack(spacing: DevysSpacing.space2) {
            Text("No pending notifications")
                .font(Typography.body.weight(.medium))
                .foregroundStyle(theme.textSecondary)

            Text("Workspace attention will appear here when terminals or agents need input.")
                .font(Typography.caption)
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DevysSpacing.space5)
    }

    private func row(_ item: WorkspaceNotificationPanelItem) -> some View {
        HStack(alignment: .top, spacing: DevysSpacing.space3) {
            Button {
                onOpen(item)
            } label: {
                VStack(alignment: .leading, spacing: DevysSpacing.space2) {
                    Text(item.notification.source.displayName.uppercased())
                        .font(Typography.micro.weight(.semibold))
                        .foregroundStyle(theme.accent)

                    Text(item.notification.title)
                        .font(Typography.label)
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.leading)

                    if let subtitle = item.notification.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Text("\(item.repositoryName) / \(item.workspaceName)")
                        .font(Typography.micro)
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            ActionButton("Clear", style: .ghost) {
                onClear(item)
            }
            .padding(.top, 2)
        }
        .padding(DevysSpacing.space3)
        .elevation(.card)
    }
}
