import ComposableArchitecture

extension WindowFeature {
    func reduceRepositoryImportRequestAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestAddRepository:
            state.addRepositoryPresentation = AddRepositoryPresentation(id: uuid())
            return .none

        case .setAddRepositoryPresentation(let presentation):
            state.addRepositoryPresentation = presentation
            return .none

        case .requestOpenRepository:
            state.openRepositoryRequestID = uuid()
            return .none

        case .setOpenRepositoryRequestID(let requestID):
            state.openRepositoryRequestID = requestID
            return .none

        default:
            return .none
        }
    }
}
