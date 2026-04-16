// WorkspaceCreationSheet.swift
// Create or import workspaces for a repository.

import AppKit
import AppFeatures
import Git
import SwiftUI
import UI
import Workspace

@MainActor
struct WorkspaceCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let repository: Repository
    let defaults: WorkspaceCreationDefaults
    let creationService: WorkspaceCreationService
    let onComplete: @MainActor ([Workspace]) async -> Void

    @State private var selectedMode: WorkspaceCreationMode
    @State private var branchReferences: [WorkspaceBranchReference] = []
    @State private var pullRequests: [PullRequest] = []
    @State private var newBranchName: String = ""
    @State private var selectedBaseReference: String = ""
    @State private var selectedExistingBranchName: String?
    @State var pullRequestReference: String = ""
    @State private var selectedPullRequestNumber: Int?
    @State var importedWorktreeURLs: [URL] = []
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        repository: Repository,
        defaults: WorkspaceCreationDefaults,
        creationService: WorkspaceCreationService,
        initialMode: WorkspaceCreationMode = .newBranch,
        onComplete: @escaping @MainActor ([Workspace]) async -> Void
    ) {
        self.repository = repository
        self.defaults = defaults
        self.creationService = creationService
        self.onComplete = onComplete
        _selectedMode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    repositorySection
                    modeSection
                    modeContentSection
                }
                .formStyle(.grouped)

                Divider()

                actionBar
            }
            .navigationTitle("Create Workspace")
            .frame(width: 640, height: 560)
            .task {
                await loadOptions()
            }
            .alert("Workspace Creation Failed", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var repositorySection: some View {
        Section("Repository") {
            LabeledContent("Name", value: repository.displayName)
            LabeledContent("Path", value: repository.rootURL.path)
        }
    }

    private var modeSection: some View {
        Section("Flow") {
            Picker("Mode", selection: $selectedMode) {
                ForEach(WorkspaceCreationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var modeContentSection: some View {
        switch selectedMode {
        case .newBranch:
            newBranchSection
        case .existingBranch:
            existingBranchSection
        case .pullRequest:
            pullRequestSection
        case .importedWorktree:
            importedWorktreeSection
        }
    }

    private var newBranchSection: some View {
        Section("New Branch") {
            TextField("Branch name", text: $newBranchName)

            Picker("Base", selection: $selectedBaseReference) {
                ForEach(baseReferenceOptions, id: \.self) { reference in
                    Text(reference).tag(reference)
                }
            }

            LabeledContent("Destination", value: destinationPath(for: newBranchName))
        }
    }

    private var existingBranchSection: some View {
        Section("Existing Branch") {
            Picker("Branch", selection: existingBranchSelection) {
                Text("Select a branch").tag(Optional<String>.none)
                ForEach(existingBranchOptions) { branch in
                    Text(branch.displayName).tag(Optional(branch.name))
                }
            }

            if let selectedBranch = selectedExistingBranch {
                LabeledContent(
                    "Destination",
                    value: destinationPath(for: selectedBranch.displayName)
                )
            }
        }
    }

    private var pullRequestSection: some View {
        Section("Pull Request") {
            TextField("PR number or GitHub URL", text: $pullRequestReference)

            Picker("Open PR", selection: selectedPullRequestSelection) {
                Text("Select a pull request").tag(Optional<Int>.none)
                ForEach(pullRequests) { pullRequest in
                    Text("#\(pullRequest.number) \(pullRequest.title)").tag(Optional(pullRequest.number))
                }
            }

            if let pullRequest = selectedPullRequest {
                LabeledContent(
                    "Destination",
                    value: destinationPath(for: "pr/\(pullRequest.number)-\(pullRequest.headBranch)")
                )
            }
        }
    }

    private var importedWorktreeSection: some View {
        Section("Imported Worktrees") {
            Button("Choose Worktrees...") {
                selectImportedWorktrees()
            }

            if importedWorktreeURLs.isEmpty {
                Text("No worktrees selected")
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(importedWorktreeURLs, id: \.path) { url in
                    Text(url.path)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if isLoading || isSubmitting {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(primaryButtonTitle) {
                Task { await submit() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isLoading || isSubmitting || !canSubmit)
        }
        .padding(16)
    }

    private var baseReferenceOptions: [String] {
        let options = branchReferences.map(\.displayName)
        if options.contains(defaults.defaultBaseBranch) {
            return options
        }
        return [defaults.defaultBaseBranch] + options
    }

    private var existingBranchOptions: [WorkspaceBranchReference] {
        branchReferences.filter { !($0.isCurrent && !$0.isRemote) }
    }

    private var selectedExistingBranch: WorkspaceBranchReference? {
        guard let selectedExistingBranchName else { return nil }
        return existingBranchOptions.first { $0.name == selectedExistingBranchName }
    }

    var selectedPullRequest: PullRequest? {
        if let selectedPullRequestNumber {
            return pullRequests.first { $0.number == selectedPullRequestNumber }
        }
        return nil
    }

    private var existingBranchSelection: Binding<String?> {
        Binding(
            get: { selectedExistingBranchName },
            set: { selectedExistingBranchName = $0 }
        )
    }

    private var selectedPullRequestSelection: Binding<Int?> {
        Binding(
            get: { selectedPullRequestNumber },
            set: { selectedPullRequestNumber = $0 }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var primaryButtonTitle: String {
        selectedMode == .importedWorktree ? "Import Worktrees" : "Create Workspace"
    }

    private var canSubmit: Bool {
        switch selectedMode {
        case .newBranch:
            return !newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .existingBranch:
            return selectedExistingBranch != nil
        case .pullRequest:
            return selectedPullRequest != nil
                || !pullRequestReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .importedWorktree:
            return !importedWorktreeURLs.isEmpty
        }
    }

    private func loadOptions() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let loadedBranches = creationService.listBranches(in: repository.rootURL)
            async let loadedPullRequests = creationService.listPullRequests(in: repository.rootURL)

            branchReferences = try await loadedBranches
            pullRequests = try await loadedPullRequests
            selectedBaseReference = baseReferenceOptions.first ?? defaults.defaultBaseBranch
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let workspaces = try await createWorkspaces()
            await onComplete(workspaces)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createWorkspaces() async throws -> [Workspace] {
        switch selectedMode {
        case .newBranch:
            let workspace = try await creationService.createWorkspace(
                in: repository,
                request: .newBranch(
                    name: newBranchName,
                    baseReference: selectedBaseReference
                )
            )
            return [workspace]

        case .existingBranch:
            guard let branch = selectedExistingBranch else {
                return []
            }
            let workspace = try await creationService.createWorkspace(
                in: repository,
                request: .existingBranch(branch)
            )
            return [workspace]

        case .pullRequest:
            let pullRequest = try await resolvedPullRequest()
            let workspace = try await creationService.createWorkspace(
                in: repository,
                request: .pullRequest(pullRequest)
            )
            return [workspace]

        case .importedWorktree:
            return try await creationService.importWorkspaces(
                at: importedWorktreeURLs,
                into: repository
            )
        }
    }
}
