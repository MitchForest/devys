import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// A request not bound to a work item (a hire, a routine to activate, an app to connect), as one
/// card in the conversation where it was asked. A work item's requests are on its card.
struct RequestCard: View {
    let store: StoreOf<Workspace>
    let request: NeedsYouItem

    var body: some View {
        if let decision = request.decision {
            if let app = request.app, request.kind == .connect {
                ConnectRequestRow(store: store, decision: decision, app: app)
            } else if let routine = request.routine {
                RoutineProposal(store: store, decision: decision, routine: routine)
            } else {
                DecisionCard(store: store, decision: decision)
            }
        }
    }
}

/// One exact request: who asked, what they will do, and the input it will run with.
struct DecisionCard: View {
    let store: StoreOf<Workspace>
    let decision: Decision

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusChip([.secret, .file].contains(decision.kind) ? "Needs you" : "Needs approval", tone: .needsYou)
            Text(DecisionText.title(decision)).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
            Text("\(store.state.employeeName(decision.employeeID)) \(decision.kind == .decision ? "asked to run this exactly:" : "asks you:")")
                .font(DevysTypography.secondary)
                .foregroundStyle(DevysColors.ink2)
            DecisionFields(store: store, decision: decision)
            HStack(spacing: DevysSpacing.small) {
                RequestActions(store: store, decision: decision, compact: false)
            }
            .padding(.top, 2)
        }
        .devysCard()
    }
}

/// How the owner answers a request: Approve or Decline; a spend approval opens the signing sheet
/// (Face ID or Touch ID); a secret request opens the secure entry sheet; a file request the file
/// chooser. A work item's card offers Decline only on an approval.
struct RequestActions: View {
    let store: StoreOf<Workspace>
    let decision: Decision
    let compact: Bool
    var declines = true

    var body: some View {
        if case .secret(_, _, let spend) = decision.request {
            Button(spend ? "Add card" : "Add secret", systemImage: "key") { store.send(.secretTapped(decision.id)) }
                .buttonStyle(DevysButtonStyle(.aurora, compact: compact))
                .help("Opens a secure sheet; the employee uses it by name and never sees it.")
        } else if case .file(_, let accept) = decision.request {
            ChooseFileButton(store: store, decision: decision, accept: accept, compact: compact)
        } else if decision.isSpend {
            Button("Approve…", systemImage: "faceid") { store.send(.signTapped(decision.id)) }
                .buttonStyle(DevysButtonStyle(.aurora, compact: compact))
                .help("Shows exactly what you sign, then asks for Face ID or Touch ID.")
        } else {
            Button("Approve", systemImage: "checkmark") { store.send(.decisionAnswered(decision.id, approve: true)) }
                .buttonStyle(DevysButtonStyle(.aurora, compact: compact))
                .help("Allows this exact request once.")
        }
        if declines {
            Button("Decline") { store.send(.decisionAnswered(decision.id, approve: false)) }
                .buttonStyle(DevysButtonStyle(.raised, compact: compact))
        }
    }
}

/// The request's fields, key by key, then the exact steps it covers and the draft it shows.
struct DecisionFields: View {
    let store: StoreOf<Workspace>
    let decision: Decision

    var body: some View {
        let fields = DecisionText.fields(decision)
        VStack(alignment: .leading, spacing: 8) {
            if !fields.isEmpty || !decision.steps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(fields, id: \.key) { field in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            label(field.key)
                            Text(field.value).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink).lineLimit(6).textSelection(.enabled)
                        }
                    }
                    if !decision.steps.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            label("Steps")
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(decision.steps.enumerated()), id: \.offset) { index, step in
                                    Text("\(index + 1). \(step)").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if let preview = decision.preview { DraftPreview(store: store, ref: preview) }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).frame(minWidth: 56, alignment: .leading)
    }
}

/// The signing sheet: exactly what is signed (merchant, amount, renewal, action), then Face ID or
/// Touch ID. The system prompt names the merchant and amount again.
struct SigningSheetView: View {
    let store: StoreOf<Workspace>

    var body: some View {
        if let sheet = store.signing {
            let approval = sheet.approval
            VStack(alignment: .leading, spacing: DevysSpacing.regular) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Approve spending").font(DevysTypography.title).foregroundStyle(DevysColors.ink)
                    Text("\(sheet.employee) asks to spend exactly this, once.")
                        .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                }
                VStack(alignment: .leading, spacing: 10) {
                    row("Merchant", approval.counterparty)
                    row("Amount", approval.amount.text, emphasis: true)
                    row("Renews", approval.renewal ?? "No renewal")
                    row("Action", approval.action)
                    if !approval.steps.isEmpty {
                        row("Steps", approval.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
                    }
                    if approval.preview != nil {
                        row("Draft", "As shown on the card, unchanged")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("A different amount, merchant, action or draft needs a new approval.")
                    .font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                if let error = sheet.error {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Cancel") { store.send(.signDismissed) }.buttonStyle(.quiet).disabled(sheet.isSigning)
                    Button(sheet.isSigning ? "Signing…" : "Approve with \(sheet.biometry)") { store.send(.signConfirmed) }
                        .buttonStyle(.aurora)
                        .disabled(sheet.isSigning)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(DevysSpacing.roomy)
            .sheetFrame(width: 420, height: 420)
            .background(DevysColors.sheet)
            .presentationDetents([.medium])
        }
    }

    private func row(_ label: String, _ value: String, emphasis: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(DevysTypography.label).foregroundStyle(DevysColors.ink3).frame(width: 70, alignment: .leading)
            Text(value)
                .font(emphasis ? DevysTypography.heading : DevysTypography.body)
                .foregroundStyle(DevysColors.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
