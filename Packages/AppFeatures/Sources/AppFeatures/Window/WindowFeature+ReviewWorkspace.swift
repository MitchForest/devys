import ComposableArchitecture
import Foundation
import Workspace

extension WindowFeature {
    func reduceReviewWorkspaceAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .reviewWorkspaceLoadRequested(let workspaceID):
            state.updateReviewWorkspace(workspaceID) { workspaceState in
                workspaceState.isLoading = true
                workspaceState.lastErrorMessage = nil
            }
            guard let rootURL = state.worktree(for: workspaceID)?.repositoryRootURL else {
                return .none
            }
            return loadReviewWorkspaceEffect(workspaceID: workspaceID, rootURL: rootURL)

        case let .reviewWorkspaceLoaded(workspaceID, snapshot):
            let issuesByRunID = Dictionary(
                grouping: snapshot.issues.map { reviewHydratedIssue($0) },
                by: \.runID
            )

            state.updateReviewWorkspace(workspaceID) { workspaceState in
                workspaceState.runs = snapshot.runs
                workspaceState.issuesByRunID = issuesByRunID.mapValues { $0.sorted(by: reviewIssueSort) }
                workspaceState.isLoading = false
                workspaceState.lastErrorMessage = nil
            }
            return .none

        case let .reviewWorkspaceLoadFailed(workspaceID, message):
            state.updateReviewWorkspace(workspaceID) { workspaceState in
                workspaceState.isLoading = false
                workspaceState.lastErrorMessage = message
            }
            return .none

        default:
            return .none
        }
    }

    func loadReviewWorkspaceEffect(
        workspaceID: Workspace.ID,
        rootURL: URL
    ) -> Effect<Action> {
        let reviewPersistenceClient = self.reviewPersistenceClient
        return .run { send in
            do {
                let snapshot = try await reviewPersistenceClient.loadWorkspace(workspaceID, rootURL)
                await send(.reviewWorkspaceLoaded(workspaceID, snapshot))
            } catch {
                await send(.reviewWorkspaceLoadFailed(workspaceID, error.localizedDescription))
            }
        }
    }
}

private func reviewHydratedIssue(
    _ issue: ReviewIssue
) -> ReviewIssue {
    var hydrated = issue
    hydrated.followUpPromptArtifactPath = reviewNormalizedOptionalString(
        hydrated.followUpPromptArtifactPath
    )
    return hydrated
}

private func reviewNormalizedOptionalString(
    _ value: String?
) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
