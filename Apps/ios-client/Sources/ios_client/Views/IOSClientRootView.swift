import ComposableArchitecture
import Dependencies
import RemoteFeatures
import RemoteCore
import SSH
import SwiftUI
import UI

struct IOSClientRootView: View {
    @Bindable var store: StoreOf<RemoteTerminalFeature>
    @Dependency(\.remoteWorkspaceClient) private var workspaceClient
    @Environment(\.theme) private var theme

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            IOSRemoteRepositoryList(store: store)
        } content: {
            IOSRemoteWorktreeList(store: store)
        } detail: {
            IOSRemoteWorktreeDetail(store: store)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(theme.accent)
        .preferredColorScheme(.dark)
        .task {
            store.send(.task)
        }
        .alert(
            "Connection Issue",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        store.send(.setErrorMessage(nil))
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    store.send(.setErrorMessage(nil))
                }
            },
            message: {
                Text(store.lastErrorMessage ?? "")
            }
        )
        .alert(
            "Trust SSH Host?",
            isPresented: Binding(
                get: { store.hostTrustPrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        store.send(.resolveHostTrust(false))
                    }
                }
            ),
            actions: {
                Button("Reject", role: .cancel) {
                    store.send(.resolveHostTrust(false))
                }
                Button("Trust") {
                    store.send(.resolveHostTrust(true))
                }
            },
            message: {
                if let prompt = store.hostTrustPrompt {
                    Text(
                        """
                        \(prompt.context.host):\(prompt.context.port)
                        \(prompt.context.algorithm)
                        \(prompt.context.fingerprintSHA256)
                        """
                    )
                }
            }
        )
        .sheet(
            isPresented: Binding(
                get: { store.repositoryEditor != nil },
                set: { isPresented in
                    if !isPresented {
                        store.send(.dismissRepositoryEditor)
                    }
                }
            )
        ) {
            if let draft = store.repositoryEditor {
                IOSRemoteRepositoryEditorSheet(
                    initialDraft: draft,
                    onSave: { store.send(.saveRepository($0)) },
                    onCancel: { store.send(.dismissRepositoryEditor) }
                )
                .presentationDetents([.large])
                .presentationBackground(.clear)
            }
        }
        .sheet(
            item: Binding(
                get: { store.worktreeCreationRepository },
                set: { repository in
                    if repository == nil {
                        store.send(.dismissWorktreeCreation)
                    }
                }
            )
        ) { repository in
            IOSRemoteWorktreeCreationSheet(
                repository: repository.authority,
                onCreate: { store.send(.createWorktree($0)) },
                onCancel: { store.send(.dismissWorktreeCreation) }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(.clear)
        }
        .sheet(
            isPresented: Binding(
                get: { store.isSettingsPresented },
                set: { isPresented in
                    if isPresented {
                        store.send(.presentSettings)
                    } else {
                        store.send(.dismissSettings)
                    }
                }
            )
        ) {
            IOSSettingsSheet(store: store)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { store.activeSession != nil },
                set: { isPresented in
                    if !isPresented {
                        store.send(.dismissActiveSession)
                    }
                }
            )
        ) {
            IOSRemoteSessionView(
                store: store,
                hostKeyValidator: workspaceClient.trustedHostValidator()
            )
                .presentationBackground(.clear)
        }
    }
}

// MARK: - Repository list column

