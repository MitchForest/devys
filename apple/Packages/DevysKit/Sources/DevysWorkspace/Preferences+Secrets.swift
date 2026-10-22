import ComposableArchitecture2
import Dependencies
package import DevysClient
import DevysDesignSystem
import SwiftUI

// MARK: - Secrets: the selected business's secrets by name

package enum SecretIntent {
    case requested
    case loaded(businessID: String, Loadable<[SecretEntry]>)
    case addTapped
    case edited(SecretEntrySheet)
    /// The sheet's value goes straight to the vault; it never enters state.
    case submitted(NewSecret)
    /// The list as it now stands, or why it wasn't saved.
    case finished(businessID: String, Result<[SecretEntry], SecretFailure>)
    case dismissed
    case removeTapped(name: String)
}

/// Why a secret wasn't saved, as the server said it (never with the value).
package struct SecretFailure: Error, Equatable {
    package let message: String
}

extension Preferences {
    func reduceSecrets(_ intent: SecretIntent, state: inout State) {
        guard let businessID = state.selectedBusinessID ?? state.businesses.first?.id else { return }
        let runtime = runtime
        switch intent {
        case .requested:
            store.addTask {
                do {
                    try store.send(Action(.secret(.loaded(businessID: businessID, .loaded(try await runtime.secrets(businessID))))))
                } catch {
                    try store.send(Action(.secret(.loaded(businessID: businessID, .failed(SecretEntrySheet.message(error))))))
                }
            }
        case .loaded(let id, let secrets):
            guard id == businessID else { return }
            state.secrets = secrets
        case .addTapped:
            state.secretEntry = SecretEntrySheet()
        case .edited(let sheet):
            guard let current = state.secretEntry, !current.isSaving else { return }
            state.secretEntry = sheet
        case .submitted(let secret):
            guard var sheet = state.secretEntry, !sheet.isSaving, secret.name == sheet.name else { return }
            sheet.isSaving = true
            sheet.error = nil
            state.secretEntry = sheet
            store.addTask {
                do {
                    try store.send(Action(.secret(.finished(businessID: businessID, .success(try await runtime.addSecret(businessID, secret))))))
                } catch {
                    try store.send(Action(.secret(.finished(businessID: businessID, .failure(SecretFailure(message: SecretEntrySheet.message(error)))))))
                }
            }
        case .finished(let id, .success(let secrets)):
            state.secretEntry = nil
            if id == businessID { state.secrets = .loaded(secrets) }
        case .finished(_, .failure(let failure)):
            state.secretEntry?.isSaving = false
            state.secretEntry?.error = failure.message
        case .dismissed:
            if state.secretEntry?.isSaving != true { state.secretEntry = nil }
        case .removeTapped(let name):
            if let secrets = state.secrets.value { state.secrets = .loaded(secrets.filter { $0.name != name }) }
            store.addTask {
                do {
                    try store.send(Action(.secret(.loaded(businessID: businessID, .loaded(try await runtime.removeSecret(businessID, name))))))
                } catch {
                    try store.send(Action(.failed("\(name) couldn't be removed. Try again.")))
                    try store.send(Action(.secret(.requested)))
                }
            }
        }
    }
}

/// Settings → Secrets: the business's secrets and cards by name, who added them and when, and
/// when an employee last used one. Values are never shown; a secret is replaced by adding it again.
struct SecretsPane: View {
    let store: StoreOf<Preferences>

    var body: some View {
        let businessID = store.selectedBusinessID ?? store.businesses.first?.id
        PaneScroll {
            VStack(alignment: .leading, spacing: DevysSpacing.roomy) {
                HStack {
                    if store.businesses.count > 1 {
                        Picker("Business", selection: Binding(get: { businessID ?? "" }, set: { store.send(.businessSelected($0)) })) {
                            ForEach(store.businesses) { Text($0.name).tag($0.id) }
                        }
                        .fixedSize()
                    }
                    Spacer()
                    Button("Add", systemImage: "plus") { store.send(.addSecretTapped) }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                        .disabled(businessID == nil)
                }
                if let error = store.errorText {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                }
                list
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DevysSpacing.roomy)
        }
        .task(id: businessID) { if businessID != nil { store.send(.secretsRequested) } }
        .sheet(isPresented: Binding(get: { store.secretEntry != nil }, set: { if !$0 { store.send(.secretDismissed) } })) {
            if let sheet = store.secretEntry {
                SecretEntryView(
                    sheet: sheet,
                    edit: { store.send(.secretEdited($0)) },
                    save: { store.send(.secretSubmitted($0)) },
                    cancel: { store.send(.secretDismissed) }
                )
            }
        }
    }

    @ViewBuilder private var list: some View {
        switch store.secrets {
        case .loading:
            ProgressView()
        case .failed(let message):
            EmptyNote(text: message)
        case .loaded(let secrets) where secrets.isEmpty:
            EmptyNote(text: "No secrets yet.")
        case .loaded(let secrets):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(secrets) { secret in
                    SecretRow(secret: secret, addedByYou: secret.addedBy == store.ownerID) { store.send(.secretRemoved(secret.name)) }
                }
            }
        }
    }
}

private struct SecretRow: View {
    let secret: SecretEntry
    let addedByYou: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: DevysSpacing.compact) {
            Image(systemName: secret.kind == .spend ? "creditcard" : "key").frame(width: 24).foregroundStyle(DevysColors.ink2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(secret.name).font(DevysTypography.body.weight(.semibold).monospaced()).foregroundStyle(DevysColors.ink)
                    Text(secret.kind == .spend ? "Card" : "Secret").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
                Text(detail).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
            }
            Spacer(minLength: 8)
            Button("Remove", role: .destructive, action: remove)
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                .accessibilityLabel("Remove \(secret.name)")
        }
        .padding(.vertical, 8)
        .contextMenu { Button("Remove", role: .destructive, action: remove) }
    }

    private var detail: String {
        let added = ServerDate.parse(secret.addedAt).map { "Added \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Added"
        let adder = addedByYou ? " by you" : ""
        let used = secret.lastUsedAt.flatMap(ServerDate.parse).map { " · used \($0.formatted(.relative(presentation: .named)))" } ?? ""
        return added + adder + used
    }
}
