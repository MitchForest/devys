import SwiftUI

/// The one poller for live layers and lines (coding sessions, the browser, terminals): it reads
/// at once, then every `interval` while the view shows and the app is active, and stops while the
/// app is in the background. A 401 from any read signs the device out in the session hub.
private struct Poll<ID: Equatable>: ViewModifier {
    let id: ID
    let interval: Duration?
    let read: () async -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: Key(id: id, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            repeat {
                await read()
                guard let interval else { return }
                try? await Task.sleep(for: interval)
            } while !Task.isCancelled
        }
    }

    private struct Key: Equatable {
        let id: ID
        let active: Bool
    }
}

extension View {
    /// Reads now and every `interval` (once, when nil) while shown and active; a new `id` restarts it.
    func poll(id: some Equatable, every interval: Duration?, _ read: @escaping () async -> Void) -> some View {
        modifier(Poll(id: id, interval: interval, read: read))
    }
}
