import AppFeatures
import Git
import SwiftUI
import Workspace

@MainActor
struct WorkspaceGitDiffTabView: View {
    let workspaceID: Workspace.ID
    let path: String
    let isStaged: Bool
    let entry: WorktreeInfoEntry?
    let controller: WorkspaceOperationalController
    let onRetarget: (Bool) -> Void

    @State private var diffText: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var ignoreWhitespace = false
    @State private var contextLines = 3
    @State private var statusMessage: String?

    var body: some View {
        let stagePatchAction: ((String) -> Void)? = isStaged ? nil : { patch in
            Task { await applyStagePatch(patch) }
        }
        let discardPatchAction: (String, Bool) -> Void = { patch, wasStaged in
            Task { await applyDiscardPatch(patch, wasStaged: wasStaged) }
        }

        GitDiffDocumentView(
            filePath: path,
            diffText: diffText,
            isLoading: isLoading,
            errorMessage: errorMessage,
            isStaged: isStaged,
            ignoreWhitespace: $ignoreWhitespace,
            statusMessage: statusMessage,
            onExpandContext: {
                contextLines += 10
            },
            onShowAllContext: {
                contextLines = Int.max
            },
            onStagePatch: stagePatchAction,
            onDiscardPatch: discardPatchAction
        )
        .task(id: reloadKey) {
            await refreshDiffForCurrentSnapshot()
        }
    }

    private var reloadKey: String {
        [
            workspaceID,
            path,
            String(isStaged),
            entry?.refreshToken?.uuidString ?? "nil",
            String(ignoreWhitespace),
            String(contextLines)
        ]
        .joined(separator: "|")
    }

    private func refreshDiffForCurrentSnapshot() async {
        if let entry {
            let matchingChanges = entry.changes.filter { $0.path == path }
            if !matchingChanges.isEmpty {
                if matchingChanges.contains(where: { $0.isStaged == isStaged }) {
                    statusMessage = nil
                } else if matchingChanges.contains(where: { $0.isStaged != isStaged }) {
                    statusMessage = isStaged
                        ? "This diff moved back to unstaged changes."
                        : "This diff moved to staged changes."
                    onRetarget(!isStaged)
                    return
                } else {
                    statusMessage = "This diff no longer has local changes."
                    diffText = ""
                    errorMessage = nil
                    isLoading = false
                    return
                }
            } else if entry.isRepositoryAvailable {
                statusMessage = "This diff no longer has local changes."
                diffText = ""
                errorMessage = nil
                isLoading = false
                return
            }
        }

        statusMessage = nil
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            diffText = try await controller.diffText(
                workspaceID: workspaceID,
                path: path,
                isStaged: isStaged,
                contextLines: contextLines,
                ignoreWhitespace: ignoreWhitespace
            )
        } catch {
            diffText = nil
            errorMessage = error.localizedDescription
        }
    }

    private func applyStagePatch(_ patch: String) async {
        if let error = await controller.stageDiffPatch(workspaceID: workspaceID, patch: patch) {
            errorMessage = error
        }
    }

    private func applyDiscardPatch(_ patch: String, wasStaged: Bool) async {
        if let error = await controller.discardDiffPatch(
            workspaceID: workspaceID,
            patch: patch,
            wasStaged: wasStaged
        ) {
            errorMessage = error
        }
    }
}
