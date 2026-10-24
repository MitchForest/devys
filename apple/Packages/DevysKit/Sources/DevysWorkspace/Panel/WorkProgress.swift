import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

/// A work item's plan, each step with where it stands; the owner's own steps read "You: …".
struct WorkStepsView: View {
    let steps: [WorkStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                HStack(spacing: 8) {
                    Image(systemName: Self.symbol(step.state))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Self.tint(step.state))
                        .accessibilityHidden(true)
                    Text(step.text)
                        .font(step.state == .doing ? DevysTypography.secondary.weight(.medium) : DevysTypography.secondary)
                        .foregroundStyle(step.state == .todo ? DevysColors.ink3 : DevysColors.ink)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(step.state.rawValue)
            }
        }
    }

    static func symbol(_ state: WorkStep.State) -> String {
        switch state {
        case .done: "checkmark.circle.fill"
        case .doing: "smallcircle.filled.circle"
        case .blocked: "exclamationmark.circle.fill"
        case .todo, .unknown: "circle"
        }
    }

    static func tint(_ state: WorkStep.State) -> Color {
        switch state {
        case .done: DevysColors.green
        case .doing: DevysColors.indigo
        case .blocked: DevysColors.red
        case .todo, .unknown: DevysColors.ink3
        }
    }
}

/// What the work achieved, each one sentence that wraps as text: label · value · its site as a
/// link, and its mark, as the web.
struct WorkResultsView: View {
    let results: [WorkResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Text(Self.sentence(result))
                    .font(DevysTypography.secondary)
                    .foregroundStyle(DevysColors.ink2)
                    .tint(DevysColors.indigo)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    static func sentence(_ result: WorkResult) -> AttributedString {
        var label = AttributedString(result.label)
        label.font = DevysTypography.secondary.weight(.medium)
        label.foregroundColor = DevysColors.ink
        var text = label
        if let value = result.value { text += AttributedString(" · \(value)") }
        if let link = result.url, let url = URL(string: link), url.scheme == "https", let host = url.host() {
            var site = AttributedString(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
            site.link = url
            text += AttributedString(" · ") + site
        }
        if let mark = result.mark {
            var check = AttributedString(" \(mark)")
            check.font = DevysTypography.secondary.weight(.semibold)
            check.foregroundColor = tint(result.check)
            text += check
        }
        return text
    }

    static func tint(_ check: WorkResult.Check?) -> Color {
        switch check {
        case .held: DevysColors.green
        case .failed: DevysColors.red
        case .uncertain, nil: DevysColors.amber
        }
    }
}

/// A work item, drawn from the item as it is now so it updates in place: who is on it, the plan,
/// its results and one line of state with at most one thing for the owner to do. It heads the
/// work's view beside the conversation, whose header names it.
struct WorkProgressCard: View {
    let store: StoreOf<Workspace>
    let workItemID: String

    var body: some View {
        let item = store.work.value?.first { $0.id == workItemID }
        VStack(alignment: .leading, spacing: 10) {
            if let item {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(store.state.employeeName(item.ownerEmployeeID))
                        .font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).lineLimit(1)
                    Spacer(minLength: 8)
                    if let position = store.state.stepPosition(item), item.state.isOpen {
                        Text(position).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).fixedSize()
                    }
                }
                if !item.steps.isEmpty { WorkStepsView(steps: item.steps) }
                if !item.results.isEmpty { WorkResultsView(results: item.results) }
                WorkStateLine(store: store, item: item, line: store.state.cardLine(item))
            } else {
                Text("This work is no longer here.").font(DevysTypography.body).foregroundStyle(DevysColors.ink3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(DevysColors.hairline).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("work-card")
    }
}

/// A work item in a conversation: one line (its title, who is on it, where it stands) that opens
/// the work beside the conversation. The plan is shown once, there.
struct WorkChip: View {
    let store: StoreOf<Workspace>
    let workItemID: String
    let text: String
    @State private var hovering = false

    var body: some View {
        let item = store.work.value?.first { $0.id == workItemID }
        let status = item.map(store.state.workStatus)
        Button { store.send(.workOpened(workItemID)) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text(item?.title ?? text).font(DevysTypography.control.weight(.semibold)).foregroundStyle(DevysColors.ink)
                        if let item {
                            Text(" · \(store.state.employeeName(item.ownerEmployeeID))").font(DevysTypography.control).foregroundStyle(DevysColors.ink3)
                        }
                    }
                    .lineLimit(1)
                    if let status, !status.text.isEmpty {
                        Text(status.text).font(DevysTypography.secondary.weight(.medium)).foregroundStyle(status.tone.color).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 520, alignment: .leading)
            .background(hovering ? DevysColors.sheetTint : DevysColors.sheet, in: RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous).strokeBorder(DevysColors.hairline, lineWidth: 1) }
            .devysElevation(.resting)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityIdentifier("work-chip")
    }
}

/// The card's one line of state and its one action: Stop (and Watch while the browser is being
/// driven for it), Start, the request's own action, Hand back.
private struct WorkStateLine: View {
    let store: StoreOf<Workspace>
    let item: WorkItem
    let line: WorkCardLine
    @Dependency(\.browserClient) private var browser
    @State private var browsing = false

