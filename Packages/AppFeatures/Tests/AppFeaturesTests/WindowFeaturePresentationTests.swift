import AppFeatures
import ComposableArchitecture
import Foundation
import Testing
import Workspace

@Suite("WindowFeature Presentation Tests")
struct WindowFeaturePresentationTests {
    @Test("Presenting workspace creation resolves the repository in reducer state")
    @MainActor
    func presentWorkspaceCreation() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let store = TestStore(
            initialState: WindowFeature.State(repositories: [repository])
        ) {
            WindowFeature()
        }

        await store.send(.presentWorkspaceCreation(repositoryID: repository.id, mode: .importedWorktree)) {
            $0.workspaceCreationPresentation = WorkspaceCreationPresentation(
                repository: repository,
                mode: .importedWorktree
            )
        }

        await store.send(.setWorkspaceCreationPresentation(nil)) {
            $0.workspaceCreationPresentation = nil
        }
    }

    @Test("Chat launch and git presentations are reducer-owned")
    @MainActor
    func shellPresentations() async {
        let launchPresentation = ChatLaunchPresentation(
            workspaceID: "/tmp/devys-project/workspaces/feature",
            initialAttachments: [.snippet(language: "swift", content: "print(\"hi\")")]
        )
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        }

        await store.send(.setChatLaunchPresentation(launchPresentation)) {
            $0.chatLaunchPresentation = launchPresentation
        }

        await store.send(.setGitCommitSheetPresented(true)) {
            $0.isGitCommitSheetPresented = true
        }

        await store.send(.setCreatePullRequestSheetPresented(true)) {
            $0.isCreatePullRequestSheetPresented = true
        }

        await store.send(.setChatLaunchPresentation(nil)) {
            $0.chatLaunchPresentation = nil
        }
    }

    @Test("Hosted workspace content summaries are reducer-owned")
    @MainActor
    func hostedWorkspaceContent() async {
        let workspaceID = "/tmp/devys-project/workspaces/feature"
        let content = HostedWorkspaceContentState(
            editorDocuments: [
                HostedEditorDocumentSummary(
                    url: URL(fileURLWithPath: "/tmp/devys-project/README.md"),
                    title: "README.md",
                    isDirty: true,
                    isLoading: false
                )
            ],
            chatSessions: [
                HostedChatSessionSummary(
                    sessionID: ChatSessionID(rawValue: "session-1"),
                    kind: .codex,
                    title: "Codex",
                    icon: "chevron.left.forwardslash.chevron.right",
                    subtitle: "Connected",
                    isBusy: true,
                    isRestorable: true,
                    createdAt: Date(timeIntervalSince1970: 1),
                    lastActivityAt: Date(timeIntervalSince1970: 2)
                )
            ]
        )
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        }

        await store.send(.setHostedWorkspaceContent(workspaceID, content)) {
            $0.hostedWorkspaceContentByID[workspaceID] = content
        }

        await store.send(.removeHostedWorkspaceContent(workspaceID)) {
            $0.hostedWorkspaceContentByID.removeValue(forKey: workspaceID)
        }
    }
}
