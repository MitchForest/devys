import ComposableArchitecture
import Diff
import Foundation
import Git

@Reducer
struct DiffTabFeature {
    @ObservableState
    struct State: Equatable {
        var change: GitFileChange
        var projectRootURL: URL?
        var diffSnapshot: DiffSnapshot?
        var mode: DiffViewMode = .unified
        var isGitActionRunning = false
        var isLoading = false
        var errorMessage: String?
        var gitRefreshCount = 0

        init(change: GitFileChange, projectRootURL: URL? = nil) {
            self.change = change
            self.projectRootURL = projectRootURL?.standardizedFileURL
        }

        var canDiscardActiveChange: Bool {
            change.status != .ignored && change.status != .unmerged
        }

        var statusMessage: String {
            change.isStaged ? "Staged \(change.status.rawValue)" : "Unstaged \(change.status.rawValue)"
        }
    }

    enum Action: Equatable {
        case task
        case modeChanged(DiffViewMode)
        case loadDiffRequested
        case diffLoaded(DiffSnapshot)
        case diffFailed(String)
        case fileActionRequested(DiffGitAction)
        case fileDiscardConfirmed
        case fileDiscardCancelled
        case fileActionSucceeded(DiffGitAction)
        case fileActionFailed(String)
        case hunkActionRequested(DiffGitAction, hunkIndex: Int)
        case hunkDiscardConfirmed(Int)
        case hunkDiscardCancelled
        case hunkActionSucceeded(DiffGitAction)
        case hunkActionFailed(String)
        case copyPathRequested
        case copyPathFinished
    }

    @Dependency(\.alertClient) private var alertClient
    @Dependency(\.diffModePersistenceClient) private var diffModePersistenceClient
    @Dependency(\.gitRepositoryClient) private var gitRepositoryClient
    @Dependency(\.pasteboardClient) private var pasteboardClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.mode = diffModePersistenceClient.loadMode()
                return .send(.loadDiffRequested)

            case let .modeChanged(mode):
                state.mode = mode
                diffModePersistenceClient.saveMode(mode)
                return .none

