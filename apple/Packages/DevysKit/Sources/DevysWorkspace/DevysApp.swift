public import ComposableArchitecture2
import Dependencies
package import DevysClient
package import Foundation

/// Root route. The session phase stream owns it: signing in or out changes the
/// session, and the route follows. A `devys://enroll` link signs this device in,
/// replacing the current session only after the owner confirms.
@Feature
public struct DevysApp {
    public init() {}

    public struct State {
        package var route: Route = .launching
        package var signIn: Spawn<SignIn>?
        package var workspace: Spawn<Workspace>?
        /// A sign-in link opened while signed in, waiting for the owner to confirm the switch.
        package var pendingLink: EnrollLink?
        package var isEnrolling = false
        package var linkError: String?

        public init() {}
    }

    package enum Route: Equatable {
        case launching
        case signedOut
        case signedIn
    }

    public struct Action {
        package let intent: Intent

        package init(_ intent: Intent) {
            self.intent = intent
        }
    }

    package enum Intent {
        case phaseChanged(SessionPhase)
        case linkOpened(URL)
        case linkConfirmed
        case linkCancelled
        case linkFinished(server: URL, replaced: Bool)
        case linkFailed(String)
        case linkErrorDismissed
    }

    /// Declared here (not by the macro) so effect helpers can live in an extension.
    @FeatureBindable var store = FeatureStore<Self.State, Self.Action>()

    @Dependency(\.sessionClient) var sessionClient: SessionClient

    public var body: some Feature {
        Update { state, action in
            switch action.intent {
            case .phaseChanged(.signedOut):
                state.route = .signedOut
                state.workspace = nil
                if state.signIn == nil { state.signIn = Spawn(SignIn.State()) }

            case .phaseChanged(.signedIn(let server)):
                state.route = .signedIn
                state.signIn = nil
                if state.workspace == nil { state.workspace = Spawn(Workspace.State(server: server)) }

            case .linkOpened(let url):
                guard let link = EnrollLink(url: url) else {
                    state.linkError = "That isn't a Devys sign-in link."
                    return
                }
                if state.route == .signedIn {
                    state.pendingLink = link
                } else {
                    enroll(link, replacing: false, state: &state)
                }

            case .linkConfirmed:
                guard let link = state.pendingLink else { return }
                state.pendingLink = nil
                enroll(link, replacing: true, state: &state)

            case .linkCancelled:
                state.pendingLink = nil

            case .linkFinished(let server, let replaced):
                state.isEnrolling = false
                // A new session means a new person or server: start the workspace fresh.
                if replaced { state.workspace = Spawn(Workspace.State(server: server)) }

            case .linkFailed(let message):
                state.isEnrolling = false
                state.linkError = message

            case .linkErrorDismissed:
                state.linkError = nil
            }
        }
        .ifLet(\.signIn) {
            SignIn()
        }
        .ifLet(\.workspace) {
            Workspace()
        }
        .onMount { _ in
            let session = sessionClient
            store.addTask {
                for await phase in session.phases() {
                    try store.send(Action(.phaseChanged(phase)))
                }
            }
        }
    }
}

extension DevysApp {
    /// Signs in with the link's server and code; the device name labels this device.
    func enroll(_ link: EnrollLink, replacing: Bool, state: inout State) {
        guard !state.isEnrolling else { return }
        state.isEnrolling = true
        state.linkError = nil
        let session = sessionClient
        store.addTask {
            do {
                try await session.signIn(link.server, link.code)
                try store.send(Action(.linkFinished(server: link.server, replaced: replacing)))
            } catch {
                try store.send(Action(.linkFailed(SignIn.message(for: error))))
            }
        }
    }
}

extension DevysApp.Action {
    package static func linkOpened(_ url: URL) -> Self { Self(.linkOpened(url)) }
    package static var linkConfirmed: Self { Self(.linkConfirmed) }
    package static var linkCancelled: Self { Self(.linkCancelled) }
    package static var linkErrorDismissed: Self { Self(.linkErrorDismissed) }
}
