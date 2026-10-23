import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// macOS and regular-width iPad get the frame-and-workspace shell; compact
/// width (iPhone, narrow iPad) gets tabs with full-screen conversations.
struct WorkspaceScreen: View {
    let store: StoreOf<Workspace>
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        Group {
            if store.account != nil, store.businesses.isEmpty {
                FirstBusiness(store: store)
            } else {
                workspace
            }
        }
        .alert(
            "\(store.joinRequest?.name ?? "A device") wants to join",
            // Only its buttons answer it (Esc is Deny); the alert closing by itself answers nothing.
            isPresented: Binding(get: { store.joinRequest != nil }, set: { _ in }),
            presenting: store.joinRequest
        ) { request in
            Button("Deny", role: .cancel) { store.send(.joinAnswered(request.id, allow: false)) }
            Button("Allow") { store.send(.joinAnswered(request.id, allow: true)) }
                .keyboardShortcut(.defaultAction)
        } message: { request in
            Text(request.match.joined(separator: " "))
        }
    }

    private var workspace: some View {
        shell.modifier(WorkspaceSheets(store: store))
            // A task, not `onChange(initial:)`: SwiftUI can flush a pending initial onChange
            // synchronously while a reducer mutates observed state (the first account load),
            // and sending then traps on the store's re-entrancy check.
            .task(id: scenePhase) { store.send(.activeChanged(scenePhase == .active)) }
    }

    @ViewBuilder private var shell: some View {
        #if os(iOS)
            if sizeClass == .compact {
                CompactShell(store: store)
            } else {
                RegularShell(store: store)
            }
        #else
            RegularShell(store: store)
        #endif
    }
}

/// Signed in with no business yet: its name, a line about it if you like, and Start. The starting
/// team (everyone, with the Head of Operations) is the default; Settings changes it later.
private struct FirstBusiness: View {
    let store: StoreOf<Workspace>

    var body: some View {
        Group {
            if let preferences = store.spawn(\.preferences), let draft = preferences.newBusiness {
                form(preferences, draft: draft)
                    .onChange(of: preferences.businesses.isEmpty) { _, empty in
                        if !empty { store.send(.preferencesToggled(false)) }
                    }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DevysColors.frame)
    }

    private func form(_ preferences: StoreOf<Preferences>, draft: NewBusinessDraft) -> some View {
        VStack(spacing: 28) {
            DevysAvatar(
                AvatarSpec(palette: .blue, shape: .roundedSquare, seed: 7),
                size: 88,
                mood: draft.isSubmitting ? .thinking : draft.error == nil ? .idle : .oops,
                label: "Devys"
            )
            VStack(spacing: DevysSpacing.compact) {
                Text("Name your business")
                    .font(DevysTypography.title)
                    .foregroundStyle(DevysColors.ink)
                    .padding(.bottom, DevysSpacing.small)
                field("Name", text: binding(preferences, \.name))
                field("What it does (optional)", text: binding(preferences, \.brief))
                Button {
                    preferences.send(.createBusinessTapped)
                } label: {
                    Text("Start").font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.aurora)
                .disabled(!draft.canCreate)
                .keyboardShortcut(.defaultAction)
                .padding(.top, DevysSpacing.regular)
                Text(draft.error ?? " ").font(DevysTypography.body).foregroundStyle(DevysColors.ink3)
            }
        }
        .frame(maxWidth: 320)
        .padding(DevysSpacing.roomy)
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text, prompt: Text(prompt).foregroundStyle(DevysColors.ink3))
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(DevysColors.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(prompt)
    }

    private func binding(_ preferences: StoreOf<Preferences>, _ keyPath: WritableKeyPath<NewBusinessDraft, String>) -> Binding<String> {
        Binding(
            get: { preferences.newBusiness?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var draft = preferences.newBusiness else { return }
                draft[keyPath: keyPath] = value
                preferences.send(.newBusinessEdited(draft))
            }
        )
    }
}
