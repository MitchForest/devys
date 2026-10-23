import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The Face, one button, at most one short line. Nothing to read, nothing to type.
struct SignInScreen: View {
    let store: StoreOf<SignIn>

    var body: some View {
        VStack(spacing: 28) {
            DevysAvatar(
                AvatarSpec(palette: .blue, shape: .roundedSquare, seed: 7),
                size: 88,
                mood: mood,
                label: "Devys"
            )
            content
        }
        .frame(maxWidth: 320)
        .padding(DevysSpacing.roomy)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DevysColors.frame)
        .animation(DevysMotion.arrive, value: store.phase)
        .task { store.send(.appeared) }
        #if DEBUG
            // QA: `DEVYS_CONNECT=1` taps Connect once a Mac is found, for screenshots.
            .task(id: store.mac?.server) {
                if ProcessInfo.processInfo.environment["DEVYS_CONNECT"] == "1", case .found = store.phase {
                    store.send(.connectTapped)
                }
            }
        #endif
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .looking:
            line("Looking for your Mac…")
        case .found(let mac), .connecting(let mac):
            Button {
                store.send(.connectTapped)
            } label: {
                Text("Connect to \(mac.name)")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.aurora)
            .disabled(store.phase == .connecting(mac))
            .keyboardShortcut(.defaultAction)
            line(store.errorText)
        case .waiting(let ticket):
            Text(ticket.match.joined(separator: " "))
                .font(.system(size: 44))
                .accessibilityLabel("Match \(ticket.match.joined(separator: " "))")
            line("Allow on \(ticket.mac.name)")
        }
    }

    private var mood: BotMood {
        switch store.phase {
        case .looking, .connecting: .thinking
        case .waiting: .waiting
        case .found: store.errorText == nil ? .idle : .oops
        }
    }

    /// One short line; kept in place when empty so the button doesn't move.
    private func line(_ text: String?) -> some View {
        Text(text ?? " ")
            .font(DevysTypography.body)
            .foregroundStyle(DevysColors.ink3)
            .multilineTextAlignment(.center)
            .accessibilityHidden(text == nil)
    }
}
