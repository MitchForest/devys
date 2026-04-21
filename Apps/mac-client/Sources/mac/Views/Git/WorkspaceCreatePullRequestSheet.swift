import SwiftUI
import UI
import Workspace

@MainActor
struct WorkspaceCreatePullRequestSheet: View {
    @Environment(\.devysTheme) private var theme
    let currentBranch: String?
    let workspaceID: Workspace.ID
    let controller: WorkspaceOperationalController
    let onCreated: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var baseBranch = "main"
    @State private var branches: [String] = []
    @State private var isDraft = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            formContent
            Divider()
            footerView
        }
        .frame(width: 500, height: 500)
        .task {
            branches = await controller.loadLocalBranchNames(workspaceID: workspaceID)
            if let firstBranch = branches.first, !branches.contains(baseBranch) {
                baseBranch = firstBranch
            }
            isTitleFocused = true
        }
        .alert("Failed to Create PR", isPresented: Binding(
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
            Text("Create Pull Request")
                .font(Typography.heading)
                .foregroundStyle(theme.text)

            Spacer()

            if let currentBranch {
                HStack(spacing: Spacing.space1) {
                    Text(currentBranch)
                        .font(Typography.Code.gutter.weight(.medium))
                        .foregroundStyle(theme.accent)

                    Image(systemName: "arrow.right")
                        .font(Typography.micro)
                        .foregroundStyle(theme.textTertiary)

                    Text(baseBranch)
                        .font(Typography.Code.gutter.weight(.medium))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.space5)
        .padding(.vertical, Spacing.space3)
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                VStack(alignment: .leading, spacing: Spacing.space1) {
                    Text("Base Branch")
                        .font(Typography.caption.weight(.medium))
                        .foregroundStyle(theme.textSecondary)

                    Picker("Base Branch", selection: $baseBranch) {
                        ForEach(branches.isEmpty ? ["main"] : branches, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: Spacing.space1) {
                    Text("Title")
                        .font(Typography.caption.weight(.medium))
                        .foregroundStyle(theme.textSecondary)

                    HStack {
                        TextField("PR title", text: $title)
                            .textFieldStyle(.plain)
                            .font(Typography.body)
                            .foregroundStyle(theme.text)
                            .focused($isTitleFocused)
                    }
                    .padding(.horizontal, Spacing.space3)
                    .padding(.vertical, Spacing.space2)
                    .inputChrome(.card, isFocused: isTitleFocused)
                }

                VStack(alignment: .leading, spacing: Spacing.space1) {
                    Text("Description")
                        .font(Typography.caption.weight(.medium))
                        .foregroundStyle(theme.textSecondary)

                    TextEditorField(text: $bodyText, minHeight: 150)
                }

                Toggle("Create as draft", isOn: $isDraft)
                    .toggleStyle(.checkbox)
                    .font(Typography.label)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(Spacing.space5)
        }
    }

    private var footerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(action: createPR) {
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Text(isDraft ? "Create Draft PR" : "Create Pull Request")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreate || isCreating)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, Spacing.space5)
        .padding(.vertical, Spacing.space3)
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createPR() {
        guard canCreate else { return }

        isCreating = true
        Task {
            let result = await controller.createPullRequest(
                workspaceID: workspaceID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: bodyText,
                base: baseBranch,
                draft: isDraft
            )
            isCreating = false
            switch result {
            case .success(let prNumber):
                onCreated(prNumber)
                dismiss()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}
