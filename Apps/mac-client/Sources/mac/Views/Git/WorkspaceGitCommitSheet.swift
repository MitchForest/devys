import Git
import SwiftUI
import UI

@MainActor
struct WorkspaceGitCommitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let branchName: String?
    let stagedChanges: [GitFileChange]
    let onCommit: @MainActor (String, Bool) async -> String?

    @State private var message = ""
    @State private var extendedMessage = ""
    @State private var pushAfterCommit = false
    @State private var errorMessage: String?
    @State private var isCommitting = false
    @FocusState private var isMessageFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            VStack(alignment: .leading, spacing: Spacing.space4) {
                stagedFilesSummary
                subjectLineField
                extendedMessageField
                Toggle("Push after committing", isOn: $pushAfterCommit)
                    .toggleStyle(.checkbox)
                    .font(Typography.label)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(Spacing.space5)

            Divider()
            footerView
        }
        .frame(width: 500, height: 450)
        .onAppear {
            isMessageFocused = true
        }
        .alert("Commit Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var headerView: some View {
        HStack {
            Text("Commit Changes")
                .font(Typography.heading)
                .foregroundStyle(theme.text)

            Spacer()

            if let branchName {
                HStack(spacing: Spacing.space1) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(Typography.micro)
                        .foregroundStyle(theme.textSecondary)

                    Text(branchName)
                        .font(Typography.Code.gutter.weight(.medium))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.space5)
        .padding(.vertical, Spacing.space3)
    }

    private var stagedFilesSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            Text("Staged Changes (\(stagedChanges.count))")
                .font(Typography.caption.weight(.medium))
                .foregroundStyle(theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.space2) {
                    ForEach(stagedChanges.prefix(10)) { file in
                        HStack(spacing: Spacing.space1) {
                            Image(systemName: file.status.iconName)
                                .font(Typography.micro)
                                .foregroundStyle(statusColor(file.status))

                            Text(file.filename)
                                .font(Typography.micro)
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, Spacing.space2)
                        .padding(.vertical, 3)
                        .background(theme.overlay)
                        .overlay {
                            Capsule()
                                .strokeBorder(theme.border, lineWidth: Spacing.borderWidth)
                        }
                        .clipShape(Capsule())
                    }

                    if stagedChanges.count > 10 {
                        Text("+\(stagedChanges.count - 10) more")
                            .font(Typography.micro)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
    }

    private var subjectLineField: some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            HStack {
                Text("Subject")
                    .font(Typography.caption.weight(.medium))
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                Text("\(message.count)/72")
                    .font(Typography.Code.gutter)
                    .foregroundStyle(message.count > 72 ? DevysColors.warning : theme.textTertiary)
            }

            HStack {
                TextField("Brief description of changes", text: $message)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundStyle(theme.text)
                    .focused($isMessageFocused)
                    .onSubmit {
                        if canCommit {
                            commit()
                        }
                    }
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space2)
            .inputChrome(.card, isFocused: isMessageFocused)
        }
    }

    private var extendedMessageField: some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            Text("Extended Description (optional)")
                .font(Typography.caption.weight(.medium))
                .foregroundStyle(theme.textSecondary)

            TextEditorField(
                text: $extendedMessage,
                minHeight: 100,
                isMonospaced: true
            )
        }
    }

    private var footerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(action: commit) {
                if isCommitting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Text(pushAfterCommit ? "Commit & Push" : "Commit")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canCommit || isCommitting)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, Spacing.space5)
        .padding(.vertical, Spacing.space3)
    }

    private var canCommit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !stagedChanges.isEmpty
    }

    private func commit() {
        guard canCommit else { return }

        isCommitting = true
        let fullMessage = extendedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? message
            : message + "\n\n" + extendedMessage

        Task {
            let result = await onCommit(fullMessage, pushAfterCommit)
            isCommitting = false
            if let result {
                errorMessage = result
            } else {
                dismiss()
            }
        }
    }

    private func statusColor(_ status: Git.GitFileStatus) -> Color {
        switch status {
        case .modified:
            .orange
        case .added:
            DevysColors.success
        case .deleted:
            DevysColors.error
        case .renamed, .copied, .untracked, .ignored, .unmerged:
            DevysColors.darkTextSecondary
        }
    }
}
