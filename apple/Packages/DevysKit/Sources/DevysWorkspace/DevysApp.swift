public import ComposableArchitecture2
import Dependencies
package import DevysClient
package import Foundation

/// Root route. The session phase stream owns it: signing in or out changes the session, and the
/// route follows. A `devys://connect` link (the QR code in Settings › Devices) shows its Mac on
/// the sign-in screen's one button; a signed-in device has nothing to connect.
@Feature
public struct DevysApp {
    public init() {}

    public struct State {
        package var route: Route = .launching
        package var signIn: Spawn<SignIn>?
        package var workspace: Spawn<Workspace>?
        /// A Mac from a link opened before the sign-in screen existed.
        package var linkedMac: FoundMac?

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
    }

    @Dependency(\.sessionClient) var sessionClient: SessionClient

    public var body: some Feature {
        Update { state, action in
            switch action.intent {
            case .phaseChanged(.signedOut):
                state.route = .signedOut
                state.workspace = nil
                if state.signIn == nil {
                    var signIn = SignIn.State()
                    if let mac = state.linkedMac { signIn.phase = .found(mac) }
                    state.signIn = Spawn(signIn)
                }

            case .phaseChanged(.signedIn(let server)):
                state.route = .signedIn
                state.signIn = nil
                state.linkedMac = nil
                if state.workspace == nil { state.workspace = Spawn(Workspace.State(server: server)) }

            case .linkOpened(let url):
                guard state.route != .signedIn, let link = ConnectLink(url: url) else { return }
                state.linkedMac = link.mac
                // Asking already: the link changes nothing until that is answered.
                switch state.signIn?.phase {
                case .looking, .found: state.signIn?.phase = .found(link.mac)
                default: break
                }
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

extension DevysApp.Action {
    package static func linkOpened(_ url: URL) -> Self { Self(.linkOpened(url)) }
}
