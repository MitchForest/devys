// TabContentView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Split
import Editor
import Git
import GhosttyTerminal
import UI

struct WelcomeTabContent: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TabContentView: View {
    @Environment(\.devysTheme) private var theme

    let tab: Split.Tab
    let content: TabContent?
    let gitStore: GitStore?
    let terminalSession: GhosttyTerminalSession?
    let editorSession: EditorSession?
    let onFocus: () -> Void
    let onEditorURLChange: (URL) -> Void

    var body: some View {
        ZStack {
            switch content {
            case .welcome:
                WelcomeTabContent()
            case .terminal:
                if let terminalSession {
                    GhosttyTerminalView(session: terminalSession)
                } else {
                    TerminalRewritePlaceholderView(workingDirectory: nil, requestedCommand: nil)
                }
            case .gitDiff:
                if let store = gitStore {
                    GitDiffView(store: store)
                } else {
                    PlaceholderView(icon: "plus.forwardslash.minus", title: "Diff", subtitle: "No repository open")
                }
            case .settings:
                SettingsView()
            case .editor(let url):
                if let session = editorSession {
                    if let document = session.document {
                        EditorView(document: document, onDocumentURLChange: onEditorURLChange)
                    } else {
                        switch session.phase {
                        case .loading, .idle:
                            PlaceholderView(icon: "doc.text", title: "Loading", subtitle: url.lastPathComponent)
                        case .failed(let message):
                            PlaceholderView(
                                icon: "exclamationmark.triangle",
                                title: "Failed to load",
                                subtitle: message
                            )
                        case .preview, .loaded:
                            PlaceholderView(icon: "doc.text", title: "Loading", subtitle: url.lastPathComponent)
                        }
                    }
                } else {
                    PlaceholderView(
                        icon: "exclamationmark.triangle",
                        title: "Editor session unavailable",
                        subtitle: url.lastPathComponent
                    )
                }
            case .none:
                PlaceholderView(icon: "doc", title: tab.title, subtitle: "")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded { onFocus() }
        )
    }
}
