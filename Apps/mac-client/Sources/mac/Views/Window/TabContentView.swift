// TabContentView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Observation
import Split
import Editor
import Git
import GhosttyTerminal
import UI
import Workspace

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
    let agentSession: AgentSessionRuntime?
    let agentComposerSpeechService: any AgentComposerSpeechService
    let onOpenAgentInlineTerminal: (Workspace.ID, UUID) -> Void
    let onOpenAgentFollowTarget: (Workspace.ID, AgentFollowTarget, Bool) -> Void
    let onOpenAgentDiffArtifact: (Workspace.ID, AgentDiffContent, Bool) -> Void
    let editorSession: EditorSession?
    let selectedRepositoryRootURL: URL?
    let selectedRepositoryDisplayName: String?
    let onFocus: () -> Void
    let onAttentionAcknowledged: () -> Void
    let onPresentationChange: () -> Void
    let onEditorURLChange: (URL) -> Void
    let onEditorPresentationChange: (EditorOpenPerformanceSnapshot?) -> Void

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
            case .agentSession:
                if let agentSession {
                    let openInlineTerminal: (UUID) -> Void = { terminalID in
                        onOpenAgentInlineTerminal(agentSession.workspaceID, terminalID)
                    }
                    AgentSessionView(
                        session: agentSession,
                        speechService: agentComposerSpeechService,
                        onOpenTerminalTab: openInlineTerminal,
                        onOpenLocationTarget: { target, prefersPreview in
                            onOpenAgentFollowTarget(agentSession.workspaceID, target, prefersPreview)
                        },
                        onOpenDiffArtifact: { diff, prefersPreview in
                            onOpenAgentDiffArtifact(agentSession.workspaceID, diff, prefersPreview)
                        }
                    )
                } else {
                    PlaceholderView(
                        icon: "message",
                        title: "Agent session unavailable",
                        subtitle: "The selected agent session could not be restored."
                    )
                }
            case .gitDiff:
                if let store = gitStore {
                    GitDiffView(store: store)
                } else {
                    PlaceholderView(icon: "plus.forwardslash.minus", title: "Diff", subtitle: "No repository open")
                }
            case .settings:
                SettingsView(
                    repositoryRootURL: selectedRepositoryRootURL,
                    repositoryDisplayName: selectedRepositoryDisplayName
                )
            case .editor(_, let url):
                if let session = editorSession {
                    editorContent(for: session, url: url)
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
            TapGesture().onEnded {
                onFocus()
                onAttentionAcknowledged()
            }
        )
        .onChange(of: presentationSnapshot) { _, _ in
            onPresentationChange()
        }
        .onAppear {
            onEditorPresentationChange(editorPerformanceSnapshot)
        }
        .onChange(of: editorPerformanceSnapshot) { _, snapshot in
            onEditorPresentationChange(snapshot)
        }
    }

    private var presentationSnapshot: String {
        switch content {
        case .terminal:
            [
                terminalSession?.tabTitle ?? "",
                terminalSession?.tabIcon ?? ""
            ]
            .joined(separator: "|")
        case .agentSession:
            [
                agentSession?.tabTitle ?? "",
                agentSession?.tabIcon ?? "",
                agentSession?.tabSubtitle ?? "",
                String(agentSession?.tabIsBusy == true)
            ]
            .joined(separator: "|")
        case .editor:
            editorSession?.isDirty == true ? "dirty" : "clean"
        default:
            ""
        }
    }

    private func tooLargeSubtitle(for preview: EditorSessionPreview, fallback: String) -> String {
        if let fileSize = preview.fileSize {
            let fileSizeLabel = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            let limitLabel = ByteCountFormatter.string(
                fromByteCount: Int64(preview.maxBytes),
                countStyle: .file
            )
            return "\(fileSizeLabel) exceeds \(limitLabel)"
        }
        return fallback
    }

    @ViewBuilder
    private func editorContent(for session: EditorSession, url: URL) -> some View {
        VStack(spacing: 0) {
            if session.isFindPresented {
                EditorFindBar(session: session)
            }

            if let document = session.document {
                EditorView(
                    document: document,
                    onDocumentURLChange: onEditorURLChange,
                    focusRequestID: session.focusRequestID,
                    searchMatches: session.findMatches,
                    activeSearchMatchID: session.activeFindMatchID,
                    navigationRequestID: session.navigationRequestID,
                    navigationTarget: session.navigationTarget
                )
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
                case .preview(let preview) where preview.isBinary:
                    PlaceholderView(
                        icon: "doc",
                        title: "Binary file",
                        subtitle: url.lastPathComponent
                    )
                case .preview(let preview) where preview.isTooLarge:
                    PlaceholderView(
                        icon: "doc.text.magnifyingglass",
                        title: "File too large",
                        subtitle: tooLargeSubtitle(for: preview, fallback: url.lastPathComponent)
                    )
                case .preview, .loaded:
                    PlaceholderView(icon: "doc.text", title: "Loading", subtitle: url.lastPathComponent)
                }
            }
        }
    }

    private var editorPerformanceSnapshot: EditorOpenPerformanceSnapshot? {
        guard case .editor = content,
              let editorSession else {
            return nil
        }

        switch editorSession.phase {
        case .idle, .loading:
            return .loading
        case .failed:
            return .failed(fileSize: editorSession.currentFileSize)
        case .preview(let preview):
            if preview.isBinary {
                return .binary(fileSize: preview.fileSize)
            }
            if preview.isTooLarge {
                return .tooLarge(fileSize: preview.fileSize)
            }
            return .previewText(fileSize: preview.fileSize)
        case .loaded:
            return .loaded(fileSize: editorSession.currentFileSize)
        }
    }
}

@MainActor
private struct EditorFindBar: View {
    @Environment(\.devysTheme) private var theme
    @Bindable var session: EditorSession
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            TextField("Find in file", text: $session.findQuery)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    session.selectNextFindMatch()
                }

            Text(matchSummary)
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            Button {
                session.selectPreviousFindMatch()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text)
            .disabled(session.findMatches.isEmpty)

            Button {
                session.selectNextFindMatch()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text)
            .disabled(session.findMatches.isEmpty)

            Button {
                session.dismissFind()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)
        }
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            session.dismissFind()
        }
    }

    private var matchSummary: String {
        guard !session.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Type to search"
        }
        guard !session.findMatches.isEmpty else {
            return "No results"
        }
        let currentIndex = (session.activeFindMatchIndex ?? 0) + 1
        return "\(currentIndex) of \(session.findMatches.count)"
    }
}
