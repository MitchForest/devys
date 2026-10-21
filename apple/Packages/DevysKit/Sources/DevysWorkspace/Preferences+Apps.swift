import ComposableArchitecture2
import Dependencies
package import DevysClient
import DevysDesignSystem
import SwiftUI

// MARK: - Apps and connections: the directory for the selected business

package enum AppIntent {
    case requested
    case loaded(businessID: String, Loadable<[AppEntry]>)
    case installToggled(appID: String, Bool)
    /// A pinned app shows in the sidebar once it has something.
    case pinToggled(appID: String, Bool)
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
        case .pinToggled(let appID, let pinned):
            if var apps = state.apps.value, let index = apps.firstIndex(where: { $0.id == appID }) {
                apps[index].pinned = pinned
                state.apps = .loaded(apps)
            }
            changeApps(businessID, failure: "That app couldn't be pinned.") { runtime in
                try await runtime.pinApp(businessID, appID, pinned)
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

/// Settings → Apps: the business's functions from the directory (Devys apps first; others are
/// coming), installed, pinned to the sidebar or removed, and the connections they use.
/// Installing grants nothing by itself.
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
            let available = apps.filter { $0.status == .available }
            let coming = apps.filter { $0.status == .coming }
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Devys apps")
                ForEach(available) { AppRow(store: store, app: $0) }
            }
            if !coming.isEmpty {
                VStack(alignment: .leading, spacing: DevysSpacing.small) {
                    SectionHeader("Coming")
                    ForEach(coming) { app in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
                            Text(app.summary).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                        }
                        .padding(.vertical, 4)
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

/// One app: what it is, whether the sidebar shows it, and install or remove. Documents is
/// always installed.
private struct AppRow: View {
    let store: StoreOf<Preferences>
    let app: AppEntry

    var body: some View {
        // Beside the words when the row has room, under them on a phone.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DevysSpacing.compact) {
                words
                Spacer(minLength: 8)
                controls
            }
            VStack(alignment: .leading, spacing: 6) {
                words
                HStack(spacing: DevysSpacing.compact) { controls }
            }
        }
        .padding(.vertical, 6)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(app.name).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
            Text(app.summary).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
        }
    }

    @ViewBuilder private var controls: some View {
        if app.installed {
            HStack(spacing: 6) {
                Toggle("Sidebar", isOn: Binding(get: { app.pinned }, set: { store.send(.appPinToggled(app.id, $0)) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text("Sidebar").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
            }
            .fixedSize()
            .help("Shows in the sidebar once it has something")
        }
        if app.id == "documents" {
            Text("Always installed").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).fixedSize()
        } else if app.installed {
            Button("Remove") { store.send(.appInstallToggled(app.id, false)) }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                .fixedSize()
        } else {
            Button("Install") { store.send(.appInstallToggled(app.id, true)) }
                .buttonStyle(DevysButtonStyle(.raised, compact: true))
                .fixedSize()
        }
    }
}
