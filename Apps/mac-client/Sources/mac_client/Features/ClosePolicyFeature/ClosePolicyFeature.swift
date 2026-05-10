import ComposableArchitecture
import Foundation

@Reducer
struct ClosePolicyFeature {
    @ObservableState
    struct State: Equatable {
        var subjects: [CloseSubject.ID: CloseSubject] = [:]
        var decisions: [CloseSubject.ID: CloseDecision] = [:]
    }

    enum Action: Equatable {
        case register(CloseSubject)
        case requestClose(CloseSubject.ID)
        case closeAlertResponse(CloseSubject.ID, AlertResponse)
    }

    @Dependency(\.alertClient) private var alertClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .register(subject):
                state.subjects[subject.id] = subject
                state.decisions[subject.id] = nil
                return .none

            case let .requestClose(id):
                guard let subject = state.subjects[id] else {
                    state.decisions[id] = .deny
                    return .none
                }

                switch subject.kind {
                case .plain:
                    state.decisions[id] = .allow
                    return .none

                case .dirtyDocument:
                    return .run { send in
                        guard let request = subject.alertRequest else {
                            await send(.closeAlertResponse(id, .cancel))
                            return
                        }
                        let response = await alertClient.choose(
                            request
                        )
                        await send(.closeAlertResponse(id, response))
                    }

                case .terminalCloseRisk:
                    return .run { send in
                        guard let request = subject.alertRequest else {
                            await send(.closeAlertResponse(id, .cancel))
                            return
                        }
                        let confirmed = await alertClient.confirm(
                            request
                        )
                        await send(.closeAlertResponse(id, confirmed ? .confirm : .cancel))
                    }
                }

            case let .closeAlertResponse(id, response):
                guard let subject = state.subjects[id] else {
                    state.decisions[id] = .deny
                    return .none
                }

                switch (subject.kind, response) {
                case (.plain, _):
                    state.decisions[id] = .allow
                case (.dirtyDocument, .confirm):
                    state.decisions[id] = .saveThenClose
                case (.dirtyDocument, .secondary):
                    state.decisions[id] = .discardThenClose
                case (.dirtyDocument, .cancel):
                    state.decisions[id] = .deny
                case (.terminalCloseRisk, .confirm):
                    state.decisions[id] = .allow
                case (.terminalCloseRisk, .secondary), (.terminalCloseRisk, .cancel):
                    state.decisions[id] = .deny
                }
                return .none
            }
        }
    }
}

struct CloseSubject: Equatable, Identifiable, Sendable {
    let id: UUID
    var kind: Kind

    enum Kind: Equatable, Sendable {
        case plain
        case dirtyDocument(displayName: String)
        case terminalCloseRisk(displayName: String, detail: String)
    }

    var alertRequest: AlertRequest? {
        switch kind {
        case .plain:
            return nil

        case .dirtyDocument(let displayName):
            return AlertRequest(
                title: "Save changes to \(displayName)?",
                message: "Your changes will be lost if you close this tab without saving.",
                confirmTitle: "Save",
                cancelTitle: "Cancel",
                secondaryTitle: "Don't Save"
            )

        case .terminalCloseRisk(let displayName, let detail):
            return AlertRequest(
                title: "Close terminal running \(displayName)?",
                message: detail,
                confirmTitle: "Close Terminal"
            )
        }
    }
}

enum CloseDecision: Equatable, Sendable {
    case allow
    case deny
    case discardThenClose
    case saveThenClose
}
