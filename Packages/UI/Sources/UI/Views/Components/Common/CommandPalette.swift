// CommandPalette.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

// MARK: - Data Models

/// A section of results within the command palette.
public struct CommandPaletteSection: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let items: [CommandPaletteItem]

    public init(title: String, items: [CommandPaletteItem]) {
        self.title = title
        self.items = items
    }
}

/// A single item within a command palette section.
public struct CommandPaletteItem: Identifiable, Sendable {
    public let id = UUID()
    public let icon: String
    public let iconColor: Color?
    public let title: String
    public let subtitle: String?
    public let shortcut: String?

    public init(
        icon: String,
        iconColor: Color? = nil,
        title: String,
        subtitle: String? = nil,
        shortcut: String? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.shortcut = shortcut
    }
}

// MARK: - Command Palette

/// Full command palette overlay with search, sectioned results, keyboard navigation, and selection.
///
/// Includes built-in keyboard handling (↑↓ to navigate, Enter to select, Escape to dismiss).
/// When the query is empty, `homeSections` are shown as a home base — running agents, recent
/// files, quick actions. When the query is non-empty, `sections` (filtered by the consumer)
/// are shown.
public struct CommandPalette: View {
    @Environment(\.theme) private var theme

    @Binding private var query: String
    private let sections: [CommandPaletteSection]
    private let homeSections: [CommandPaletteSection]
    @Binding private var selectedIndex: Int
    private let placeholder: String
    private let emptyTitle: String
    private let emptySubtitle: String?
    private let onSelect: (Int) -> Void
    private let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var confirmScale: CGFloat = 1.0

    public init(
        query: Binding<String>,
        sections: [CommandPaletteSection],
        homeSections: [CommandPaletteSection] = [],
        selectedIndex: Binding<Int>,
        placeholder: String = "Search files, commands, agents...",
        emptyTitle: String = "No results",
        emptySubtitle: String? = nil,
        onSelect: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self._query = query
        self.sections = sections
        self.homeSections = homeSections
        self._selectedIndex = selectedIndex
        self.placeholder = placeholder
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    /// The sections to display — home sections when query is empty, filtered sections otherwise.
    private var visibleSections: [CommandPaletteSection] {
        query.isEmpty && !homeSections.isEmpty ? homeSections : sections
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: Search Field

            searchField

            Separator()

            // MARK: Results

            if visibleItemCount == 0 {
                emptyState
            } else {
                resultsList
            }
        }
        .frame(width: 520)
        .frame(maxHeight: 480)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .elevation(.overlay)
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1.0 : 0)
        .onAppear {
            withAnimation(Animations.spring) { isVisible = true }
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            confirmSelection()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    /// Animate out, then call onDismiss.
    public func dismiss() {
        withAnimation(.easeOut(duration: 0.12)) { isVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { onDismiss() }
    }

    // MARK: - Search Field

    private var searchField: some View {
        SearchInput(placeholder, text: $query)
        .padding(.horizontal, Spacing.space4)
        .padding(.vertical, Spacing.space3)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.space1) {
                ForEach(visibleSections) { section in
                    SectionHeader(section.title)
                        .padding(.horizontal, Spacing.space3)
                        .padding(.top, Spacing.space2)

                    ForEach(
                        Array(section.items.enumerated()),
                        id: \.element.id
                    ) { itemOffset, item in
                        let currentIndex = flattenedIndex(
                            for: section,
                            itemOffset: itemOffset
                        )
                        CommandPaletteRow(
                            icon: item.icon,
                            iconColor: item.iconColor,
                            title: item.title,
                            subtitle: item.subtitle,
                            shortcut: item.shortcut,
                            isActive: selectedIndex == currentIndex
                        )
                        .scaleEffect(
                            selectedIndex == currentIndex ? confirmScale : 1.0
                        )
                        .padding(.horizontal, Spacing.space2)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(currentIndex) }
                    }
                }
            }
            .padding(.vertical, Spacing.space2)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.space2) {
            Spacer()
            Text(emptyTitle)
                .font(Typography.body)
                .foregroundStyle(theme.textTertiary)
            if let emptySubtitle {
                Text(emptySubtitle)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Index Helpers

    private var visibleItemCount: Int {
        visibleSections.reduce(0) { $0 + $1.items.count }
    }

    private func flattenedIndex(
        for section: CommandPaletteSection,
        itemOffset: Int
    ) -> Int {
        var index = 0
        for s in visibleSections {
            if s.id == section.id {
                return index + itemOffset
            }
            index += s.items.count
        }
        return index + itemOffset
    }

    // MARK: - Keyboard Navigation

    private func moveSelection(by delta: Int) {
        let count = visibleItemCount
        guard count > 0 else { return }
        let newIndex = (selectedIndex + delta + count) % count
        withAnimation(Animations.micro) { selectedIndex = newIndex }
    }

    private func confirmSelection() {
        guard visibleItemCount > 0 else { return }
        // Brief scale pulse on the selected row
        withAnimation(Animations.micro) { confirmScale = 1.02 }
        withAnimation(Animations.micro.delay(0.06)) {
            confirmScale = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            onSelect(selectedIndex)
        }
    }
}

// MARK: - Previews

#Preview("Command Palette") {
    struct Demo: View {
        @State var query = ""
        @State var selectedIndex = 0

        var previewSections: [CommandPaletteSection] {
            [
                CommandPaletteSection(
                    title: "Recent Files",
                    items: [
                        CommandPaletteItem(icon: "doc.text", title: "ContentView.swift"),
                        CommandPaletteItem(icon: "doc.text", title: "AppDelegate.swift"),
                    ]
                ),
                CommandPaletteSection(
                    title: "Commands",
                    items: [
                        CommandPaletteItem(icon: "play.fill", title: "Run Build"),
                        CommandPaletteItem(icon: "gearshape", title: "Settings"),
                    ]
                ),
                CommandPaletteSection(
                    title: "Agents",
                    items: [
                        CommandPaletteItem(icon: "sparkles", title: "API Refactor"),
                        CommandPaletteItem(icon: "sparkles", title: "Test Writer"),
                    ]
                ),
            ]
        }

        var body: some View {
            ZStack {
                Color(hex: "#121110")
                    .ignoresSafeArea()

                CommandPalette(
                    query: $query,
                    sections: previewSections,
                    selectedIndex: $selectedIndex,
                    onSelect: { _ in },
                    onDismiss: {}
                )
            }
            .frame(width: 640, height: 500)
            .environment(\.theme, Theme(isDark: true))
        }
    }
    return Demo()
}

#Preview("Command Palette — Empty") {
    struct Demo: View {
        @State var query = "xyzzy"
        @State var selectedIndex = 0

        var body: some View {
            ZStack {
                Color(hex: "#121110")
                    .ignoresSafeArea()

                CommandPalette(
                    query: $query,
                    sections: [],
                    selectedIndex: $selectedIndex,
                    onSelect: { _ in },
                    onDismiss: {}
                )
            }
            .frame(width: 640, height: 500)
            .environment(\.theme, Theme(isDark: true))
        }
    }
    return Demo()
}
