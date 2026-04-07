// WorkspaceCommandPaletteView.swift
// Keyboard-driven command palette for workspace shell actions.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import SwiftUI
import UI
import Workspace

enum WorkspaceCommandPaletteAction: Equatable {
    case addRepository
    case selectRepository(Repository.ID)
    case createWorkspace(Repository.ID)
    case importWorktrees(Repository.ID)
    case selectWorkspace(repositoryID: Repository.ID, workspaceID: Workspace.ID)
    case launchShell
    case launchClaude
    case launchCodex
    case runDefaultProfile
    case jumpToLatestUnreadWorkspace
    case revealCurrentWorkspaceInNavigator
}

struct WorkspaceCommandPaletteItem: Identifiable, Equatable {
    let action: WorkspaceCommandPaletteAction
    let title: String
    let subtitle: String
    let systemImage: String
    let keywords: [String]
    let shortcut: String?

    var id: String {
        switch action {
        case .addRepository:
            "add-repository"
        case .selectRepository(let repositoryID):
            "select-repository:\(repositoryID)"
        case .createWorkspace(let repositoryID):
            "create-workspace:\(repositoryID)"
        case .importWorktrees(let repositoryID):
            "import-worktrees:\(repositoryID)"
        case .selectWorkspace(let repositoryID, let workspaceID):
            "select-workspace:\(repositoryID):\(workspaceID)"
        case .launchShell:
            "launch-shell"
        case .launchClaude:
            "launch-claude"
        case .launchCodex:
            "launch-codex"
        case .runDefaultProfile:
            "run-default-profile"
        case .jumpToLatestUnreadWorkspace:
            "jump-latest-unread-workspace"
        case .revealCurrentWorkspaceInNavigator:
            "reveal-current-workspace"
        }
    }
}

struct WorkspaceCommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let items: [WorkspaceCommandPaletteItem]
    let onSelect: (WorkspaceCommandPaletteItem) -> Void

    @State private var query = ""
    @State private var selectedItemID: WorkspaceCommandPaletteItem.ID?
    @State private var keyMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [WorkspaceCommandPaletteItem] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedQuery.isEmpty else { return items }

        return items.filter { item in
            if item.title.lowercased().contains(normalizedQuery) {
                return true
            }
            if item.subtitle.lowercased().contains(normalizedQuery) {
                return true
            }
            return item.keywords.contains { $0.lowercased().contains(normalizedQuery) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .overlay(theme.borderSubtle)
            results
        }
        .frame(width: 720, height: 520)
        .background(theme.base)
        .onAppear {
            isSearchFocused = true
            selectFirstFilteredItem()
            installKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onChange(of: query) { _, _ in
            selectFirstFilteredItem()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMMAND PALETTE")
                .font(DevysTypography.heading)
                .tracking(DevysTypography.headerTracking)
                .foregroundStyle(theme.textSecondary)

            TextField("Search commands", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onSubmit {
                    executeSelectedItem()
                }
        }
        .padding(20)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredItems) { item in
                        button(for: item)
                    }
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No matching commands")
                .font(DevysTypography.base)
                .foregroundStyle(theme.textSecondary)

            Text("Try a repository, workspace, launch action, or unread command.")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(theme.surface)
        .cornerRadius(DevysSpacing.radiusMd)
    }

    private func button(for item: WorkspaceCommandPaletteItem) -> some View {
        Button {
            execute(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(DevysTypography.base)
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.subtitle)
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusMd)
                    .fill(selectedItemID == item.id ? theme.active : theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusMd)
                    .strokeBorder(
                        selectedItemID == item.id ? theme.accent.opacity(0.4) : theme.borderSubtle,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 125:
                moveSelection(by: 1)
                return nil
            case 126:
                moveSelection(by: -1)
                return nil
            case 36, 76:
                executeSelectedItem()
                return nil
            case 53:
                dismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        guard let selectedItemID,
              let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = filteredItems.first?.id
            return
        }

        let nextIndex = max(0, min(filteredItems.count - 1, currentIndex + offset))
        self.selectedItemID = filteredItems[nextIndex].id
    }

    private func selectFirstFilteredItem() {
        selectedItemID = filteredItems.first?.id
    }

    private func executeSelectedItem() {
        guard let selectedItemID,
              let item = filteredItems.first(where: { $0.id == selectedItemID }) ?? filteredItems.first else {
            return
        }
        execute(item)
    }

    private func execute(_ item: WorkspaceCommandPaletteItem) {
        onSelect(item)
        dismiss()
    }
}
