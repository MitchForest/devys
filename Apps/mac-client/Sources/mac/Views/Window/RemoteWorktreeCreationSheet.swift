import AppFeatures
import RemoteCore
import SwiftUI
import UI

struct RemoteWorktreeCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let repository: RemoteRepositoryAuthority?
    let draft: RemoteWorktreeDraft
    let onCreate: (RemoteWorktreeDraft) -> Void
    let onCancel: () -> Void

    @State private var branchName: String
    @State private var startPoint: String
    @State private var directoryName: String

    init(
        repository: RemoteRepositoryAuthority?,
        draft: RemoteWorktreeDraft,
        onCreate: @escaping (RemoteWorktreeDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.repository = repository
        self.draft = draft
        self.onCreate = onCreate
        self.onCancel = onCancel
        _branchName = State(initialValue: draft.branchName)
        _startPoint = State(initialValue: draft.startPoint)
        _directoryName = State(initialValue: draft.directoryName)
    }

    var body: some View {
        Sheet(
            title: "Create Remote Worktree",
            primaryAction: SheetAction(title: "Create", isEnabled: isCreateEnabled, action: create),
            secondaryAction: SheetAction(title: "Cancel", action: cancel),
            onDismiss: cancel
        ) {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                if let repository {
                    Text("\(repository.railDisplayName) • \(repository.repositoryPath)")
                        .font(Typography.body)
                        .foregroundStyle(theme.textSecondary)
                }

                FormField("Branch") {
                    TextInput("feature/ssh-remote", text: $branchName)
                }
                FormField("Start Point") {
                    TextInput("origin/main", text: $startPoint)
                }
                FormField("Directory Name") {
                    TextInput("devys-feature-ssh-remote", text: $directoryName)
                }
            }
        }
        .frame(width: 520)
    }

    private var isCreateEnabled: Bool {
        !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        guard isCreateEnabled else { return }
        onCreate(
            RemoteWorktreeDraft(
                repositoryID: draft.repositoryID,
                branchName: branchName,
                startPoint: startPoint,
                directoryName: directoryName,
                id: draft.id
            )
        )
        dismiss()
    }

    private func cancel() {
        onCancel()
        dismiss()
    }
}
