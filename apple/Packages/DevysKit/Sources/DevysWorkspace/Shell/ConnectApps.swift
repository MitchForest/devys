import AuthenticationServices
import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

/// Connect apps: outside services the business connects (Ramp, Stripe, Notion…). Search across
/// them and the MCP Registry, filter by category, Add one with its own sign-in; "N connected" lists
/// the ones the business has. Documents, Code and the browser are what employees do, never apps.
struct ConnectAppsSheet: View {
    let store: StoreOf<Workspace>
    @Dependency(\.runtimeClient) private var runtime
    @Environment(\.webAuthenticationSession) private var session
    @State private var query = ""
    @State private var category: String?
    @State private var showsConnected = false
    @State private var found: [FoundApp] = []
    @State private var searching = false
    @State private var adding: String?
    @State private var error: String?

    private var connected: [AppEntry] { (store.apps.value ?? []).filter { $0.state != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !showsConnected {
                searchField.padding(.horizontal, 20).padding(.bottom, 10)
                if query.trimmingCharacters(in: .whitespaces).isEmpty { chips }
            }
            Rectangle().fill(DevysColors.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                    }
                    if showsConnected {
                        connectedList
                    } else if query.trimmingCharacters(in: .whitespaces).count > 1 {
                        results
                    } else {
                        listed
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .sheetFrame(width: 720, height: 600)
        .background(DevysColors.sheet)
        .task(id: query) { await search() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if showsConnected {
                Button("All apps", systemImage: "chevron.left") { showsConnected = false }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(DevysColors.ink2)
            }
            Text(showsConnected ? "Connected" : "Connect Apps").font(DevysTypography.title).foregroundStyle(DevysColors.ink)
            Spacer()
            if !showsConnected, !connected.isEmpty {
                Button { showsConnected = true } label: {
                    HStack(spacing: 3) {
                        Text("\(connected.count) connected")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(DevysTypography.control)
                    .foregroundStyle(DevysColors.ink2)
                }
                .buttonStyle(.plain)
            }
            ToolbarIconButton("Close", symbol: "xmark") { store.send(.connectAppsToggled(false)) }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
            TextField("Search across apps and skills", text: $query)
                .textFieldStyle(.plain)
                .font(DevysTypography.body)
            if searching { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var categories: [String] {
        var seen: [String] = []
        for app in store.listedApps.value ?? [] where !seen.contains(app.category) { seen.append(app.category) }
        return seen
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip("All", selected: category == nil) { category = nil }
                ForEach(categories, id: \.self) { name in chip(name, selected: category == name) { category = name } }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DevysTypography.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? DevysColors.sheet : DevysColors.ink2)
                .background(selected ? DevysColors.ink : DevysColors.sheetTint, in: Capsule())
                .overlay { Capsule().strokeBorder(selected ? .clear : DevysColors.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var listed: some View {
        switch store.listedApps {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        case .failed(let message):
            EmptyNote(text: message)
        case .loaded(let apps):
            ForEach(category.map { [$0] } ?? categories, id: \.self) { name in
                VStack(alignment: .leading, spacing: 8) {
                    Text(name).font(DevysTypography.label).foregroundStyle(DevysColors.ink3).accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], alignment: .leading, spacing: 4) {
                        ForEach(apps.filter { $0.category == name }) { app in
                            AppTile(name: app.name, description: app.description, logo: app.logo) { action(app: app.app, installed: app.installed) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if found.isEmpty, !searching {
            Text("No apps found. Paste an app's address to add it.").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], alignment: .leading, spacing: 4) {
            ForEach(found) { app in
                AppTile(name: app.name, description: app.description, logo: app.logo) { action(app: app.app, installed: app.installed) }
            }
        }
    }

    /// What an app's row offers: Add, Connect, Review, or that it is on.
    @ViewBuilder private func action(app: String, installed: Bool) -> some View {
        let entry = store.apps.value?.first { $0.id == app && $0.state != nil }
        if adding == app {
            ProgressView().controlSize(.small)
        } else if installed || entry?.state == .turnedOn {
            Text("On").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
        } else if let entry, entry.state == .review {
            AddCapsule(title: "Review") { review(entry.id) }
        } else {
            AddCapsule(title: entry == nil ? "Add" : entry?.state == .lapsed ? "Reconnect" : "Connect") { add(app) }
        }
    }

    @ViewBuilder private var connectedList: some View {
        if connected.isEmpty {
            Text("No apps connected yet.").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
        }
        ForEach(connected) { app in
            HStack(spacing: 12) {
                AppLogo(path: app.logo, name: app.name, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                    Text(stateText(app)).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                }
                Spacer(minLength: 8)
                switch app.state {
                case .connecting, .lapsed:
                    AddCapsule(title: app.state == .lapsed ? "Reconnect" : "Connect") { add(app.id) }
                case .review:
                    AddCapsule(title: "Review") { review(app.id) }
                default:
                    AddCapsule(title: "Change") { review(app.id) }
                }
                Button("Remove") { remove(app.id) }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            }
            .padding(.vertical, 4)
        }
    }

    private func stateText(_ app: AppEntry) -> String {
        switch app.state {
        case .turnedOn: "On"
        case .review: "Connected · waiting for you to turn it on"
        case .lapsed: "Its sign-in stopped working"
        default: "Not connected yet"
        }
    }

    private func search() async {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard typed.count > 1 else {
            found = []
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searching = true
        found = (try? await runtime.searchApps(store.businessID, typed)) ?? []
        searching = false
    }

    /// Adds the app (or picks up one already added) and runs its own sign-in; once connected its
    /// review opens beside the conversation.
    private func add(_ app: String) {
        let businessID = store.businessID
        error = nil
        adding = app
        Task {
            defer {
                adding = nil
                store.send(.listedAppsRequested)
            }
            do {
                var added = try await runtime.addApp(businessID, app)
                if added.state == .connecting || added.state == .lapsed {
                    let connecting = try await runtime.connectApp(businessID, added.id)
                    added = connecting.app
                    if let url = connecting.url {
                        _ = try await session.authenticate(using: url, callback: .customScheme("devys"), additionalHeaderFields: [:])
                    }
                }
                // Signed in (or needing no sign-in): its one review, beside the conversation.
                if added.state != .turnedOn { review(added.id) }
            } catch DevysHTTPError.rejected(_, let message) where !message.isEmpty {
                error = message
            } catch {
                // A cancelled sign-in leaves the app added; Connect is on its row.
            }
        }
    }

    private func review(_ appID: String) {
        store.send(.connectAppsToggled(false))
        store.send(.layerOpened(.remoteApp(appID)))
    }

    private func remove(_ appID: String) {
        let businessID = store.businessID
        Task {
            do {
                try await runtime.installApp(businessID, appID, false)
            } catch {
                self.error = "That app couldn't be removed."
            }
            store.send(.listedAppsRequested)
        }
    }
}

/// One app: its logo, name and a grey line, with its action at the end.
private struct AppTile<Action: View>: View {
    let name: String
    let description: String
    let logo: String?
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 12) {
            AppLogo(path: logo, name: name, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink).lineLimit(1)
                if !description.isEmpty {
                    Text(description).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

/// The grey Add capsule.
private struct AddCapsule: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DevysTypography.caption.weight(.semibold))
                .foregroundStyle(DevysColors.ink)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(DevysColors.track.opacity(0.7), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
