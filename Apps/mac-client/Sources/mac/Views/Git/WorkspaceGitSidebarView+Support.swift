import AppFeatures
import Git
import SwiftUI
import UI

@MainActor
extension WorkspaceGitSidebarView {
    @ViewBuilder
    var gitContent: some View {
        if !entry.isRepositoryAvailable {
            nonRepositoryStateView
        } else if entry.isLoading && entry.changes.isEmpty {
            loadingView
        } else if entry.changes.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !entry.stagedChanges.isEmpty {
                        sectionView(
                            title: "Staged Changes",
                            id: "staged",
                            files: entry.stagedChanges,
                            isStaged: true
                        )
                    }

                    if !entry.unstagedChanges.isEmpty {
                        sectionView(
                            title: "Unstaged",
                            id: "unstaged",
                            files: entry.unstagedChanges,
                            isStaged: false
                        )
                    }

                    if !entry.untrackedChanges.isEmpty {
                        sectionView(
                            title: "Untracked",
                            id: "untracked",
                            files: entry.untrackedChanges,
                            isStaged: false
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(Typography.micro)
            .foregroundStyle(DevysColors.error)
            .padding(.horizontal, Spacing.space3)
            .padding(.bottom, Spacing.space2)
    }

    func sectionView(
        title: String,
        id: String,
        files: [GitFileChange],
        isStaged: Bool
    ) -> some View {
        let allowsStageAll = !isStaged && files.contains { $0.status != .ignored }

        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: title,
                id: id,
                count: files.count,
                isStaged: isStaged,
                allowsStageAll: allowsStageAll
            )

            if expandedSections.contains(id) {
                ForEach(files) { file in
                    fileRowView(file: file, isStaged: isStaged)
                }
            }
        }
    }

    func sectionHeader(
        title: String,
        id: String,
        count: Int,
        isStaged: Bool,
        allowsStageAll: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if expandedSections.contains(id) {
                    expandedSections.remove(id)
                } else {
                    expandedSections.insert(id)
                }
            }
        } label: {
            HStack(spacing: Spacing.space2) {
                Image(systemName: expandedSections.contains(id) ? "chevron.down" : "chevron.right")
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 10)

                Text(title)
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)

                Text("\(count)")
                    .font(Typography.micro)
                    .foregroundStyle(theme.textTertiary)

                Spacer()

                if hoveredSection == id {
                    sectionBulkAction(isStaged: isStaged, allowsStageAll: allowsStageAll)
                }
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSection = hovering ? id : nil
        }
    }

    @ViewBuilder
    func sectionBulkAction(isStaged: Bool, allowsStageAll: Bool) -> some View {
        if isStaged {
            Button("Unstage All") {
                Task { await onUnstageAll() }
            }
            .font(Typography.micro)
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
        } else if allowsStageAll {
            Button("Stage All") {
                Task { await onStageAll() }
            }
            .font(Typography.micro)
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
        }
    }

    func fileRowView(file: GitFileChange, isStaged: Bool) -> some View {
        WorkspaceGitFileRowView(
            file: file,
            isStaged: isStaged,
            isSelected: selectedDiffPath == file.path && selectedDiffIsStaged == isStaged,
            onSelect: {
                onPreviewDiff(file.path, isStaged)
            },
            onOpen: {
                onOpenDiff(file.path, isStaged)
            },
            onAddToChat: {
                onAddDiffToChat(file.path, isStaged)
            },
            onStage: isStaged || file.status == .ignored ? nil : {
                Task { await onStageFile(file.path) }
            },
            onUnstage: isStaged ? {
                Task { await onUnstageFile(file.path) }
            } : nil,
            onDiscard: isStaged || file.status == .ignored ? nil : {
                Task { await onDiscardChange(file) }
            }
        )
    }

    var nonRepositoryStateView: some View {
        VStack(spacing: Spacing.space2) {
            Image(systemName: "arrow.triangle.branch")
                .font(Typography.display)
                .foregroundStyle(theme.textTertiary.opacity(0.8))

            Text("Git not initialized")
                .font(Typography.label)
                .foregroundStyle(theme.textSecondary)

            Text("Open the project now and initialize Git later when you need source control.")
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading...")
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(Typography.display)
                .foregroundStyle(DevysColors.success.opacity(0.6))

            Text("No Changes")
                .font(Typography.label)
                .foregroundStyle(theme.textSecondary)

            Text("Working tree is clean")
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    var actionsFooter: some View {
        if !entry.isRepositoryAvailable {
            HStack(spacing: Spacing.space2) {
                if let onInitializeGit {
                    Button(action: onInitializeGit) {
                        HStack(spacing: Spacing.space1) {
                            Image(systemName: "plus")
                                .font(Typography.micro.weight(.semibold))
                            Text("Initialize Git")
                                .font(Typography.caption.weight(.medium))
                        }
                        .padding(.horizontal, Spacing.space3)
                        .padding(.vertical, Spacing.space1)
                        .background(theme.overlay)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                                .strokeBorder(theme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(entry.isLoading)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space2)
        } else {
            HStack(spacing: Spacing.space2) {
                Button {
                    showingCommitSheet = true
                } label: {
                    HStack(spacing: Spacing.space1) {
                        Text(">")
                            .font(Typography.Code.gutter)
                            .foregroundStyle(theme.accent)
                        Text("commit")
                            .font(Typography.Code.gutter.weight(.medium))
                    }
                    .padding(.horizontal, Spacing.space3)
                    .padding(.vertical, Spacing.space1)
                    .background(theme.overlay)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                            .strokeBorder(
                                entry.stagedChanges.isEmpty ? theme.border : theme.accent,
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(entry.stagedChanges.isEmpty)
                .opacity(entry.stagedChanges.isEmpty ? 0.5 : 1.0)

                Spacer()

                Button {
                    Task { await onFetch() }
                } label: {
                    Image(systemName: "arrow.trianglehead.clockwise")
                        .font(Typography.label)
                }
                .buttonStyle(.plain)
                .help("Fetch")
                .disabled(entry.isLoading)

                Button {
                    Task { await onPull() }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(Typography.label)
                }
                .buttonStyle(.plain)
                .help("Pull")
                .disabled(entry.isLoading)

                Button {
                    Task { await onPush() }
                } label: {
                    Image(systemName: "arrow.up.circle")
                        .font(Typography.label)
                }
                .buttonStyle(.plain)
                .help("Push")
                .disabled(entry.isLoading)
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space2)
        }
    }
}