    var body: some View {
        HStack(spacing: 8) {
            switch line {
            case .working(let doing):
                dot(DevysColors.indigo)
                label("\(doing)…")
                Spacer(minLength: 6)
                if browsing {
                    Button("Watch") { store.send(.browserOpened(item.id)) }
                        .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                        .help("Watch the browser")
                }
                Button("Stop", systemImage: "stop.fill") { store.send(.stopTapped(item.ownerEmployeeID)) }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
                    .disabled(store.isStopping)
                    .help("Stops \(store.state.employeeName(item.ownerEmployeeID)) now")
            case .ready:
                dot(DevysColors.amber)
                label("Ready when you are")
                Spacer(minLength: 6)
                Button("Start", systemImage: "play.fill") { store.send(.startTapped(item.id)) }
                    .buttonStyle(DevysButtonStyle(.aurora, compact: true))
                    .help("Starts the plan in this order; payments and anything public still ask when reached.")
            case .yourTurn(let request):
                YourTurn(store: store, request: request)
            case .yours:
                dot(DevysColors.amber)
                label("You have it")
                Spacer(minLength: 6)
                Button("Hand back", systemImage: "arrowshape.turn.up.left") { store.send(.takeoverToggled(item.id)) }
                    .buttonStyle(DevysButtonStyle(.aurora, compact: true))
            case .waiting(let condition):
                dot(DevysColors.ink3)
                label("Waiting on \(condition)")
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(DevysColors.green).accessibilityHidden(true)
                label("Done")
            case .upNext(let next):
                label("Up next: \(next)").foregroundStyle(DevysColors.ink3)
            case .quiet:
                EmptyView()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .poll(id: isWorking, every: isWorking ? .seconds(5) : nil) {
            guard isWorking else { return browsing = false }
            let status = try? await browser.status(store.businessID)
            browsing = status.map { $0.open && $0.driver == item.id } ?? false
        }
    }

    private var isWorking: Bool {
        if case .working = line { true } else { false }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(DevysTypography.secondary.weight(.medium)).foregroundStyle(DevysColors.ink).lineLimit(2)
    }
}

/// "Your turn: <the ask>" and exactly its one action: Connect, Open Chrome (on iPhone and iPad,
/// Take over), Add card, Choose file, Approve… with Face ID or Touch ID, or Approve and Decline.
/// What an approval covers (its steps, its draft, a modelled action's input) shows above it.
private struct YourTurn: View {
    let store: StoreOf<Workspace>
    let request: NeedsYouItem

    var body: some View {
        if let decision = request.decision {
            VStack(alignment: .leading, spacing: 8) {
                if shows(decision) { DecisionFields(store: store, decision: decision) }
                HStack(spacing: 8) {
                    Circle().fill(DevysColors.amber).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text("Your turn: \(DecisionText.ask(request))")
                        .font(DevysTypography.secondary.weight(.medium)).foregroundStyle(DevysColors.ink).lineLimit(2)
                    Spacer(minLength: 6)
                    action(decision)
                }
            }
        }
    }

    private func shows(_ decision: Decision) -> Bool {
        decision.kind == .decision || !decision.steps.isEmpty || decision.preview != nil
    }

    @ViewBuilder private func action(_ decision: Decision) -> some View {
        if case .connect(let appID, _) = decision.request {
            if let app = store.state.remoteApp(appID) { AppActionButton(store: store, app: app) }
        } else if decision.kind == .takeOver, let workID = decision.workItemID {
            #if os(macOS)
                Button("Open Chrome", systemImage: "macwindow") { store.send(.takeOverTapped(workID)) }
                    .buttonStyle(DevysButtonStyle(.aurora, compact: true))
                    .help("Brings the business's Chrome to the front; Hand back here when you're done.")
            #else
                Button("Take over", systemImage: "hand.raised") { store.send(.takeOverTapped(workID)) }
                    .buttonStyle(DevysButtonStyle(.aurora, compact: true))
                    .help("Opens the live browser for you; Hand back when you're done.")
            #endif
        } else {
            // Approve and Decline answer an approval; any other request has its one action.
            RequestActions(store: store, decision: decision, compact: true, declines: [.approve, .decision].contains(decision.kind) && !decision.isSpend)
        }
    }
}

extension WorkStatus.Tone {
    /// Amber when it waits on the owner, indigo while it runs, green once done.
    var color: Color {
        switch self {
        case .you: DevysColors.amber
        case .working: DevysColors.indigo
        case .done: DevysColors.green
        case .quiet: DevysColors.ink3
        }
    }
}