struct IOSRemoteRepositoryList: View {
    @Bindable var store: StoreOf<RemoteTerminalFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        List(selection: repositorySelectionBinding) {
            ForEach(store.repositories, id: \.id) { repository in
                repositoryRow(repository)
                    .tag(Optional(repository.id))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.base.ignoresSafeArea())
        .navigationTitle("Repositories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    store.send(.presentSettings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .tint(theme.textSecondary)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.send(.presentNewRepository)
                } label: {
                    Image(systemName: "plus")
                }
                .tint(theme.text)
            }
        }
        .overlay {
            if store.repositories.isEmpty {
                EmptyState(
                    icon: "server.rack",
                    title: "No SSH Repositories",
                    description: "Add the Mac mini repository you want to control from iPhone or iPad.",
                    actionTitle: "Add Repository"
                ) {
                    store.send(.presentNewRepository)
                }
                .padding(Spacing.space4)
            }
        }
    }

    private var repositorySelectionBinding: Binding<RemoteRepositoryAuthority.ID?> {
        Binding(
            get: { store.selectedRepositoryID },
            set: { store.send(.selectRepository($0)) }
        )
    }

    @ViewBuilder
    private func repositoryRow(_ repository: RemoteRepositoryRecord) -> some View {
        HStack(spacing: Spacing.space2) {
            Image(systemName: "server.rack")
                .font(Typography.body.weight(.medium))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(repository.authority.railDisplayName)
                    .font(Typography.body)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(repository.connection.host)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            Button("Edit") {
                store.send(.presentEditRepository(repository.id))
            }
            Button("Delete", role: .destructive) {
                store.send(.removeRepository(repository.id))
            }
        }
    }
}

// MARK: - Worktree list column

