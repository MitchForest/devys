// ContentView+SearchPaletteSurface.swift
// Shared search palette presentation for file and text search.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

@MainActor
struct ContentViewSearchPaletteSurface: View {
    @Environment(\.dismiss) private var dismiss

    let mode: WorkspaceSearchMode
    let sectionTitle: String
    let items: [WorkspaceSearchItem]
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (WorkspaceSearchItem) -> Void

    @Binding var query: String
    @State private var selectedIndex = 0

    var body: some View {
        CommandPalette(
            query: $query,
            sections: sections,
            selectedIndex: $selectedIndex,
            placeholder: mode.placeholder,
            emptyTitle: emptyTitle,
            emptySubtitle: emptySubtitle,
            onSelect: selectItem(at:)
        ) {
            dismiss()
        }
        .onAppear {
            resetSelection()
        }
        .onChange(of: query) { _, _ in
            resetSelection()
        }
    }

    private var sections: [CommandPaletteSection] {
        guard !items.isEmpty else { return [] }

        return [
            CommandPaletteSection(
                title: sectionTitle,
                items: items.map(paletteItem(for:))
            )
        ]
    }

    private var emptyTitle: String {
        if errorMessage != nil {
            return "Search unavailable"
        }
        if isLoading {
            return "Searching"
        }
        return mode.emptyTitle
    }

    private var emptySubtitle: String? {
        if let errorMessage {
            return errorMessage
        }
        if isLoading {
            return switch mode {
            case .commands:
                "Gathering matching commands."
            case .files:
                "Scanning files in the active workspace."
            case .textSearch:
                "Scanning file contents in the active workspace."
            }
        }
        return mode.emptySubtitle
    }

    private func paletteItem(for item: WorkspaceSearchItem) -> CommandPaletteItem {
        CommandPaletteItem(
            icon: item.systemImage,
            title: item.title,
            subtitle: item.subtitle,
            shortcut: item.accessory
        )
    }

    private func resetSelection() {
        selectedIndex = 0
    }

    private func selectItem(at index: Int) {
        guard items.indices.contains(index) else {
            dismiss()
            return
        }

        onSelect(items[index])
        dismiss()
    }
}
