import RemoteFeatures
import RemoteCore
import SwiftUI
import UI

struct IOSRemoteRepositoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let onSave: (RemoteRepositoryRecord) -> Void
    let onCancel: () -> Void

    @State private var draft: RemoteRepositoryEditorDraft

    init(
        initialDraft: RemoteRepositoryEditorDraft,
        onSave: @escaping (RemoteRepositoryRecord) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Sheet(
                    title: draft.originalRepositoryID == nil ? "Add SSH Repository" : "Edit SSH Repository",
                    primaryAction: SheetAction(
                        title: draft.originalRepositoryID == nil ? "Save" : "Update",
                        isEnabled: draft.isSaveEnabled,
                        action: save
                    ),
                    secondaryAction: SheetAction(
                        title: "Cancel",
                        action: cancel
                    ),
                    onDismiss: cancel
                ) {
                    VStack(alignment: .leading, spacing: Spacing.space4) {
                        Text(
                            """
                            This should match the same remote authority you use from the Mac, but with direct SSH \
                            credentials for iPhone or iPad.
                            """
                        )
                            .font(Typography.body)
                            .foregroundStyle(theme.textSecondary)

                        VStack(alignment: .leading, spacing: Spacing.space3) {
                            SectionHeader("Repository")

                            FormField("SSH Target (Optional)") {
                                TextInput("mitch@mac-mini", text: $draft.sshTarget, icon: "terminal")
                            }
                            FormField("Display Name") {
                                TextInput("devys", text: $draft.displayName, icon: "folder")
                            }
                            FormField("Repository Path") {
                                TextInput("/Users/mitch/Code/devys", text: $draft.repositoryPath, icon: "folder")
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.space3) {
                            SectionHeader("SSH")

                            FormField("Host") {
                                TextInput("100.64.0.10", text: $draft.host, icon: "network")
                            }
                            HStack(spacing: Spacing.space3) {
                                FormField("Port") {
                                    TextInput("22", text: $draft.port)
                                }
                                FormField("Username") {
                                    TextInput("mitch", text: $draft.username)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.space3) {
                            SectionHeader("Authentication")

                            SegmentedControl(
                                options: ["Password", "Private Key"],
                                selectedIndex: authenticationIndexBinding
                            )

                            switch draft.authenticationMode {
                            case .password:
                                FormField("Password") {
                                    SecureInput("SSH password", text: $draft.password)
                                }
                            case .privateKey:
                                FormField("Private Key PEM") {
                                    TextEditorField(
                                        text: $draft.privateKeyPEM,
                                        minHeight: 180,
                                        isMonospaced: true
                                    )
                                }
                                FormField("Passphrase (Optional)") {
                                    SecureInput("Optional passphrase", text: $draft.privateKeyPassphrase)
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.space3)
            }
            .background(Color.clear)
        }
    }

    private var authenticationIndexBinding: Binding<Int> {
        Binding(
            get: { draft.authenticationMode == .password ? 0 : 1 },
            set: { draft.authenticationMode = $0 == 0 ? .password : .privateKey }
        )
    }

    private func save() {
        guard draft.isSaveEnabled, let record = draft.makeRecord() else { return }
        onSave(record)
        dismiss()
    }

    private func cancel() {
        onCancel()
        dismiss()
    }
}

struct IOSRemoteWorktreeCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let repository: RemoteRepositoryAuthority
    let onCreate: (RemoteWorktreeDraft) -> Void
    let onCancel: () -> Void

    @State private var branchName = ""
    @State private var startPoint = "origin/main"
    @State private var directoryName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Sheet(
                    title: "Create Worktree",
                    primaryAction: SheetAction(title: "Create", isEnabled: isCreateEnabled, action: create),
                    secondaryAction: SheetAction(title: "Cancel", action: cancel),
                    onDismiss: cancel
                ) {
                    VStack(alignment: .leading, spacing: Spacing.space4) {
                        Text(repository.railDisplayName)
                            .font(Typography.heading)
                            .foregroundStyle(theme.text)

                        Text(repository.repositoryPath)
                            .font(Typography.caption)
                            .foregroundStyle(theme.textSecondary)

                        FormField("Branch") {
                            TextInput("feature/ios-remote", text: $branchName, icon: "arrow.triangle.branch")
                        }
                        FormField("Start Point") {
                            TextInput("origin/main", text: $startPoint)
                        }
                        FormField("Directory Name") {
                            TextInput("devys-feature-ios-remote", text: $directoryName)
                        }
                    }
                }
                .padding(Spacing.space3)
            }
            .background(Color.clear)
        }
    }

    private var isCreateEnabled: Bool {
        !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        guard isCreateEnabled else { return }
        let draft = RemoteWorktreeDraft(
            repositoryID: repository.id,
            branchName: branchName,
            startPoint: startPoint,
            directoryName: directoryName
        )
        onCreate(draft)
        dismiss()
    }

    private func cancel() {
        onCancel()
        dismiss()
    }
}
