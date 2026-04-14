// ContentView+FileTreeActions.swift
// Explicit file tree rename/delete operations and editor reconciliation.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import Foundation
import Split
import Workspace

@MainActor
extension ContentView {
    func handleFileTreeDeletionNotification(_ notification: Notification) {
        guard let activeRuntime,
              let activeModel = activeRuntime.fileTreeModel,
              let sourceModel = notification.object as? FileTreeModel,
              sourceModel === activeModel,
              let deletedURLs = notification.userInfo?[FileTreeModel.deletedURLsUserInfoKey] as? [URL] else {
            return
        }

        let affectedTabIDs = editorTabIDs(affectedBy: collapseNestedURLs(deletedURLs))
        let cleanTabIDs = affectedTabIDs.filter { editorSessions[$0]?.isDirty != true }
        closeEditorTabs(cleanTabIDs)
    }

    func renameFileTreeItem(_ url: URL, in workspaceID: Workspace.ID) {
        let normalizedURL = canonicalEditorSessionURL(url)
        let currentName = normalizedURL.lastPathComponent
        let title = isDirectoryURL(normalizedURL) ? "Rename Folder" : "Rename File"
        let message = "Enter a new name for \(currentName)."

        guard let proposedName = promptForFileTreeItemName(
            currentValue: currentName,
            title: title,
            message: message
        ) else {
            return
        }

        guard proposedName != currentName else { return }

        let destinationURL = normalizedURL
            .deletingLastPathComponent()
            .appendingPathComponent(proposedName, isDirectory: isDirectoryURL(normalizedURL))
            .standardizedFileURL

        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            showFileTreeAlert(
                style: .critical,
                title: "Rename Failed",
                message: "\(destinationURL.lastPathComponent) already exists."
            )
            return
        }

        do {
            try FileManager.default.moveItem(at: normalizedURL, to: destinationURL)
            retargetEditorTabs(from: normalizedURL, to: destinationURL)
            Task {
                await runtimeRegistry.runtimeHandle(for: workspaceID)?.fileTreeModel?.refresh()
                await runtimeRegistry.runtimeHandle(for: workspaceID)?.fileTreeModel?.revealURL(destinationURL)
            }
        } catch {
            showFileTreeAlert(
                style: .critical,
                title: "Rename Failed",
                message: error.localizedDescription
            )
        }
    }

    func deleteFileTreeItems(_ urls: [URL], in workspaceID: Workspace.ID) async {
        let targets = collapseNestedURLs(urls.map(canonicalEditorSessionURL))
        guard !targets.isEmpty else { return }

        let affectedTabIDs = editorTabIDs(affectedBy: targets)
        let dirtyTabIDs = affectedTabIDs.filter { editorSessions[$0]?.isDirty == true }

        guard confirmDeleteFileTreeItems(targets, dirtyTabCount: dirtyTabIDs.count) else {
            return
        }

        closeEditorTabs(affectedTabIDs)

        var failures: [(URL, Error)] = []
        for target in targets {
            do {
                try FileManager.default.trashItem(at: target, resultingItemURL: nil)
            } catch {
                failures.append((target, error))
            }
        }

        await runtimeRegistry.runtimeHandle(for: workspaceID)?.fileTreeModel?.refresh()

        if !failures.isEmpty {
            let failedNames = failures.map { $0.0.lastPathComponent }.joined(separator: ", ")
            let detail = failures.first?.1.localizedDescription ?? "Unknown error"
            showFileTreeAlert(
                style: .critical,
                title: "Delete Failed",
                message: "Could not move \(failedNames) to Trash.\n\n\(detail)"
            )
        }
    }
}

