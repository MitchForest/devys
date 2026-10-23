import AuthenticationServices
import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

// MARK: - Remote apps (`devys:team/app/<id>`): Connect, a connect request, the review layer

/// An app's logo as Devys serves it (loaded with this device's sign-in), or its first letter.
/// Logos already loaded this run, by path, so a sheet or row shows them at once on every open.
@MainActor private enum LogoCache {
    static var images: [String: Image] = [:]
}

struct AppLogo: View {
    let path: String?
    let name: String
    var size: CGFloat = 22
    @Dependency(\.runtimeClient) private var runtime
    @State private var loaded: Image?

    private var image: Image? { loaded ?? path.flatMap { LogoCache.images[$0] } }

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFit()
                    .background(DevysColors.sheet)
            } else {
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(DevysColors.indigo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DevysColors.indigo.opacity(0.14))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
        .task(id: path) {
            guard let path, LogoCache.images[path] == nil, let data = try? await runtime.appLogo(path) else { return }
            #if os(macOS)
                guard let picture = NSImage(data: data) else { return }
                let shown = Image(nsImage: picture)
            #else
                guard let picture = UIImage(data: data) else { return }
                let shown = Image(uiImage: picture)
            #endif
            LogoCache.images[path] = shown
            loaded = shown
        }
    }
}

/// Connect (or Reconnect): the provider's own sign-in in the system sheet
/// (ASWebAuthenticationSession), which returns to the app as `devys://apps/…`; then `done`.
struct ConnectButton: View {
    let businessID: String
    let appID: String
    let title: String
    var compact = true
    let done: () -> Void
    @Dependency(\.runtimeClient) private var runtime
    @Environment(\.webAuthenticationSession) private var session

    var body: some View {
        Button(title, systemImage: "powerplug") {
            Task {
                do {
                    let connecting = try await runtime.connectApp(businessID, appID)
                    if let url = connecting.url {
                        _ = try await session.authenticate(using: url, callback: .customScheme("devys"), additionalHeaderFields: [:])
                    }
                } catch {
                    // Cancelled or refused: what stands shows on the next read.
                }
                done()
            }
        }
        .buttonStyle(DevysButtonStyle(.aurora, compact: compact))
    }
}

/// Connect, Reconnect or Review, as the app's state calls for.
struct AppActionButton: View {
    let store: StoreOf<Workspace>
    let app: AppEntry
    var compact = true

    var body: some View {
        switch app.state {
        case .connecting, .lapsed:
            ConnectButton(businessID: store.businessID, appID: app.id, title: app.state == .lapsed ? "Reconnect" : "Connect", compact: compact) {
                store.send(.refreshTapped)
            }
        case .review:
            Button("Review") { store.send(.layerOpened(.remoteApp(app.id))) }
                .buttonStyle(DevysButtonStyle(.aurora, compact: compact))
        default:
            StatusChip("On", tone: .done, size: .small)
        }
    }
}

extension Workspace.State {
    /// One of the business's remote apps, from the directory.
    func remoteApp(_ id: String) -> AppEntry? {
        apps.value?.first { $0.id == id && $0.state != nil }
    }
}

/// An app an employee asks the owner to connect, not for a work item: one card in the chat where
/// it was asked. A work item's connect request is on its card.
struct ConnectRequestRow: View {
    let store: StoreOf<Workspace>
    let decision: Decision
    let app: AppBadge

    var body: some View {
        let employee = store.state.employee(decision.employeeID)
        let why: String = if case .connect(_, let why) = decision.request { why } else { "" }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AppLogo(path: app.logo, name: app.name, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(DevysTypography.control.weight(.semibold)).foregroundStyle(DevysColors.ink)
                    Text("\(employee?.name ?? "An employee"): \(why)").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).lineLimit(2)
                }
            }
            HStack(spacing: 6) {
                if let entry = store.state.remoteApp(app.id) {
                    AppActionButton(store: store, app: entry)
                }
                Button("Decline") { store.send(.decisionAnswered(decision.id, approve: false)) }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
            }
        }
        .devysCard(padding: 12)
    }
}

/// A remote app as a layer: connect it, or its one review card.
struct RemoteAppLayer: View {
    let store: StoreOf<Workspace>
    let appID: String

