package import ComposableArchitecture2
import Dependencies
package import DevysClient
import Foundation

/// Signing in with nothing to type (.docs/AUTHORITY.md "Signing in"). On the Mac running Devys
/// the app signs itself in as the Mac's owner and this screen never shows. Elsewhere it finds the
/// Mac (the local network, the last one used, or the QR code's link) and shows one button,
/// "Connect to <Mac>"; tapping it asks to join, and a signed-in device allows it. Success routes
/// at the root through the session phase stream.
@Feature
package struct SignIn {
    package init() {}

    package enum Phase: Equatable {
        /// Nothing found yet: "Looking for your Mac…".
        case looking
        case found(FoundMac)
        /// Asking the Mac; the button waits.
        case connecting(FoundMac)
        /// Asked: the two emoji the Mac shows too, until someone allows or denies it.
        case waiting(JoinTicket)
    }

    package struct State {
        package var phase = Phase.looking
        package var errorText: String?

        package init() {}

        /// The Mac the one button connects to.
        package var mac: FoundMac? {
            switch phase {
            case .looking: nil
            case .found(let mac), .connecting(let mac): mac
            case .waiting(let ticket): ticket.mac
            }
        }
    }

    package struct Action {
        package let intent: Intent

        package init(_ intent: Intent) {
            self.intent = intent
        }
    }

    package enum Intent {
        case appeared
        /// A Mac found on the local network, remembered, or opened from the QR code's link.
        case found(FoundMac)
        case connectTapped
        case asked(JoinTicket)
        case answered(JoinOutcome)
        case failed
    }

    static let retry: Duration = .seconds(2)

    @Dependency(\.sessionClient) private var sessionClient: SessionClient
    @Dependency(\.discoveryClient) private var discovery: DiscoveryClient
    @Dependency(\.continuousClock) private var clock: any Clock<Duration>

    package var body: some Feature {
        Update { state, action in
            switch action.intent {
            case .appeared:
                let session = sessionClient
                let discovery = discovery
                let clock = clock
                store.addTask {
                    // The Mac running Devys signs in as its owner; until its server answers, keep looking.
                    while true {
                        do {
                            if try await session.signInAsOwner() { return }
                            break
                        } catch {
                            try await clock.sleep(for: Self.retry)
                        }
                    }
                    if let last = discovery.lastKnown() { try store.send(Action(.found(last))) }
                    for await mac in discovery.macs() {
                        try store.send(Action(.found(mac)))
                    }
                }

            case .found(let mac):
                // A Mac turning up while asking changes nothing.
                switch state.phase {
                case .looking, .found: state.phase = .found(mac)
                case .connecting, .waiting: return
                }

            case .connectTapped:
                guard case .found(let mac) = state.phase else { return }
                state.phase = .connecting(mac)
                state.errorText = nil
                let session = sessionClient
                let discovery = discovery
                store.addTask {
                    do {
                        let ticket = try await session.requestJoin(mac)
                        try store.send(Action(.asked(ticket)))
                        let outcome = try await session.awaitJoin(ticket)
                        if outcome == .allowed { discovery.remember(mac) }
                        try store.send(Action(.answered(outcome)))
                    } catch is CancellationError {
                        return
                    } catch {
                        try store.send(Action(.failed))
                    }
                }

            case .asked(let ticket):
                state.phase = .waiting(ticket)

            case .answered(let outcome):
                // Allowed: the session changes and the root routes on. Denied or expired: back to
                // the button, with nothing to read.
                guard outcome != .allowed, let mac = state.mac else { return }
                state.phase = .found(mac)

            case .failed:
                guard let mac = state.mac else { return }
                state.phase = .found(mac)
                state.errorText = "Couldn't reach your Mac. Try again."
            }
        }
    }
}

extension SignIn.Action {
    package static var appeared: Self { Self(.appeared) }
    package static var connectTapped: Self { Self(.connectTapped) }
    package static func found(_ mac: FoundMac) -> Self { Self(.found(mac)) }
}
