import AppFeatures
import Git
import SwiftUI
import Workspace

@MainActor
extension ContentView {
    var searchPresentationBinding: Binding<WindowFeature.SearchPresentation?> {
        Binding(
            get: { store.searchPresentation },
            set: { store.send(.setSearchPresentation($0)) }
        )
    }

    var workspaceCreationPresentationBinding: Binding<WorkspaceCreationPresentation?> {
        Binding(
            get: { store.workspaceCreationPresentation },
            set: { store.send(.setWorkspaceCreationPresentation($0)) }
        )
    }

    var reviewEntryPresentationBinding: Binding<WindowFeature.ReviewEntryPresentation?> {
        Binding(
            get: { store.reviewEntryPresentation },
            set: { store.send(.setReviewEntryPresentation($0)) }
        )
    }

    var addRepositoryPresentationBinding: Binding<AddRepositoryPresentation?> {
        Binding(
            get: { store.addRepositoryPresentation },
            set: { store.send(.setAddRepositoryPresentation($0)) }
        )
    }

    var chatLaunchPresentationBinding: Binding<ChatLaunchPresentation?> {
        Binding(
            get: { store.chatLaunchPresentation },
            set: { store.send(.setChatLaunchPresentation($0)) }
        )
    }

    var remoteRepositoryPresentationBinding: Binding<RemoteRepositoryPresentation?> {
        Binding(
            get: { store.remoteRepositoryPresentation },
            set: { store.send(.setRemoteRepositoryPresentation($0)) }
        )
    }

    var remoteWorktreeCreationPresentationBinding: Binding<RemoteWorktreeCreationPresentation?> {
        Binding(
            get: { store.remoteWorktreeCreationPresentation },
            set: { store.send(.setRemoteWorktreeCreationPresentation($0)) }
        )
    }

    var gitCommitSheetBinding: Binding<Bool> {
        Binding(
            get: { store.isGitCommitSheetPresented },
            set: { store.send(.setGitCommitSheetPresented($0)) }
        )
    }

    var createPullRequestSheetBinding: Binding<Bool> {
        Binding(
            get: { store.isCreatePullRequestSheetPresented },
            set: { store.send(.setCreatePullRequestSheetPresented($0)) }
        )
    }

    var notificationsPanelBinding: Binding<Bool> {
        Binding(
            get: { store.isNotificationsPanelPresented },
            set: { store.send(.setNotificationsPanelPresented($0)) }
        )
    }

    func applyWindowPresentations<V: View>(_ view: V) -> some View {
        applyGitPresentations(
            applySearchAndNotificationsPresentations(
                applyPrimarySheetPresentations(view)
            )
        )
    }

    func applyPrimarySheetPresentations<V: View>(_ view: V) -> some View {
        view
            .sheet(item: addRepositoryPresentationBinding, content: addRepositorySheet)
            .sheet(item: workspaceCreationPresentationBinding, content: workspaceCreationSheet)
            .sheet(item: reviewEntryPresentationBinding, content: reviewTargetPickerSheet)
            .sheet(item: chatLaunchPresentationBinding, content: chatProviderSheet)
            .sheet(item: remoteRepositoryPresentationBinding, content: remoteRepositorySheet)
            .sheet(item: remoteWorktreeCreationPresentationBinding, content: remoteWorktreeSheet)
    }

    func workspaceCreationSheet(
        for request: WorkspaceCreationPresentation
    ) -> some View {
        presentedSheetContent(
            WorkspaceCreationSheet(
                repository: request.repository,
                defaults: repositorySettingsStore.settings(for: request.repository.rootURL)
                    .workspaceCreation,
                creationService: container.workspaceCreationService,
                initialMode: request.mode
            ) { workspaces in
                await handleCreatedWorkspaces(workspaces, in: request.repository)
            }
        )
    }