    var body: some View {
        ScrollView {
            if let app = store.state.remoteApp(appID) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        AppLogo(path: app.logo, name: app.name, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                            if !app.summary.isEmpty {
                                Text(app.summary).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(2)
                            }
                        }
                    }
                    if app.state == .review || app.state == .turnedOn {
                        AppReviewCard(businessID: store.businessID, app: app) { store.send(.refreshTapped) }.id(app.state)
                    } else {
                        Text(app.state == .lapsed
                            ? "\(app.name)'s sign-in stopped working. Sign in again to keep using it."
                            : "Sign in to \(app.name) to connect it. You choose what employees may do next.")
                            .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                        AppActionButton(store: store, app: app, compact: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            } else {
                EmptyNote(text: "This app was removed.").padding(14)
            }
        }
    }
}

/// The one review: what it does on its own, what asks first, what employees never get, and who
/// uses it. Turn on (or Save) makes the owner's choices its policy.
struct AppReviewCard: View {
    let businessID: String
    let app: AppEntry
    let done: () -> Void
    @Dependency(\.runtimeClient) private var runtime
    @State private var review: AppReview?
    @State private var lines: [String: ToolLine] = [:]
    @State private var users: Set<String> = []
    @State private var editing = false
    @State private var saving = false

    private static let sections: [(ToolLine, String)] = [
        (.own, "Can do on its own"),
        (.ask, "Asks you first"),
        (.never, "Never available to employees")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let review {
                ForEach(Self.sections, id: \.0) { line, title in
                    let tools = review.tools.filter { (lines[$0.capability] ?? $0.line) == line }
                    if !tools.isEmpty || editing {
                        section(title) {
                            ForEach(tools) { tool in toolRow(tool) }
                        }
                    }
                }
                section("Who can use it") {
                    ForEach(review.employees.filter { editing || users.contains($0.id) }) { user in
                        HStack {
                            Text(user.name).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink)
                            Spacer(minLength: 4)
                            if editing {
                                Toggle(isOn: Binding(
                                    get: { users.contains(user.id) },
                                    set: { isOn in if isOn { users.insert(user.id) } else { users.remove(user.id) } }
                                )) { EmptyView() }
                                    .labelsHidden()
                                    .accessibilityLabel("\(user.name) uses \(app.name)")
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }
                }
                if app.state != .turnedOn || editing {
                    HStack(spacing: 8) {
                        Button(app.state == .turnedOn ? "Save" : "Turn on", systemImage: "checkmark") { turnOn() }
                            .buttonStyle(DevysButtonStyle(.aurora))
                            .disabled(saving)
                        if editing, app.state == .turnedOn {
                            Button("Cancel") { editing = false }.buttonStyle(DevysButtonStyle(.quiet))
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task(id: app.id) { await load() }
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
                Spacer(minLength: 4)
                if !editing {
                    Button("Change") { editing = true }
                        .buttonStyle(.plain).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
            }
            rows()
        }
    }

    private func toolRow(_ tool: AppReview.Tool) -> some View {
        HStack(spacing: 8) {
            Text(tool.title).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink).lineLimit(1)
            Spacer(minLength: 4)
            if editing, !tool.fixed {
                Picker("\(tool.title): who decides", selection: Binding(
                    get: { lines[tool.capability] ?? tool.line },
                    set: { lines[tool.capability] = $0 }
                )) {
                    Text("On its own").tag(ToolLine.own)
                    Text("Asks you first").tag(ToolLine.ask)
                    Text("Never").tag(ToolLine.never)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DevysColors.sheetTint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .help(tool.description)
    }

    private func load() async {
        guard let loaded = try? await runtime.appReview(businessID, app.id) else { return }
        review = loaded
        lines = Dictionary(uniqueKeysWithValues: loaded.tools.map { ($0.capability, $0.line) })
        users = Set(loaded.employees.filter(\.uses).map(\.id))
    }

    private func turnOn() {
        saving = true
        let acceptance = AppAcceptance(lines: lines, employees: Array(users))
        Task {
            _ = try? await runtime.acceptApp(businessID, app.id, acceptance)
            saving = false
            editing = false
            done()
        }
    }
}
