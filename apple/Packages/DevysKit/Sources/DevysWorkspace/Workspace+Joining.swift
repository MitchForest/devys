import ComposableArchitecture2
import Dependencies
package import DevysClient
import Foundation

/// A device asking to join, asked about on every signed-in device as the system would ask: its
/// name and the two emoji its own screen shows. Allow signs it in as you; from a device that
/// approves spending, Face ID or Touch ID then lets its key approve spending too.
package enum JoinIntent {
    case loaded([JoinRequest])
    case answered(id: String, allow: Bool)
    case finished
}

extension Workspace {
    static let joinsInterval: Duration = .seconds(2)

    func reduceJoin(_ intent: JoinIntent, state: inout State) {
        switch intent {
        case .loaded(let requests):
            // The same request polled again stays as it is, so the alert isn't shown twice.
            guard !state.isAnsweringJoin, state.joinRequest?.id != requests.first?.id else { return }
            state.joinRequest = requests.first
        case .answered(let id, let allow):
            guard state.joinRequest?.id == id, !state.isAnsweringJoin else { return }
            state.isAnsweringJoin = true
            state.joinRequest = nil
            let runtime = runtime
            let signing = signing
            let person = state.account?.person.id
            store.addTask {
                do {
                    let key = try await runtime.answerJoin(id, allow)
                    if let key, key.status == .pending, let person {
                        // Cancelled or unable to sign, it simply waits to be allowed in Devices.
                        try? await signing.allow(key, person)
                    }
                } catch {
                    // Answered elsewhere already, or expired: nothing to say.
                }
                try store.send(Action(.join(.finished)))
            }
        case .finished:
            state.isAnsweringJoin = false
        }
    }

    /// Asks who wants to join, every two seconds while the app is in front.
    func watchJoins() {
        let runtime = runtime
        let clock = clock
        store.addTask {
            while !Task.isCancelled {
                if let requests = try? await runtime.joins() { try store.send(Action(.join(.loaded(requests)))) }
                try await clock.sleep(for: Self.joinsInterval)
            }
        }
    }
}

extension Workspace.Action {
    package static func joinAnswered(_ id: String, allow: Bool) -> Self { Self(.join(.answered(id: id, allow: allow))) }
}