    func chatProviderSheet(
        for request: ChatLaunchPresentation
    ) -> some View {
        presentedSheetContent(
            ChatProviderPickerSheet(
                onSelect: { kind in
                    store.send(.setChatLaunchPresentation(nil))
                    if let pendingSessionID = request.pendingSessionID {
                        launchPreparedChatSession(
                            kind,
                            workspaceID: request.workspaceID,
                            sessionID: pendingSessionID
                        )
                    } else {
                        openChatSession(
                            kind,
                            workspaceID: request.workspaceID,
                            initialAttachments: request.initialAttachments,
                            preferredPaneID: request.preferredPaneID
                        )
                    }
                },
                onCancel: {
                    store.send(.setChatLaunchPresentation(nil))
                    if let pendingSessionID = request.pendingSessionID,
                       let pendingTabID = request.pendingTabID {
                        cancelPreparedChatSessionLaunch(
                            workspaceID: request.workspaceID,
                            sessionID: pendingSessionID,
                            tabID: pendingTabID
                        )
                    }
                }
            )
        )
    }

    func reviewTargetPickerSheet(
        for presentation: WindowFeature.ReviewEntryPresentation
    ) -> some View {
        presentedSheetContent(
            ReviewTargetPickerSheet(
                presentation: presentation,
                onSelect: { targetKind in
                    store.send(.startManualReview(workspaceID: presentation.workspaceID, targetKind: targetKind))
                },
                onCancel: {
                    store.send(.setReviewEntryPresentation(nil))
                }
            )
        )
    }

    func remoteRepositorySheet(
        for presentation: RemoteRepositoryPresentation
    ) -> some View {
        presentedSheetContent(
            RemoteRepositorySheet(
                initialAuthority: presentation.authority,
                recentAuthorities: store.remoteRepositories,
                onSave: { authority in
                    saveRemoteRepository(authority)
                },
                onCancel: {
                    store.send(.setRemoteRepositoryPresentation(nil))
                }
            )
        )
    }

    func remoteWorktreeSheet(
        for presentation: RemoteWorktreeCreationPresentation
    ) -> some View {
        presentedSheetContent(
            RemoteWorktreeCreationSheet(
                repository: store.remoteRepositories.first {
                    $0.id == presentation.draft.repositoryID
                },
                draft: presentation.draft,
                onCreate: { draft in
                    createRemoteWorktree(draft)
                },
                onCancel: {
                    store.send(.setRemoteWorktreeCreationPresentation(nil))
                }
            )
        )
    }

    func applySearchAndNotificationsPresentations<V: View>(_ view: V) -> some View {
        view
            .sheet(item: searchPresentationBinding) { presentation in
                presentedSheetContent(searchSheetContent(for: presentation))
            }
            .sheet(isPresented: notificationsPanelBinding) {
                presentedSheetContent(notificationsPanelContent)
            }
    }

    func applyGitPresentations<V: View>(_ view: V) -> some View {
        view
            .sheet(isPresented: gitCommitSheetBinding) {
                if let workspaceID = visibleWorkspaceID,
                   let entry = workspaceOperationalState.metadataEntriesByWorkspaceID[workspaceID] {
                    presentedSheetContent(
                        WorkspaceGitCommitSheet(
                            branchName: entry.repositoryInfo?.currentBranch ?? entry.branchName,
                            stagedChanges: entry.stagedChanges
                        ) { message, push in
                            await workspaceOperationalController.commit(
                                workspaceID: workspaceID,
                                message: message,
                                push: push
                            )
                        }
                    )
                }
            }
            .sheet(isPresented: createPullRequestSheetBinding) {
                if let workspaceID = visibleWorkspaceID,
                   let entry = workspaceOperationalState.metadataEntriesByWorkspaceID[workspaceID] {
                    presentedSheetContent(
                        WorkspaceCreatePullRequestSheet(
                            currentBranch: entry.repositoryInfo?.currentBranch ?? entry.branchName,
                            workspaceID: workspaceID,
                            controller: workspaceOperationalController
                        ) { _ in
                            Task { @MainActor in
                                await handleCreatedPullRequest()
                            }
                        }
                    )
                }
            }
    }

    func presentedSheetContent<V: View>(_ view: V) -> some View {
        view
            .environment(\.devysTheme, theme)
            .preferredColorScheme(themeManager.preferredColorScheme)
    }
}
