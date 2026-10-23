import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// Home's permanent view: everything waiting on the owner, then what is moving and what is
/// stuck. Each row opens its thread; a decision is answered right here.
struct NeedsYou: View {
    let store: StoreOf<Workspace>
    let close: () -> Void

    var body: some View {
        if let home = store.home.value {
            VStack(spacing: 0) {
                PanelHeader(title: home.needsYou.isEmpty ? "At a glance" : "Needs you", close: close)
                PanelBody {
                    if !home.needsYou.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(home.needsYou) { item in
                                if item.kind == .reconnect, let app = item.app {
                                    ReconnectRow(store: store, app: app)
                                } else if item.kind == .connect, let decision = item.decision, let app = item.app {
                                    ConnectRequestRow(store: store, decision: decision, app: app)
                                } else if let decision = item.decision, let routine = item.routine {
                                    RoutineProposal(store: store, decision: decision, routine: routine)
                                } else if let decision = item.decision {
                                    DecisionRow(store: store, decision: decision)
                                } else {
                                    NeedsYouRow(store: store, item: item)
                                }
                            }
                        }
                    }
                    if !home.glance.moving.isEmpty {
                        PanelSection(title: "Moving", count: home.glance.moving.count) {
                            ForEach(home.glance.moving) { GlanceRow(store: store, card: $0, stuck: false) }
                        }
                    }
                    if !home.glance.stuck.isEmpty {
                        PanelSection(title: "Stuck", count: home.glance.stuck.count) {
                            ForEach(home.glance.stuck) { GlanceRow(store: store, card: $0, stuck: true) }
                        }
                    }
                }
            }
        }
    }
}

/// One request, answered in place; its input unfolds on demand (a spend shows it always).
struct DecisionRow: View {
    let store: StoreOf<Workspace>
    let decision: Decision
    @State private var open = false

    var body: some View {
        let employee = store.state.employee(decision.employeeID)
        let item = store.work.value?.first { $0.id == decision.workItemID }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let employee { Portrait(store.state.portrait(for: employee), size: 22, isAnimated: false) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item?.title ?? DecisionText.title(decision)).font(DevysTypography.control.weight(.semibold)).foregroundStyle(DevysColors.ink)
                    Text("\(employee?.name ?? "An employee") asks\(item == nil ? "" : " · \(DecisionText.title(decision))")")
                        .font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
                .lineLimit(1)
            }
            // A spend, steps or a draft are what is approved: shown without asking for details.
            let shown = decision.isSpend || !decision.steps.isEmpty || decision.preview != nil
            if open || shown { DecisionFields(store: store, decision: decision) }
            HStack(spacing: 6) {
                RequestActions(store: store, decision: decision, compact: true)
                Spacer(minLength: 4)
                if !shown, !DecisionText.fields(decision).isEmpty {
                    Button(open ? "Hide details" : "Details") { open.toggle() }
                        .buttonStyle(.plain).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
                if let workID = decision.workItemID {
                    Button("Thread") { store.send(.threadOpened(workID)) }
                        .buttonStyle(.plain).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
            }
        }
        .devysCard(padding: 12)
    }
}

/// One exact request: who asked, what they will do, and the input it will run with.
struct DecisionCard: View {
    let store: StoreOf<Workspace>
    let decision: Decision

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusChip([.takeOver, .secret, .file].contains(decision.kind) ? "Needs you" : "Needs approval", tone: .needsYou)
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

/// How the owner answers a request: Approve or Decline; a take over takes the work over and opens
/// its live browser; a spend approval opens the signing sheet (Face ID or Touch ID); a secret
/// request opens the secure entry sheet.
struct RequestActions: View {
    let store: StoreOf<Workspace>
    let decision: Decision
    let compact: Bool

    var body: some View {
        if case .secret(_, _, let spend) = decision.request {
            Button(spend ? "Add card" : "Add secret", systemImage: "key") { store.send(.secretTapped(decision.id)) }
                .buttonStyle(DevysButtonStyle(.aurora, compact: compact))
                .help("Opens a secure sheet; the employee uses it by name and never sees it.")
        } else if case .file(_, let accept) = decision.request {
            ChooseFileButton(store: store, decision: decision, accept: accept, compact: compact)
        } else if decision.kind == .takeOver, let workID = decision.workItemID {
            Button("Take over", systemImage: "hand.raised") { store.send(.takeOverTapped(workID)) }
                .buttonStyle(DevysButtonStyle(.aurora, compact: compact))
                .help("Takes this work over and opens its browser; Hand back when you're done.")
        } else if decision.isSpend {
            Button("Approve…", systemImage: "faceid") { store.send(.signTapped(decision.id)) }
                .buttonStyle(DevysButtonStyle(.aurora, compact: compact))
                .help("Shows exactly what you sign, then asks for Face ID or Touch ID.")
        } else {
            Button("Approve", systemImage: "checkmark") { store.send(.decisionAnswered(decision.id, approve: true)) }
                .buttonStyle(DevysButtonStyle(.aurora, compact: compact))
                .help("Allows this exact request once.")
        }
        Button("Decline") { store.send(.decisionAnswered(decision.id, approve: false)) }
            .buttonStyle(DevysButtonStyle(.raised, compact: compact))
    }
}

/// The request's fields, key by key, then the exact steps it covers and the draft it shows.
private struct DecisionFields: View {
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

/// Work waiting on the owner that isn't a decision here: it opens its thread.
private struct NeedsYouRow: View {
    let store: StoreOf<Workspace>
    let item: NeedsYouItem

    var body: some View {
        Button { if let workID = item.workID { store.send(.threadOpened(workID)) } } label: {
            HStack(spacing: 10) {
                if let employee = store.state.employee(item.employeeID) {
                    Portrait(store.state.portrait(for: employee), size: 22, isAnimated: false)
                }
                Text(item.title).font(DevysTypography.control).foregroundStyle(DevysColors.ink).lineLimit(1)
                Spacer(minLength: 4)
                if item.workID != nil {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                }
            }
            .devysCard(padding: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.workID == nil)
    }
}

/// A moving or stuck work item; stuck ones say what they wait on.
private struct GlanceRow: View {
    let store: StoreOf<Workspace>
    let card: GlanceItem
    let stuck: Bool
    @State private var hovering = false

    var body: some View {
        Button { store.send(.threadOpened(card.id)) } label: {
            HStack(spacing: 10) {
                if let employee = store.state.employee(card.employeeID) {
                    Portrait(store.state.portrait(for: employee), size: 20, isAnimated: false)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title).font(DevysTypography.secondary.weight(.medium)).foregroundStyle(DevysColors.ink).lineLimit(1)
                    if stuck {
                        Text(card.waitCondition.map { "Waiting on \($0)" } ?? "No change in a day")
                            .font(DevysTypography.caption).foregroundStyle(DevysColors.red).lineLimit(1)
                    } else if let progress = card.progress {
                        Text(progress).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovering ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, -8)
    }
}