struct IOSRemoteWorktreeList: View {
    @Bindable var store: StoreOf<RemoteTerminalFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let repository = store.selectedRepository {
                content(for: repository)
            } else {
                EmptyState(
                    icon: "sidebar.leading",
                    title: "Choose a Repository",
                    description: "Pick an SSH authority on the left to see its worktrees."
                )
                .padding(Spacing.space4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.base.ignoresSafeArea())
            }
        }
    }

    @ViewBuilder
    private func content(for repository: RemoteRepositoryRecord) -> some View {
        List(selection: worktreeSelectionBinding) {
            Section {
                repositoryMetadataRow(repository)
                repositoryActionsRow(repository)
            }

            worktreesSection(repository)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.base.ignoresSafeArea())
        .navigationTitle(repository.authority.railDisplayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func repositoryMetadataRow(_ repository: RemoteRepositoryRecord) -> some View {
        HStack(spacing: Spacing.space2) {
            MetadataChip(title: "Host", value: repository.connection.host)
            MetadataChip(title: "User", value: repository.connection.username)
            MetadataChip(title: "Port", value: "\(repository.connection.port)")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .padding(.vertical, Spacing.space1)
    }

    private func repositoryActionsRow(_ repository: RemoteRepositoryRecord) -> some View {
        HStack(spacing: Spacing.space2) {
            ActionButton("Refresh", icon: "arrow.clockwise", style: .ghost) {
                store.send(.refreshRepository(repository.id))
            }
            ActionButton("Fetch", icon: "arrow.down.circle", style: .ghost) {
                store.send(.fetchRepository(repository.id))
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .padding(.vertical, Spacing.space1)
    }

    private func worktreesSection(_ repository: RemoteRepositoryRecord) -> some View {
        Section {
            if store.selectedWorktrees.isEmpty {
                EmptyState(
                    icon: "square.on.square",
                    title: "No Remote Worktrees",
                    description: "Fetch or create a worktree on the Mac mini to launch a durable session."
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } else {
                ForEach(store.selectedWorktrees) { worktree in
                    worktreeRow(worktree)
                        .tag(Optional(worktree.id))
                }
            }
        } header: {
            SectionHeader(
                "Worktrees",
                count: store.selectedWorktrees.count,
                actionIcon: "plus.square.on.square"
            ) {
                store.send(.presentWorktreeCreation(repository.id))
            }
        }
    }

    private var worktreeSelectionBinding: Binding<RemoteWorktree.ID?> {
        Binding(
            get: { store.selectedWorktreeID },
            set: { store.send(.selectWorktree($0)) }
        )
    }

    @ViewBuilder
    private func worktreeRow(_ worktree: RemoteWorktree) -> some View {
        HStack(spacing: Spacing.space2) {
            Image(systemName: "arrow.triangle.branch")
                .font(Typography.body.weight(.medium))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(worktree.branchName)
                    .font(Typography.body)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(worktree.detail)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if worktree.status.isDirty {
                Chip(.status("Dirty", theme.warning))
            }
        }
    }
}

// MARK: - Worktree detail column

struct IOSRemoteWorktreeDetail: View {
    @Bindable var store: StoreOf<RemoteTerminalFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let repository = store.selectedRepository,
               let worktree = store.selectedWorktree {
                content(repository: repository, worktree: worktree)
            } else {
                EmptyState(
                    icon: "terminal",
                    title: "Select a Worktree",
                    description: "Pick a worktree to attach, pull, push, or open a durable shell."
                )
                .padding(Spacing.space4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.base.ignoresSafeArea())
            }
        }
    }

    @ViewBuilder
    private func content(
        repository: RemoteRepositoryRecord,
        worktree: RemoteWorktree
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                summary(worktree: worktree, repository: repository)
                actions(repository: repository, worktree: worktree)
                shellsSection(repository: repository, worktree: worktree)
            }
            .padding(Spacing.space3)
        }
        .background(theme.base.ignoresSafeArea())
        .navigationTitle(worktree.branchName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(
        worktree: RemoteWorktree,
        repository: RemoteRepositoryRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.space1) {
                    Text(worktree.branchName)
                        .font(Typography.title)
                        .foregroundStyle(theme.text)

                    Text(worktree.remotePath)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Spacing.space1) {
                    Chip(
                        .status(
                            worktree.status.isDirty ? "Dirty" : "Clean",
                            worktree.status.isDirty ? theme.warning : theme.success
                        )
                    )
                    if worktree.isPrimary {
                        Text("Primary")
                            .font(Typography.micro.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }
                }
            }

            HStack(spacing: Spacing.space2) {
                MetadataChip(title: "Host", value: repository.authority.hostLabel)
                if let headSHA = worktree.headSHA {
                    MetadataChip(title: "HEAD", value: String(headSHA.prefix(8)))
                }
            }
        }
        .padding(Spacing.space4)
        .elevation(.card)
    }

    private func actions(
        repository: RemoteRepositoryRecord,
        worktree: RemoteWorktree
    ) -> some View {
        HStack(spacing: Spacing.space2) {
            ActionButton("Pull", icon: "arrow.down.to.line", style: .ghost) {
                store.send(.pullWorktree(repositoryID: repository.id, worktreeID: worktree.id))
            }
            ActionButton("Push", icon: "arrow.up.to.line", style: .ghost) {
                store.send(.pushWorktree(repositoryID: repository.id, worktreeID: worktree.id))
            }
            Spacer()
            ActionButton("Shell", icon: "terminal", style: .primary) {
                store.send(.openSession(repositoryID: repository.id, worktreeID: worktree.id))
            }
        }
    }

    @ViewBuilder
    private func shellsSection(
        repository: RemoteRepositoryRecord,
        worktree: RemoteWorktree
    ) -> some View {
        let sessions = store.selectedWorktreeShellSessions

        VStack(alignment: .leading, spacing: Spacing.space3) {
            SectionHeader("Shells", count: sessions.count)

            if sessions.isEmpty {
                Text("Open a shell to create a durable tmux session on the remote host.")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.space4)
                    .elevation(.card)
            } else {
                VStack(spacing: Spacing.space2) {
                    ForEach(sessions, id: \.id) { session in
                        shellRow(session, repository: repository, worktree: worktree)
                    }
                }
            }
        }
    }

    private func shellRow(
        _ session: SSHRemoteShellSession,
        repository: RemoteRepositoryRecord,
        worktree: RemoteWorktree
    ) -> some View {
        Button {
            store.send(.openSession(repositoryID: repository.id, worktreeID: worktree.id))
        } label: {
            HStack(spacing: Spacing.space2) {
                Image(systemName: "terminal")
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.sessionName)
                        .font(Typography.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)

                    if let createdAt = session.createdAt {
                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(Typography.micro)
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                Spacer()

                Text(session.isAttached ? "Attached" : "Detached")
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(session.isAttached ? theme.success : theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.space3)
            .elevation(.card)
        }
        .buttonStyle(.plain)
    }
}
