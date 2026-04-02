// ContentView+Chat.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import ChatUI
import Workspace
import Foundation

extension ContentView {
    /// Opens a chat in a preview tab (single-click behavior)
    func openChatInPreviewTab(_ session: ChatCore.Session) {
        openInPreviewTab(content: .chatSession(id: session.id))
    }

    /// Opens a chat in a permanent tab (double-click behavior)
    func openChatInPermanentTab(_ session: ChatCore.Session) {
        openInPermanentTab(content: .chatSession(id: session.id))
    }

    /// Creates a new chat and opens it in a tab
    func createNewChat() {
        // Check if a default harness is set in settings
        if let defaultHarness = resolvedDefaultHarness() {
            // Use the default harness from settings
            createChatWithHarness(defaultHarness)
        } else {
            // No default set - show picker
            showHarnessPicker = true
        }
    }

    /// Creates a chat with a specific harness
    func createChatWithHarness(_ harness: ChatCore.HarnessType) {
        Task {
            await appStore?.createSession(harnessType: harness)
        }
    }

    /// Adds a file to the currently active chat session's composer.
    /// If no chat is active, creates a new one.
    func addFileToActiveChat(_ url: URL) {
        let attachment = ComposerAttachment.file(url: url)
        addAttachmentToActiveChat(attachment)
    }

    /// Adds a git diff to the currently active chat session's composer.
    /// If no chat is active, creates a new one.
    func addDiffToActiveChat(path: String, isStaged: Bool) {
        let attachment = ComposerAttachment.gitDiff(path: path, isStaged: isStaged)
        addAttachmentToActiveChat(attachment)
    }

    /// Adds an attachment to the active chat or creates a new chat.
    func addAttachmentToActiveChat(_ attachment: ComposerAttachment) {
        // Try to find any open chat session tab and add there
        for (tabId, content) in tabContents {
            if case .chatSession = content {
                appStore?.addAttachment(attachment)
                selectTab(tabId)
                return
            }
        }

        // If no active chat, create a new one and add the attachment
        Task {
            // Determine harness - use default if set
            let harness: ChatCore.HarnessType
            if let defaultHarness = resolvedDefaultHarness() {
                harness = defaultHarness
            } else {
                harness = .claudeCode
            }

            await appStore?.createSession(harnessType: harness)
            appStore?.addAttachment(attachment)
        }
    }

    private func resolvedDefaultHarness() -> ChatCore.HarnessType? {
        guard let storedValue = appSettings.agent.defaultHarness else {
            return nil
        }

        switch storedValue.lowercased() {
        case "codex":
            return .codex
        case "claudecode", "claude-code", "claude code":
            return .claudeCode
        default:
            let harness = ChatCore.HarnessType(rawValue: storedValue)
            if harness.rawValue == "codex" || harness.rawValue == "claude-code" {
                return harness
            }
            return nil
        }
    }
}
