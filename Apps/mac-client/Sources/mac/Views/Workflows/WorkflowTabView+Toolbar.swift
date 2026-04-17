import AppFeatures
import SwiftUI
import UI

extension WorkflowTabView {
    func toolbar(for definition: WorkflowDefinition) -> some View {
        HStack(alignment: .center, spacing: Spacing.space3) {
            titleBlock(for: definition)
            Spacer(minLength: Spacing.space3)
            modeToggle()
            actions(for: definition)
        }
        .padding(.horizontal, Spacing.space4)
        .padding(.vertical, Spacing.space3)
        .background(theme.base)
    }

    private func titleBlock(for definition: WorkflowDefinition) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(definition.displayName)
                .font(Typography.heading)
                .foregroundStyle(theme.text)
                .lineLimit(1)

            HStack(spacing: Spacing.space2) {
                planPathChip(for: definition)
                if mode == .run, let run {
                    WorkflowRunStatusChip(status: run.status)
                    if let current = currentNode(for: run) {
                        WorkflowMetaChip(
                            title: current.displayTitle,
                            icon: current.kind == .finish
                                ? "flag.checkered"
                                : "point.3.connected.trianglepath.dotted"
                        )
                    }
                    if let phase = run.currentPhaseTitle, !phase.isEmpty {
                        WorkflowMetaChip(title: phase, icon: "flag")
                    }
                }
            }
        }
    }

    private func planPathChip(for definition: WorkflowDefinition) -> some View {
        let trimmed = definition.planFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "No plan file" : trimmed
        let status = planFileStatus(definition)
        return WorkflowMetaChip(title: title, icon: status.icon, tint: status.tint(theme: theme))
    }

    private func planFileStatus(_ definition: WorkflowDefinition) -> WorkflowPlanFileStatus {
        let trimmed = definition.planFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .missing }
        if trimmed.hasPrefix("/") {
            let resolved = URL(fileURLWithPath: trimmed)
            return FileManager.default.fileExists(atPath: resolved.path) ? .valid : .invalid
        }
        // Relative plan paths can't be resolved without workspace context in the view;
        // treat as provisional (not green, not red).
        return .missing
    }

    private func modeToggle() -> some View {
        Picker("Mode", selection: $mode) {
            Text("Design").tag(DisplayMode.design)
            Text("Run").tag(DisplayMode.run)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .labelsHidden()
    }

    @ViewBuilder
    private func actions(for definition: WorkflowDefinition) -> some View {
        HStack(spacing: Spacing.space2) {
            switch mode {
            case .design:
                designActions(for: definition)
            case .run:
                runActions(for: definition)
            }
        }
    }

    @ViewBuilder
    private func designActions(for definition: WorkflowDefinition) -> some View {
        ActionButton("Open Plan", icon: "doc.text", style: .ghost, action: onOpenPlan)
            .disabled(definition.planFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        ActionButton("Delete", icon: "trash", style: .ghost, tone: .destructive) {
            isDeleteDefinitionConfirmationPresented = true
        }
        ActionButton("Run", icon: "play.fill", style: .primary) {
            onStartRun()
            mode = .run
        }
    }

    @ViewBuilder
    private func runActions(for _: WorkflowDefinition) -> some View {
        if let run {
            ActionButton("Terminal", icon: "terminal", style: .ghost, action: onOpenTerminal)
                .disabled(run.currentTerminalID == nil)
            ActionButton("Diff", icon: "plus.forwardslash.minus", style: .ghost, action: onOpenDiff)
                .disabled(!canOpenDiff)
            ActionButton("Prompt", icon: "text.append", style: .ghost, action: onOpenPromptArtifact)
                .disabled(run.latestPromptArtifactPath == nil)
            ActionButton("Plan", icon: "doc.text", style: .ghost, action: onOpenPlan)
                .disabled(
                    definition?.planFilePath
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty != false
                )
            if !run.status.isActive {
                ActionButton("Delete Run", icon: "trash", style: .ghost, tone: .destructive) {
                    isDeleteRunConfirmationPresented = true
                }
            }
            primaryRunAction(for: run)
        } else {
            ActionButton("Run", icon: "play.fill", style: .primary) {
                onStartRun()
            }
        }
    }

    @ViewBuilder
    private func primaryRunAction(for run: WorkflowRun) -> some View {
        switch run.status {
        case .running:
            ActionButton("Stop", icon: "stop.fill", style: .ghost, tone: .destructive, action: onStopRun)
        case .idle, .interrupted:
            ActionButton("Continue", icon: "play.fill", style: .primary, action: onContinueRun)
        case .awaitingOperator:
            EmptyView()
        case .failed, .completed:
            ActionButton("Restart", icon: "arrow.clockwise", style: .primary, action: onRestartRun)
        }
    }
}

enum WorkflowPlanFileStatus {
    case missing
    case invalid
    case valid

    var icon: String {
        switch self {
        case .missing:
            return "doc.badge.ellipsis"
        case .invalid:
            return "exclamationmark.circle.fill"
        case .valid:
            return "checkmark.circle.fill"
        }
    }

    func tint(theme: Theme) -> Color? {
        switch self {
        case .missing:
            return nil
        case .invalid:
            return theme.error
        case .valid:
            return theme.success
        }
    }
}
