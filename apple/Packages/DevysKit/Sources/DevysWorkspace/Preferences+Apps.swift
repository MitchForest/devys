import AuthenticationServices
import ComposableArchitecture2
import Dependencies
package import DevysClient
import DevysDesignSystem
import SwiftUI

// MARK: - Apps and connections: the directory for the selected business

package enum AppIntent {
    case requested
    case loaded(businessID: String, Loadable<[AppEntry]>)
    /// Removes a connected app.
    case installToggled(appID: String, Bool)
    case googleLoaded(businessID: String, Loadable<GoogleConnection>)
}

extension Preferences {
    func reduceApps(_ intent: AppIntent, state: inout State) {
        guard let businessID = state.selectedBusinessID ?? state.businesses.first?.id else { return }
        switch intent {
        case .requested:
            loadApps(businessID)
            loadGoogle(businessID)
        case .loaded(let id, let apps):
            guard id == businessID else { return }
            state.apps = apps
        case .installToggled(let appID, let install):
            changeApps(businessID, failure: install ? "That app couldn't be installed." : "That app couldn't be removed.") { runtime in
                try await runtime.installApp(businessID, appID, install)
            }
        case .googleLoaded(let id, let google):
            guard id == businessID else { return }
            state.google = google
        }
    }

    private func loadApps(_ businessID: String) {
        let runtime = runtime
        store.addTask { try await loadApps(runtime, businessID) }
    }

    private func loadApps(_ runtime: RuntimeClient, _ businessID: String) async throws {
        do {
            try store.send(Action(.app(.loaded(businessID: businessID, .loaded(try await runtime.apps(businessID))))))
        } catch {
            try store.send(Action(.app(.loaded(businessID: businessID, .failed("The app directory couldn't be loaded.")))))
        }
    }

    /// Google Drive is the one real connection today.
    private func loadGoogle(_ businessID: String) {
        let runtime = runtime
        store.addTask {
            do {
                try store.send(Action(.app(.googleLoaded(businessID: businessID, .loaded(try await runtime.googleConnection(businessID))))))
            } catch let error as DevysHTTPError {
                try store.send(Action(.app(.googleLoaded(businessID: businessID, .failed(Workspace.message(for: error))))))
            }
        }
    }

    private func changeApps(_ businessID: String, failure: String, change: @escaping @Sendable (RuntimeClient) async throws -> Void) {
        let runtime = runtime
        store.addTask {
            do {
                try await change(runtime)
            } catch {
                try store.send(Action(.failed(failure)))
            }
            try await loadApps(runtime, businessID)
        }
    }
}

/// Settings → Apps: the business's connected apps (outside services, added from Connect apps), each
/// with what to do next, and the Google Drive connection. Documents, Code and the rest are what
/// employees do, never apps here.
struct AppsPane: View {
    let store: StoreOf<Preferences>

    var body: some View {
        let businessID = store.selectedBusinessID ?? store.businesses.first?.id
        PaneScroll {
            VStack(alignment: .leading, spacing: DevysSpacing.roomy) {
                if store.businesses.count > 1 {
                    Picker("Business", selection: Binding(get: { businessID ?? "" }, set: { store.send(.businessSelected($0)) })) {
                        ForEach(store.businesses) { Text($0.name).tag($0.id) }
                    }
                    .fixedSize()
                }
                if let error = store.errorText {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                }
                directory
                connections
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DevysSpacing.roomy)
        }
        .task(id: businessID) { if businessID != nil { store.send(.appsRequested) } }
    }

    @ViewBuilder private var directory: some View {
        switch store.apps {
        case .loading:
            ProgressView()
        case .failed(let message):
            EmptyNote(text: message)
        case .loaded(let apps):
            let connected = apps.filter { $0.state != nil }
            if connected.isEmpty {
                EmptyNote(text: "No apps connected yet. Connect apps from the bottom of the sidebar.")
            } else if let businessID = store.selectedBusinessID ?? store.businesses.first?.id {
                VStack(alignment: .leading, spacing: DevysSpacing.small) {
                    SectionHeader("Connected apps")
                    ForEach(connected) { app in
                        ConnectedAppRow(businessID: businessID, app: app, store: store)
                    }
                }
            }
        }
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            SectionHeader("Connections")
            HStack(spacing: DevysSpacing.compact) {
                Image(systemName: "externaldrive.connected.to.line.below").frame(width: 28).foregroundStyle(DevysColors.ink2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Google Drive").font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                    Text("Files your employees read and write").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                }
                Spacer()
                googleState
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var googleState: some View {
        switch store.google {
        case nil, .loading: ProgressView().controlSize(.small)
        case .failed(let message): Text(message).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
        case .loaded(let google) where google.connected: StatusChip("Connected", tone: .done)
        case .loaded(let google) where google.configured:
            // Google's consent flow runs in the browser; this app doesn't start it.
            Text("Not connected · connect it in Devys on the web")
                .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).multilineTextAlignment(.trailing)
        case .loaded: Text("Not set up on this server").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
        }
    }
}

/// A connected (or connecting) remote app: its logo, where it stands, and what to do next; its
/// review opens here.
private struct ConnectedAppRow: View {
    let businessID: String
    let app: AppEntry
    let store: StoreOf<Preferences>
    @State private var reviewing = false

    var body: some View {
        HStack(spacing: DevysSpacing.compact) {
            AppLogo(path: app.logo, name: app.name, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                Text(stateText).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
            }
            Spacer(minLength: 8)
            if app.state == .connecting || app.state == .lapsed {
                ConnectButton(businessID: businessID, appID: app.id, title: app.state == .lapsed ? "Reconnect" : "Connect") {
                    store.send(.appsRequested)
                }
            } else {
                Button(app.state == .review ? "Review" : "Change") { reviewing = true }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
            }
            Button("Remove") { store.send(.appInstallToggled(app.id, false)) }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $reviewing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        AppLogo(path: app.logo, name: app.name, size: 40)
                        Text(app.name).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                        Spacer()
                        Button("Done") { reviewing = false }.buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    }
                    AppReviewCard(businessID: businessID, app: app) {
                        reviewing = false
                        store.send(.appsRequested)
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 420, minHeight: 420)
        }
    }

    private var stateText: String {
        switch app.state {
        case .turnedOn: "On"
        case .review: "Connected · waiting for you to turn it on"
        case .lapsed: "Its sign-in stopped working"
        default: "Not connected yet"
        }
    }
}