            case .loadDiffRequested:
                guard let projectRootURL = state.projectRootURL else {
                    state.errorMessage = "No project root is associated with this diff tab."
                    state.diffSnapshot = nil
                    state.isLoading = false
                    return .none
                }
                state.isLoading = true
                state.errorMessage = nil
                let change = state.change
                return .run { send in
                    do {
                        let snapshot = try await gitRepositoryClient.diffSnapshot(projectRootURL, change)
                        await send(.diffLoaded(snapshot))
                    } catch {
                        await send(.diffFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: DiffEffectID.load(projectRootURL.path, change.id), cancelInFlight: true)

            case let .diffLoaded(snapshot):
                state.diffSnapshot = snapshot
                state.isLoading = false
                state.errorMessage = nil
                return .none

            case let .diffFailed(message):
                state.diffSnapshot = nil
                state.isLoading = false
                state.errorMessage = message
                return .none

            case let .fileActionRequested(action):
                guard !state.isGitActionRunning else { return .none }
                if action == .discard {
                    guard state.canDiscardActiveChange else { return .none }
                    let change = state.change
                    return .run { send in
                        let confirmed = await alertClient.confirm(Self.discardAlertRequest(for: change, isHunk: false))
                        await send(confirmed ? .fileDiscardConfirmed : .fileDiscardCancelled)
                    }
                }
                return runFileAction(state: &state, action: action)

            case .fileDiscardConfirmed:
                return runFileAction(state: &state, action: .discard)

            case .fileDiscardCancelled:
                return .none

            case let .fileActionSucceeded(action):
                state.isGitActionRunning = false
                state.errorMessage = nil
                state.gitRefreshCount += 1
                switch action {
                case .stage:
                    state.change = GitFileChange(
                        path: state.change.path,
                        previousPath: state.change.previousPath,
                        status: state.change.status == .untracked ? .added : state.change.status,
                        isStaged: true
                    )
                case .unstage:
                    state.change = GitFileChange(
                        path: state.change.path,
                        previousPath: state.change.previousPath,
                        status: state.change.status,
                        isStaged: false
                    )
                case .discard:
                    break
                }
                return .send(.loadDiffRequested)

            case let .fileActionFailed(message):
                state.isGitActionRunning = false
                state.errorMessage = message
                return .none

            case let .hunkActionRequested(action, hunkIndex):
                guard !state.isGitActionRunning,
                      let hunks = state.diffSnapshot?.hunks,
                      hunks.indices.contains(hunkIndex) else {
                    return .none
                }
                if action == .discard {
                    let change = state.change
                    return .run { send in
                        let confirmed = await alertClient.confirm(Self.discardAlertRequest(for: change, isHunk: true))
                        await send(confirmed ? .hunkDiscardConfirmed(hunkIndex) : .hunkDiscardCancelled)
                    }
                }
                return runHunkAction(state: &state, action: action, hunkIndex: hunkIndex)

            case let .hunkDiscardConfirmed(hunkIndex):
                return runHunkAction(state: &state, action: .discard, hunkIndex: hunkIndex)

            case .hunkDiscardCancelled:
                return .none

            case .hunkActionSucceeded:
                state.isGitActionRunning = false
                state.errorMessage = nil
                state.gitRefreshCount += 1
                return .send(.loadDiffRequested)

            case let .hunkActionFailed(message):
                state.isGitActionRunning = false
                state.errorMessage = message
                return .none

            case .copyPathRequested:
                let path = state.change.path
                return .run { send in
                    await pasteboardClient.writeString(path)
                    await send(.copyPathFinished)
                }

            case .copyPathFinished:
                return .none
            }
        }
    }

    private func runFileAction(state: inout State, action: DiffGitAction) -> Effect<Action> {
        guard let projectRootURL = state.projectRootURL else { return .none }
        state.isGitActionRunning = true
        state.errorMessage = nil
        let change = state.change
        return .run { send in
            do {
                switch action {
                case .stage:
                    try await gitRepositoryClient.stageFile(projectRootURL, change)
                case .unstage:
                    try await gitRepositoryClient.unstageFile(projectRootURL, change)
                case .discard:
                    try await gitRepositoryClient.discardFile(projectRootURL, change)
                }
                await send(.fileActionSucceeded(action))
            } catch {
                await send(.fileActionFailed(error.localizedDescription))
            }
        }
        .cancellable(id: DiffEffectID.fileAction(projectRootURL.path, change.id), cancelInFlight: true)
    }

    private func runHunkAction(
        state: inout State,
        action: DiffGitAction,
        hunkIndex: Int
    ) -> Effect<Action> {
        guard let projectRootURL = state.projectRootURL,
              let hunks = state.diffSnapshot?.hunks,
              hunks.indices.contains(hunkIndex) else {
            return .none
        }

        state.isGitActionRunning = true
        state.errorMessage = nil
        let change = state.change
        let hunk = hunks[hunkIndex]
        return .run { send in
            do {
                switch action {
                case .stage:
                    try await gitRepositoryClient.stageHunk(projectRootURL, hunk, change)
                case .unstage:
                    try await gitRepositoryClient.unstageHunk(projectRootURL, hunk, change)
                case .discard:
                    try await gitRepositoryClient.discardHunk(projectRootURL, hunk, change)
                }
                await send(.hunkActionSucceeded(action))
            } catch {
                await send(.hunkActionFailed(error.localizedDescription))
            }
        }
        .cancellable(id: DiffEffectID.hunkAction(projectRootURL.path, change.id, hunk.id), cancelInFlight: true)
    }

    private static func discardAlertRequest(for change: GitFileChange, isHunk: Bool) -> AlertRequest {
        AlertRequest(
            title: isHunk
                ? "Discard hunk in \(change.filename)?"
                : (change.status == .untracked ? "Move \(change.filename) to Trash?" : "Discard changes to \(change.filename)?"),
            message: change.status == .untracked
                ? "The untracked file will be moved to Trash."
                : "The current working copy will be moved to Trash when a file exists, then git will restore the selected changes.",
            confirmTitle: isHunk ? "Discard Hunk" : "Discard Changes",
            cancelTitle: "Cancel"
        )
    }

    private enum DiffEffectID: Hashable {
        case load(String, String)
        case fileAction(String, String)
        case hunkAction(String, String, String)
    }
}

enum DiffGitAction: Sendable, Equatable {
    case stage
    case unstage
    case discard
}