@MainActor
private extension ContentView {
    func editorTabIDs(affectedBy targets: [URL]) -> [TabID] {
        let normalizedTargets = targets.map(canonicalEditorSessionURL)
        return tabContents.compactMap { tabID, content in
            guard case .editor(_, let editorURL) = content else { return nil }
            let normalizedEditorURL = canonicalEditorSessionURL(editorURL)

            let isAffected = normalizedTargets.contains { targetURL in
                normalizedEditorURL == targetURL || isDescendant(normalizedEditorURL, of: targetURL)
            }

            return isAffected ? tabID : nil
        }
    }

    func closeEditorTabs(_ tabIDs: [TabID]) {
        for tabID in tabIDs {
            guard let paneID = paneID(for: tabID) else { continue }
            closeBypass.insert(tabID)
            _ = controller.closeTab(tabID, inPane: paneID)
        }
    }

    func paneID(for tabID: TabID) -> PaneID? {
        for paneID in controller.allPaneIds
        where controller.tabs(inPane: paneID).contains(where: { $0.id == tabID }) {
            return paneID
        }
        return nil
    }

    func retargetEditorTabs(from oldBaseURL: URL, to newBaseURL: URL) {
        let normalizedOldBaseURL = canonicalEditorSessionURL(oldBaseURL)
        let normalizedNewBaseURL = canonicalEditorSessionURL(newBaseURL)

        let affectedTabIDs = tabContents.compactMap { tabID, content -> TabID? in
            guard case .editor(_, let editorURL) = content else { return nil }
            let normalizedEditorURL = canonicalEditorSessionURL(editorURL)
            let isAffected = normalizedEditorURL == normalizedOldBaseURL
                || isDescendant(normalizedEditorURL, of: normalizedOldBaseURL)
            return isAffected ? tabID : nil
        }

        for tabID in affectedTabIDs {
            guard case .editor(_, let editorURL)? = tabContents[tabID] else { continue }
            let retargetedURL = retargetURL(
                canonicalEditorSessionURL(editorURL),
                from: normalizedOldBaseURL,
                to: normalizedNewBaseURL
            )
            updateEditorTabURL(tabId: tabID, newURL: retargetedURL)
        }
    }

    func collapseNestedURLs(_ urls: [URL]) -> [URL] {
        let uniqueURLs = Array(Set(urls.map(canonicalEditorSessionURL))).sorted { $0.path < $1.path }
        return uniqueURLs.filter { candidate in
            !uniqueURLs.contains { other in
                other != candidate && isDescendant(candidate, of: other)
            }
        }
    }

    func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let ancestorPath = canonicalEditorSessionURL(ancestor).path
        let candidatePath = canonicalEditorSessionURL(candidate).path
        return candidatePath.hasPrefix(ancestorPath + "/")
    }

    func retargetURL(_ url: URL, from oldBaseURL: URL, to newBaseURL: URL) -> URL {
        let oldPath = oldBaseURL.path
        let newPath = newBaseURL.path
        let candidatePath: String

        if url == oldBaseURL {
            candidatePath = newPath
        } else {
            candidatePath = url.path.replacingOccurrences(
                of: oldPath,
                with: newPath,
                options: .anchored
            )
        }

        return URL(fileURLWithPath: candidatePath).standardizedFileURL
    }

    func promptForFileTreeItemName(
        currentValue: String,
        title: String,
        message: String
    ) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.stringValue = currentValue
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let trimmedValue = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    func confirmDeleteFileTreeItems(_ urls: [URL], dirtyTabCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning

        let itemLabel = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
        alert.messageText = "Move \(itemLabel) to Trash?"

        if dirtyTabCount > 0 {
            alert.informativeText = """
            \(dirtyTabCount) open editor tab\(dirtyTabCount == 1 ? "" : "s") have unsaved changes.

            Continuing will close those tabs without saving and move the selected items to Trash.
            """
            alert.addButton(withTitle: "Close Without Saving")
        } else {
            alert.informativeText = "The selected items will be moved to Trash."
            alert.addButton(withTitle: "Move to Trash")
        }

        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    func showFileTreeAlert(style: NSAlert.Style, title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
