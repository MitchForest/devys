import AppFeatures
import Git
import SwiftUI
import UI

@MainActor
struct WorkspaceGitSidebarView: View {
    @Environment(\.devysTheme) var theme

    let entry: WorktreeInfoEntry
    let selectedDiffPath: String?
    let selectedDiffIsStaged: Bool?
    let onPreviewDiff: (String, Bool) -> Void
    let onOpenDiff: (String, Bool) -> Void
    let onAddDiffToChat: (String, Bool) -> Void
    let onInitializeGit: (() -> Void)?
    let onStageFile: @MainActor (String) async -> Void
    let onUnstageFile: @MainActor (String) async -> Void
    let onStageAll: @MainActor () async -> Void
    let onUnstageAll: @MainActor () async -> Void
    let onDiscardChange: @MainActor (GitFileChange) async -> Void
    let onCommit: @MainActor (String, Bool) async -> String?
    let onFetch: @MainActor () async -> Void
    let onPull: @MainActor () async -> Void
    let onPush: @MainActor () async -> Void

    @State var showingCommitSheet = false
    @State var expandedSections: Set<String> = ["staged", "unstaged"]
    @State var hoveredSection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage = entry.errorMessage,
               !errorMessage.isEmpty {
                errorBanner(errorMessage)
            }

            gitContent

            Divider()
            actionsFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingCommitSheet) {
            WorkspaceGitCommitSheet(
                branchName: entry.repositoryInfo?.currentBranch ?? entry.branchName,
                stagedChanges: entry.stagedChanges,
                onCommit: onCommit
            )
        }
    }
}
