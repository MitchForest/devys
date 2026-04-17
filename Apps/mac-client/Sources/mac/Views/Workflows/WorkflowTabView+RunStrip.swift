import AppFeatures
import SwiftUI
import UI

extension WorkflowTabView {
    func runStrip(for run: WorkflowRun, definition: WorkflowDefinition) -> some View {
        HStack(alignment: .top, spacing: Spacing.space3) {
            runStripNowCell(for: run)
            runStripNextCell(for: run, definition: definition)
            runStripPlanCell(for: run)
            runStripLogCell(for: run)
        }
        .padding(Spacing.space3)
        .background(theme.base)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.border)
                .frame(height: Spacing.borderWidth)
        }
    }

    private func runStripNowCell(for run: WorkflowRun) -> some View {
        StripCell(
            label: "NOW",
            tint: statusTint(for: run.status)
        ) {
            VStack(alignment: .leading, spacing: Spacing.space1) {
                HStack(spacing: Spacing.space2) {
                    WorkflowRunStatusChip(status: run.status)
                    Text(nowTitle(for: run))
                        .font(Typography.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                }
                Text(nowSubtitle(for: run))
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        } actions: {
            ActionButton("Terminal", icon: "terminal", style: .ghost, action: onOpenTerminal)
                .disabled(run.currentTerminalID == nil)
        }
    }

    private func runStripNextCell(
        for run: WorkflowRun,
        definition: WorkflowDefinition
    ) -> some View {
        let edges: [WorkflowEdge] = {
            guard let currentNodeID = run.currentNodeID else { return [] }
            return definition.outgoingEdges(from: currentNodeID)
        }()
        let awaiting = run.status == .awaitingOperator

        return StripCell(
            label: "NEXT",
            tint: awaiting ? theme.warning : nil
        ) {
            if edges.isEmpty {
                Text("Terminal")
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
            } else if awaiting {
                VStack(alignment: .leading, spacing: Spacing.space1) {
                    Text("Choose next step")
                        .font(Typography.caption)
                        .foregroundStyle(theme.warning)
                    ForEach(edges) { edge in
                        ActionButton(
                            edge.displayLabel,
                            icon: "arrow.right",
                            style: .primary
                        ) {
                            onChooseEdge(edge.id)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(edges.first?.displayLabel ?? "—")
                        .font(Typography.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text("\(edges.count) outgoing")
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        } actions: {
            EmptyView()
        }
    }

    private func runStripPlanCell(for run: WorkflowRun) -> some View {
        let phase = run.latestPlanSnapshot?.currentPhase
        let completed = phase?.tickets.filter(\.isCompleted).count ?? 0
        let total = phase?.tickets.count ?? 0

        return StripCell(
            label: "PLAN",
            tint: nil
        ) {
            if let phase {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.title)
                        .font(Typography.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    HStack(spacing: Spacing.space2) {
                        Text("\(completed) / \(total) tickets")
                            .font(Typography.caption)
                            .foregroundStyle(theme.textSecondary)
                        if total > 0 {
                            planProgressBar(completed: completed, total: total)
                        }
                    }
                }
            } else {
                Text("No active phase")
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
            }
        } actions: {
            ActionButton("Open Plan", icon: "doc.text", style: .ghost, action: onOpenPlan)
                .disabled(
                    definition?.planFilePath
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty != false
                )
        }
    }

    private func runStripLogCell(for run: WorkflowRun) -> some View {
        StripCell(
            label: "LOG",
            tint: logCellTint(for: run)
        ) {
            if let event = run.events.last {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.message)
                        .font(Typography.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                    Text("\(run.events.count) events")
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                Text("No events yet.")
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
            }
        } actions: {
            EmptyView()
        }
    }

    private func planProgressBar(completed: Int, total: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.hover)
                Capsule()
                    .fill(theme.accent)
                    .frame(width: progressWidth(available: proxy.size.width, completed: completed, total: total))
            }
        }
        .frame(height: 4)
        .frame(maxWidth: 80)
    }

    private func progressWidth(available: CGFloat, completed: Int, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return available * CGFloat(completed) / CGFloat(total)
    }

    private func logCellTint(for run: WorkflowRun) -> Color? {
        guard let level = run.events.last?.level else { return nil }
        switch level {
        case .info:
            return nil
        case .warning:
            return theme.warning
        case .error:
            return theme.error
        }
    }

    private func statusTint(for status: WorkflowRunStatus) -> Color? {
        switch status {
        case .running:
            return theme.accent
        case .awaitingOperator, .interrupted:
            return theme.warning
        case .failed:
            return theme.error
        case .completed:
            return theme.success
        case .idle:
            return nil
        }
    }

    private func nowTitle(for run: WorkflowRun) -> String {
        currentNode(for: run)?.displayTitle ?? "—"
    }

    private func nowSubtitle(for run: WorkflowRun) -> String {
        let elapsed = Date().timeIntervalSince(run.startedAt)
        let formatted = WorkflowElapsedFormatter.format(elapsed)
        switch run.status {
        case .running:
            return "Running · \(formatted)"
        case .awaitingOperator:
            return "Awaiting choice"
        case .idle:
            return "Idle · \(formatted)"
        case .interrupted:
            return "Interrupted · \(formatted)"
        case .failed:
            return "Failed"
        case .completed:
            return "Completed"
        }
    }
}

@MainActor
struct StripCell<Content: View, Actions: View>: View {
    @Environment(\.devysTheme) private var theme

    let label: String
    let tint: Color?
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            HStack(spacing: Spacing.space2) {
                Text(label)
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(tint ?? theme.textTertiary)
                Spacer()
            }
            content
            Spacer(minLength: 0)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 96, alignment: .top)
        .padding(Spacing.space3)
        .elevation(.card)
    }
}

enum WorkflowElapsedFormatter {
    static func format(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
