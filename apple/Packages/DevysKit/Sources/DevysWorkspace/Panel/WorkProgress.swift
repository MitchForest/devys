import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The plan an employee shows while the work takes time, each step with where it stands.
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
                    Text(step.title)
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

/// What the work achieved, in the words of `WorkResult.text`: label · value, its link and its mark.
struct WorkResultsView: View {
    let results: [WorkResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(result.label).font(DevysTypography.secondary.weight(.medium)).foregroundStyle(DevysColors.ink)
                    if let value = result.value {
                        Text("· \(value)").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                    }
                    if let link = result.url, let url = URL(string: link), url.scheme == "https" {
                        Link(link, destination: url).font(DevysTypography.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    if let mark = result.mark {
                        Text(mark).font(DevysTypography.secondary.weight(.semibold)).foregroundStyle(Self.tint(result.check))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func tint(_ check: WorkResult.Check?) -> Color {
        switch check {
        case .held: DevysColors.green
        case .failed: DevysColors.red
        case .uncertain, nil: DevysColors.amber
        }
    }
}

/// A work item's card in its thread: one per item, drawn from the item as it is now, so each
/// change to its steps or results updates it in place.
struct WorkProgressCard: View {
    let store: StoreOf<Workspace>
    let workItemID: String
    let text: String

    var body: some View {
        let item = store.work.value?.first { $0.id == workItemID }
        VStack(alignment: .leading, spacing: 8) {
            Text(item.map { WorkStep.progress($0.steps) ?? "Results" } ?? text)
                .font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).lineLimit(1)
            if let item, !item.steps.isEmpty { WorkStepsView(steps: item.steps) }
            if let item, !item.results.isEmpty { WorkResultsView(results: item.results) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 520, alignment: .leading)
        .background(DevysColors.sheet, in: RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous).strokeBorder(DevysColors.hairline, lineWidth: 1) }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityIdentifier("work-progress")
    }
}
