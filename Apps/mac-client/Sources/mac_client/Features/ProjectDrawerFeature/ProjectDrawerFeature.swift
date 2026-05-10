import ComposableArchitecture
import Foundation
import Git

@Reducer
struct ProjectDrawerFeature {
    @ObservableState
    struct State: Equatable {
        var projectRootURL: URL?
        var isPinned = false
        var isTransientlyVisible = false
        var expandedDirectoryPaths: Set<String> = []
        var fileRows: [ProjectFileRow] = []
        var filesIsLoading = false
        var gitChanges: [GitFileChange] = []
        var gitActionIDs: Set<String> = []
        var gitIsRepositoryAvailable = false
        var gitIsLoading = false
        var gitErrorMessage: String?
        var localPorts: [LocalPort] = []
        var localPortsIsLoading = false
        var localPortsErrorMessage: String?
        var searchQuery = ""
        var changesExpanded = true
        var filesExpanded = true

        init(projectRootURL: URL? = nil) {
            self.projectRootURL = projectRootURL?.standardizedFileURL
        }

        var trimmedSearchQuery: String {
            searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    enum Action: Equatable {
        case task(projectRootURL: URL?)
        case pinLoaded(Bool)
        case sectionStateLoaded(ProjectDrawerSectionState)
        case togglePin
        case reveal
        case hide
        case setChangesExpanded(Bool)
        case setFilesExpanded(Bool)
        case searchQueryChanged(String)
        case clearSearch
        case toggleDirectory(URL)
        case fileRowsLoadingChanged(Bool)
        case fileRowsLoaded([ProjectFileRow])
        case gitRefreshRequested
        case gitRefreshStarted
        case gitStatusLoaded([GitFileChange])
        case gitNotRepository
        case gitFailed(String)
        case gitStageFileRequested(GitFileChange)
        case gitUnstageFileRequested(GitFileChange)
        case gitDiscardFileRequested(GitFileChange)
        case gitDiscardFileConfirmed(GitFileChange)
        case gitDiscardFileCancelled(String)
        case gitActionFailed(String, String)
        case gitActionFinished(String)
        case localPortsRefreshRequested
        case localPortsLoaded([LocalPort])
        case localPortsFailed(String)
    }

    @Dependency(\.projectDrawerPersistenceClient) private var persistence
    @Dependency(\.localPortsClient) private var localPortsClient
    @Dependency(\.gitRepositoryClient) private var gitRepositoryClient
    @Dependency(\.alertClient) private var alertClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .task(projectRootURL):
                let standardizedProjectRootURL = projectRootURL?.standardizedFileURL
                state.projectRootURL = standardizedProjectRootURL
                state.isPinned = persistence.loadPinned(standardizedProjectRootURL)
                let sectionState = persistence.loadSections(standardizedProjectRootURL)
                state.changesExpanded = sectionState.changesExpanded
                state.filesExpanded = sectionState.filesExpanded
                return .none

            case let .pinLoaded(isPinned):
                state.isPinned = isPinned
                return .none

            case let .sectionStateLoaded(sectionState):
                state.changesExpanded = sectionState.changesExpanded
                state.filesExpanded = sectionState.filesExpanded
                return .none

            case .togglePin:
                state.isPinned.toggle()
                if state.isPinned {
                    state.isTransientlyVisible = false
                }
                persistence.savePinned(state.projectRootURL, state.isPinned)
                return .none

            case .reveal:
                guard !state.isPinned else { return .none }
                state.isTransientlyVisible = true
                return .none

            case .hide:
                guard !state.isPinned else { return .none }
                state.isTransientlyVisible = false
                return .none

            case let .setChangesExpanded(isExpanded):
                state.changesExpanded = isExpanded
                persistence.saveSections(
                    state.projectRootURL,
                    ProjectDrawerSectionState(
                        changesExpanded: state.changesExpanded,
                        filesExpanded: state.filesExpanded
                    )
                )
                return .none

            case let .setFilesExpanded(isExpanded):
                state.filesExpanded = isExpanded
                persistence.saveSections(
                    state.projectRootURL,
                    ProjectDrawerSectionState(
                        changesExpanded: state.changesExpanded,
                        filesExpanded: state.filesExpanded
                    )
                )
                return .none

            case let .searchQueryChanged(query):
                state.searchQuery = query
                return .none

            case .clearSearch:
                state.searchQuery = ""
                return .none

            case let .toggleDirectory(url):
                let path = url.standardizedFileURL.path
                if state.expandedDirectoryPaths.contains(path) {
                    state.expandedDirectoryPaths.remove(path)
                } else {
                    state.expandedDirectoryPaths.insert(path)
                }
                return .none

            case let .fileRowsLoadingChanged(isLoading):
                state.filesIsLoading = isLoading
                return .none

            case let .fileRowsLoaded(rows):
                state.fileRows = rows
                state.filesIsLoading = false
                return .none

            case .gitRefreshRequested:
                guard let projectRootURL = state.projectRootURL else {
                    state.gitChanges = []
                    state.gitIsRepositoryAvailable = false
                    state.gitIsLoading = false
                    state.gitErrorMessage = nil
                    return .none
                }
                state.gitIsLoading = true
                return .run { send in
                    do {
                        let changes = try await gitRepositoryClient.status(projectRootURL)
                        await send(.gitStatusLoaded(changes))
                    } catch GitError.notRepository {
                        await send(.gitNotRepository)
                    } catch {
                        await send(.gitFailed(error.localizedDescription))
                    }
                }
                .cancellable(
                    id: GitEffectID.status(projectRootURL.path),
                    cancelInFlight: true
                )

            case .gitRefreshStarted:
                state.gitIsLoading = true
                return .none

            case let .gitStatusLoaded(changes):
                state.gitChanges = changes
                state.gitIsRepositoryAvailable = true
                state.gitIsLoading = false
                state.gitErrorMessage = nil
                return .none

            case .gitNotRepository:
                state.gitChanges = []
                state.gitIsRepositoryAvailable = false
                state.gitIsLoading = false
                state.gitErrorMessage = nil
                return .none

            case let .gitFailed(message):
                state.gitChanges = []
                state.gitIsRepositoryAvailable = false
                state.gitIsLoading = false
                state.gitErrorMessage = message
                return .none

            case let .gitActionFinished(id):
                state.gitActionIDs.remove(id)
                return .none

            case let .gitActionFailed(id, message):
                state.gitActionIDs.remove(id)
                state.gitChanges = []
                state.gitIsRepositoryAvailable = false
                state.gitIsLoading = false
                state.gitErrorMessage = message
                return .none

            case let .gitStageFileRequested(change):
                return runGitFileAction(
                    state: &state,
                    change: change,
                    operation: gitRepositoryClient.stageFile
                )

            case let .gitUnstageFileRequested(change):
                return runGitFileAction(
                    state: &state,
                    change: change,
                    operation: gitRepositoryClient.unstageFile
                )

            case let .gitDiscardFileRequested(change):
                guard state.projectRootURL != nil,
                      !state.gitActionIDs.contains(change.id) else {
                    return .none
                }
                return .run { send in
                    let confirmed = await alertClient.confirm(Self.discardAlertRequest(for: change))
                    if confirmed {
                        await send(.gitDiscardFileConfirmed(change))
                    } else {
                        await send(.gitDiscardFileCancelled(change.id))
                    }
                }

            case let .gitDiscardFileConfirmed(change):
                return runGitFileAction(
                    state: &state,
                    change: change,
                    operation: gitRepositoryClient.discardFile
                )

            case .gitDiscardFileCancelled:
                return .none

            case .localPortsRefreshRequested:
                guard let projectRootURL = state.projectRootURL else {
                    state.localPorts = []
                    state.localPortsIsLoading = false
                    state.localPortsErrorMessage = nil
                    return .none
                }
                state.localPortsIsLoading = true
                state.localPortsErrorMessage = nil
                return .run { send in
                    do {
                        let ports = try await localPortsClient.detect(projectRootURL)
                        await send(.localPortsLoaded(ports))
                    } catch {
                        await send(.localPortsFailed(error.localizedDescription))
                    }
                }

            case let .localPortsLoaded(ports):
                state.localPorts = ports
                state.localPortsIsLoading = false
                state.localPortsErrorMessage = nil
                return .none

            case let .localPortsFailed(message):
                state.localPorts = []
                state.localPortsIsLoading = false
                state.localPortsErrorMessage = message
                return .none
            }
        }
    }

    private func runGitFileAction(
        state: inout State,
        change: GitFileChange,
        operation: @escaping @Sendable (URL, GitFileChange) async throws -> Void
    ) -> Effect<Action> {
        guard let projectRootURL = state.projectRootURL,
              !state.gitActionIDs.contains(change.id) else {
            return .none
        }

        state.gitActionIDs.insert(change.id)
        return .run { send in
            do {
                try await operation(projectRootURL, change)
                await send(.gitActionFinished(change.id))
                await send(.gitRefreshRequested)
            } catch {
                await send(.gitActionFailed(change.id, error.localizedDescription))
            }
        }
        .cancellable(
            id: GitEffectID.fileAction(projectRootURL.path, change.id),
            cancelInFlight: true
        )
    }

    private static func discardAlertRequest(for change: GitFileChange) -> AlertRequest {
        AlertRequest(
            title: change.status == .untracked
                ? "Move \(change.filename) to Trash?"
                : "Discard changes to \(change.filename)?",
            message: change.status == .untracked
                ? "The untracked file will be moved to Trash."
                : "The current working copy will be moved to Trash when a file exists, then git will restore the selected changes.",
            confirmTitle: "Discard Changes",
            cancelTitle: "Cancel"
        )
    }

    private enum GitEffectID: Hashable {
        case status(String)
        case fileAction(String, String)
    }
}
