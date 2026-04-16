// BranchPicker.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

// MARK: - Data Model

/// A branch entry for the picker.
public struct BranchItem: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let isRemote: Bool
    public let isRecent: Bool

    public init(name: String, isRemote: Bool = false, isRecent: Bool = false) {
        self.name = name
        self.isRemote = isRemote
        self.isRecent = isRecent
    }
}

// MARK: - Branch Picker

/// Searchable branch selection list with Recent / Local / Remote sections.
///
/// Includes a search field at top, sectioned branch rows, and a
/// "Create new branch..." action at the bottom.
public struct BranchPicker: View {
    @Environment(\.theme) private var theme

    private let branches: [BranchItem]
    private let currentBranch: String
    private let onSelect: (String) -> Void
    private let onCreateNew: (String) -> Void

    @State private var searchText = ""

    public init(
        branches: [BranchItem],
        currentBranch: String,
        onSelect: @escaping (String) -> Void,
        onCreateNew: @escaping (String) -> Void
    ) {
        self.branches = branches
        self.currentBranch = currentBranch
        self.onSelect = onSelect
        self.onCreateNew = onCreateNew
    }

    // MARK: - Filtered Lists

    private var filteredBranches: [BranchItem] {
        guard !searchText.isEmpty else { return branches }
        return branches.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var recentBranches: [BranchItem] {
        filteredBranches.filter { $0.isRecent && !$0.isRemote }
    }

    private var localBranches: [BranchItem] {
        filteredBranches.filter { !$0.isRemote && !$0.isRecent }
    }

    private var remoteBranches: [BranchItem] {
        filteredBranches.filter { $0.isRemote }
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Search

            SearchInput("Search branches...", text: $searchText)
                .padding(Spacing.space3)

            Separator()

            // MARK: Sections

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !recentBranches.isEmpty {
                        branchSection("Recent", branches: recentBranches)
                    }

                    if !localBranches.isEmpty {
                        branchSection("Local", branches: localBranches)
                    }

                    if !remoteBranches.isEmpty {
                        branchSection("Remote", branches: remoteBranches)
                    }

                    // MARK: Create New

                    Separator()
                        .padding(.vertical, Spacing.space1)

                    CreateBranchRow(searchText: searchText, onCreateNew: onCreateNew)
                }
                .padding(.vertical, Spacing.space1)
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 300)
        .background(theme.overlay, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .shadowStyle(Shadows.md)
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func branchSection(_ title: String, branches: [BranchItem]) -> some View {
        SectionHeader(title, count: branches.count)
            .padding(.horizontal, Spacing.space3)
            .padding(.top, Spacing.space2)
            .padding(.bottom, Spacing.space1)

        ForEach(branches) { branch in
            BranchRow(
                branch: branch,
                isCurrent: branch.name == currentBranch,
                onSelect: onSelect
            )
        }
    }
}

// MARK: - Branch Row

private struct BranchRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    let branch: BranchItem
    let isCurrent: Bool
    let onSelect: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect(branch.name)
        } label: {
            HStack(spacing: Spacing.space2) {
                if isCurrent {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 6, height: 6)
                } else {
                    Color.clear
                        .frame(width: 6, height: 6)
                }

                Image(systemName: branch.isRemote ? "cloud" : "arrow.triangle.branch")
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(isCurrent ? theme.accent : theme.textSecondary)
                    .frame(width: 18)

                Text(branch.name)
                    .font(Typography.body)
                    .foregroundStyle(isCurrent ? theme.accent : theme.text)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, layout.itemPaddingV)
            .frame(minHeight: layout.sidebarRowHeight)
            .background(
                isCurrent
                    ? theme.accentMuted
                    : (isHovered ? theme.hover : .clear),
                in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
            )
            .padding(.horizontal, Spacing.space1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }
}

// MARK: - Create Branch Row

private struct CreateBranchRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    let searchText: String
    let onCreateNew: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onCreateNew(searchText)
        } label: {
            HStack(spacing: Spacing.space2) {
                Image(systemName: "plus")
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 18)

                Text(searchText.isEmpty ? "Create new branch..." : "Create \"\(searchText)\"...")
                    .font(Typography.body)
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, layout.itemPaddingV)
            .frame(minHeight: layout.sidebarRowHeight)
            .background(
                isHovered ? theme.hover : .clear,
                in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
            )
            .padding(.horizontal, Spacing.space1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }
}

// MARK: - Previews

#Preview("Branch Picker") {
    BranchPicker(
        branches: [
            BranchItem(name: "main", isRecent: true),
            BranchItem(name: "refactor/tca", isRecent: true),
            BranchItem(name: "feature/chat-ui"),
            BranchItem(name: "feature/agent-flows"),
            BranchItem(name: "fix/sidebar-crash"),
            BranchItem(name: "origin/main", isRemote: true),
            BranchItem(name: "origin/develop", isRemote: true),
            BranchItem(name: "origin/feature/chat-ui", isRemote: true),
        ],
        currentBranch: "refactor/tca",
        onSelect: { _ in },
        onCreateNew: { _ in }
    )
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
