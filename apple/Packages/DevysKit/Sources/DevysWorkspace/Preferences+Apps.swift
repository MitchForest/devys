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

/// Settings → Apps: the business's functions from the directory (Devys apps first), installed, pinned to the sidebar or removed, the system apps every business has, and
/// the connections they use. Installing grants nothing by itself.
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
            let available = apps.filter { $0.kind == .business && $0.state == nil }
            let system = apps.filter { $0.kind == .system }
            let connected = apps.filter { $0.state != nil }
            if let businessID = store.selectedBusinessID ?? store.businesses.first?.id {
                AddAppSection(businessID: businessID) { store.send(.appsRequested) }
                if !connected.isEmpty {
                    VStack(alignment: .leading, spacing: DevysSpacing.small) {
                        SectionHeader("Connected apps")
                        ForEach(connected) { app in
                            ConnectedAppRow(businessID: businessID, app: app, store: store)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Devys apps")
                ForEach(available) { AppRow(store: store, app: $0) }
            }
            // Always installed and never in the sidebar: nothing to install, remove or pin.
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Built in")
                ForEach(system) { app in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).font(DevysTypography.body).foregroundStyle(DevysColors.ink)
                        Text(app.summary).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                        AppSkills(app: app)
                    }
                    .padding(.vertical, 4)
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

/// The skills an app ships, by name: what employees can load from it.
private struct AppSkills: View {
    let app: AppEntry

    var body: some View {
        if !app.skills.isEmpty {
            Text("Skills: \(app.skills.map(\.name).joined(separator: ", "))")
                .font(DevysTypography.caption)
                .foregroundStyle(DevysColors.ink3)
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
            AppSkills(app: app)
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
        if app.installed {
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

/// Add app: search by name or what it does (the business's apps and the MCP Registry), or paste an
/// app's address; adding one connects it with its own sign-in.
private struct AddAppSection: View {
    let businessID: String
    let reload: () -> Void
    @Dependency(\.runtimeClient) private var runtime
    @Environment(\.webAuthenticationSession) private var session
    @State private var query = ""
    @State private var found: [FoundApp] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            SectionHeader("Add app")
            TextField("Search apps, or paste an app's address", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Add app")
            if let error {
                Text(error).font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
            }
            if searching, found.isEmpty {
                ProgressView().controlSize(.small)
            } else if query.trimmingCharacters(in: .whitespaces).count > 1, found.isEmpty {
                Text("No apps found.").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
            }
            ForEach(found) { app in
                HStack(spacing: DevysSpacing.compact) {
                    AppLogo(path: app.logo, name: app.name, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                        if !app.description.isEmpty {
                            Text(app.description).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if app.installed {
                        Text("Added").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                    } else {
                        Button("Add") { add(app.app) }
                            .buttonStyle(DevysButtonStyle(.raised, compact: true))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .task(id: query) { await search() }
    }

    private func search() async {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard typed.count > 1 else { found = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searching = true
        found = (try? await runtime.searchApps(businessID, typed)) ?? []
        searching = false
    }

    private func add(_ app: String) {
        error = nil
        Task {
            do {
                let added = try await runtime.addApp(businessID, app)
                query = ""
                if added.state == .connecting || added.state == .lapsed {
                    let connecting = try await runtime.connectApp(businessID, added.id)
                    if let url = connecting.url {
                        _ = try await session.authenticate(using: url, callback: .customScheme("devys"), additionalHeaderFields: [:])
                    }
                }
            } catch DevysHTTPError.rejected(_, let message) where !message.isEmpty {
                error = message
            } catch {
                // Cancelled sign-ins leave the app added; Connect is on its row.
            }
            reload()
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
