import ComposableArchitecture
import Foundation

@Reducer
struct TerminalTabFeature {
    @ObservableState
    struct State: Equatable {
        var projectRootURL: URL?
        var workingDirectoryURL: URL?
        var pendingProjectRootCandidateURL: URL?
        var dismissedProjectRootCandidatePaths: Set<String> = []
        var closeRisk: TerminalTabCloseRisk?
        var composerPresentation: TerminalComposerPresentationPolicy = .transientBottomDrawer
        var isComposerPresented = false
        var composerIntent: TerminalComposerIntent?

        init(projectRootURL: URL? = nil) {
            let standardizedProjectRootURL = projectRootURL?.standardizedFileURL
            self.projectRootURL = standardizedProjectRootURL
            self.workingDirectoryURL = standardizedProjectRootURL
        }
    }

    enum Action: Equatable {
        case projectRootChanged(URL?)
        case workingDirectoryChanged(URL)
        case pendingProjectRootCandidateChanged(URL?)
        case dismissProjectRootCandidate(URL)
        case closeRiskChanged(TerminalTabCloseRisk?)
        case composerPresentationChanged(Bool)
        case focusComposerRequested
        case pasteIntoComposerRequested
        case captureSelectionIntoComposerRequested
        case composerIntentHandled
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .projectRootChanged(url):
                let standardizedURL = url?.standardizedFileURL
                state.projectRootURL = standardizedURL
                state.pendingProjectRootCandidateURL = nil
                if state.workingDirectoryURL == nil {
                    state.workingDirectoryURL = standardizedURL
                }
                return .none

            case let .workingDirectoryChanged(url):
                state.workingDirectoryURL = url.standardizedFileURL
                return .none

            case let .pendingProjectRootCandidateChanged(url):
                let standardizedURL = url?.standardizedFileURL
                guard let standardizedURL else {
                    state.pendingProjectRootCandidateURL = nil
                    return .none
                }
                guard !state.dismissedProjectRootCandidatePaths.contains(standardizedURL.path) else {
                    return .none
                }
                state.pendingProjectRootCandidateURL = standardizedURL
                return .none

            case let .dismissProjectRootCandidate(url):
                let standardizedURL = url.standardizedFileURL
                state.dismissedProjectRootCandidatePaths.insert(standardizedURL.path)
                if state.pendingProjectRootCandidateURL == standardizedURL {
                    state.pendingProjectRootCandidateURL = nil
                }
                return .none

            case let .closeRiskChanged(closeRisk):
                state.closeRisk = closeRisk
                return .none

            case let .composerPresentationChanged(isPresented):
                state.isComposerPresented = isPresented
                return .none

            case .focusComposerRequested:
                state.isComposerPresented = true
                state.composerIntent = .focus
                return .none

            case .pasteIntoComposerRequested:
                state.isComposerPresented = true
                state.composerIntent = .paste
                return .none

            case .captureSelectionIntoComposerRequested:
                state.isComposerPresented = true
                state.composerIntent = .captureSelection
                return .none

            case .composerIntentHandled:
                state.composerIntent = nil
                return .none
            }
        }
    }
}

enum TerminalComposerPresentationPolicy: Equatable, Sendable {
    case transientBottomDrawer
    case pinnedBottomDrawer
}

enum TerminalComposerIntent: Equatable, Sendable {
    case focus
    case paste
    case captureSelection
}

struct TerminalTabCloseRisk: Equatable, Sendable {
    var displayName: String
    var detail: String

    init(displayName: String, detail: String) {
        self.displayName = displayName
        self.detail = detail
    }
}
