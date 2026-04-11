// RepositoryManagementSheet.swift
// Devys - Repository navigator management sheet.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Workspace
import UI

struct RepositoryManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let repositories: [Repository]
    let selectedRepositoryID: Repository.ID?
    let onMoveRepository: (Repository.ID, Int) -> Void
    let onRemoveRepository: (Repository.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space4) {
            header

            if repositories.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: DevysSpacing.space2) {
                        ForEach(Array(repositories.enumerated()), id: \.element.id) { index, repository in
                            RepositoryManagementRow(
                                repository: repository,
                                isSelected: repository.id == selectedRepositoryID,
                                canMoveUp: index > 0,
                                canMoveDown: index < repositories.count - 1,
                                onMoveUp: { onMoveRepository(repository.id, -1) },
                                onMoveDown: { onMoveRepository(repository.id, 1) },
                                onRemove: { onRemoveRepository(repository.id) }
                            )
                        }
                    }
                }
            }
        }
        .padding(DevysSpacing.space4)
        .background(theme.surface)
        .onChange(of: repositories.count) { _, newCount in
            if newCount == 0 {
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Manage Repositories")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.text)

                Text("Reorder navigator sections or remove repositories you no longer want in this window.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer(minLength: 0)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DevysSpacing.space2) {
            Spacer()
            Text("No repositories")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RepositoryManagementRow: View {
    @Environment(\.devysTheme) private var theme

    let repository: Repository
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DevysSpacing.space3) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DevysSpacing.space2) {
                    Text(repository.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.text)

                    if isSelected {
                        Text("Active")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.surface)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(theme.accent)
                            .clipShape(Capsule())
                    }
                }

                Text(repository.rootURL.path)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            HStack(spacing: DevysSpacing.space1) {
                managementButton(
                    systemName: "arrow.up",
                    disabled: !canMoveUp,
                    action: onMoveUp
                )
                managementButton(
                    systemName: "arrow.down",
                    disabled: !canMoveDown,
                    action: onMoveDown
                )
                managementButton(
                    systemName: "trash",
                    disabled: false,
                    role: .destructive,
                    action: onRemove
                )
            }
        }
        .padding(.horizontal, DevysSpacing.space3)
        .padding(.vertical, DevysSpacing.space2)
        .background(
            RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                .fill(isSelected ? theme.elevated : theme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        }
    }

    private func managementButton(
        systemName: String,
        disabled: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? DevysColors.error : theme.textSecondary)
        .opacity(disabled ? 0.35 : 1)
        .disabled(disabled)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
    }
}
