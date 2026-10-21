package import ComposableArchitecture2
import Dependencies
import DevysClient
package import Foundation

/// Device enrollment: a server address and a one-time code from another signed-in device
/// (Settings › Devices). Success routes at the root through the session phase stream.
@Feature
package struct SignIn {
    package init() {}

    package struct State {
        #if DEBUG
            /// The local development server.
            package var server = "http://127.0.0.1:5173"
        #else
            package var server = ""
        #endif
        package var code = ""
        package var isSubmitting = false
        package var errorText: String?

        package init() {}

        package var serverURL: URL? {
            guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)),
                  let scheme = url.scheme, ["http", "https"].contains(scheme), url.host() != nil
            else { return nil }
            return url
        }

        package var normalizedCode: String {
            code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        package var canSubmit: Bool {
            serverURL != nil && normalizedCode.wholeMatch(of: /[a-f0-9]{64}/) != nil && !isSubmitting
        }
    }

    package struct Action {
        package let intent: Intent

        package init(_ intent: Intent) {
            self.intent = intent
        }
    }

    package enum Intent {
        case serverChanged(String)
        case codeChanged(String)
        case submitTapped
        case failed(String)
    }

    @Dependency(\.sessionClient) private var sessionClient: SessionClient

    package var body: some Feature {
        Update { state, action in
            switch action.intent {
            case .serverChanged(let server):
                state.server = server
                state.errorText = nil

            case .codeChanged(let code):
                state.code = code
                state.errorText = nil

            case .submitTapped:
                guard state.canSubmit, let server = state.serverURL else { return }
                state.isSubmitting = true
                state.errorText = nil
                let session = sessionClient
                let code = state.normalizedCode
                store.addTask {
                    do {
                        try await session.signIn(server, code)
                    } catch {
                        try store.send(Action(.failed(Self.message(for: error))))
                    }
                }

            case .failed(let message):
                state.isSubmitting = false
                state.errorText = message
            }
        }
    }

    static func message(for error: any Error) -> String {
        switch error as? DevysHTTPError {
        case .rejected(401, _), .unauthorized:
            "That code has expired or was already used. Add a device in Settings › Devices on another signed-in device for a new one."
        case .rejected(400, _):
            "That doesn't look like an enrollment code."
        case .unreachable:
            "Couldn't reach the server. Check the address and that Devys is running."
        default:
            "Sign-in failed. Try again."
        }
    }
}

extension SignIn.Action {
    package static func serverChanged(_ value: String) -> Self { Self(.serverChanged(value)) }
    package static func codeChanged(_ value: String) -> Self { Self(.codeChanged(value)) }
    package static var submitTapped: Self { Self(.submitTapped) }
}
