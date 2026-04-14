// WorkspaceSearchPanelView.swift
// Shared keyboard-driven workspace search panel.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import SwiftUI
import UI

struct WorkspaceSearchPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let presentation: WorkspaceSearchPresentation
    let query: Binding<String>
    let items: [WorkspaceSearchItem]
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (WorkspaceSearchItem) -> Void

    @State private var selectedItemID: WorkspaceSearchItem.ID?
    @State private var keyMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .overlay(theme.borderSubtle)
            results
        }
        .frame(width: 760, height: 540)
        .background(theme.base)
        .onAppear {
            isSearchFocused = true
            selectFirstResult()
            installKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onChange(of: query.wrappedValue) { _, _ in
            selectFirstResult()
        }
        .onChange(of: items) { _, _ in
            selectFirstResult()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.title)
                .font(DevysTypography.heading)
                .tracking(DevysTypography.headerTracking)
                .foregroundStyle(theme.textSecondary)

            TextField(presentation.placeholder, text: query)
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
                if let errorMessage {
                    errorState(message: errorMessage)
                } else if isLoading && items.isEmpty {
                    loadingState
                } else if items.isEmpty {
                    emptyState
                } else {
                    ForEach(items) { item in
                        button(for: item)
                    }
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        stateCard(
            title: presentation.emptyTitle,
            message: presentation.emptySubtitle
        )
    }

    private var loadingState: some View {
        stateCard(
            title: "Searching",
            message: "Collecting results for the current workspace."
        )
    }

    private func errorState(message: String) -> some View {
        stateCard(
            title: "Search unavailable",
            message: message
        )
    }

    private func stateCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DevysTypography.base)
                .foregroundStyle(theme.textSecondary)

            Text(message)
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(theme.surface)
        .clipShape(.rect(cornerRadius: DevysSpacing.radiusMd))
    }

    private func button(for item: WorkspaceSearchItem) -> some View {
        Button {
            execute(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.visibleAccent)
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

                if let accessory = item.accessory {
                    Text(accessory)
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
        guard !items.isEmpty else { return }
        guard let selectedItemID,
              let currentIndex = items.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = items.first?.id
            return
        }

        let nextIndex = max(0, min(items.count - 1, currentIndex + offset))
        self.selectedItemID = items[nextIndex].id
    }

    private func selectFirstResult() {
        selectedItemID = items.first?.id
    }

    private func executeSelectedItem() {
        guard let selectedItemID,
              let item = items.first(where: { $0.id == selectedItemID }) ?? items.first else {
            return
        }
        execute(item)
    }

    private func execute(_ item: WorkspaceSearchItem) {
        onSelect(item)
        dismiss()
    }
}
