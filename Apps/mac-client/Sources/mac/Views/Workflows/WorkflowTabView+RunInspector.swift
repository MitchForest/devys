import AppFeatures
import SwiftUI
import UI

extension WorkflowTabView {
    func runInspector(
        for run: WorkflowRun,
        definition: WorkflowDefinition
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                if let selectedNode = selectedWorkflowNode(in: definition) {
                    inspectorNodeDetail(selectedNode, run: run)
                } else if let selectedEdge = selectedWorkflowEdge(in: definition) {
                    inspectorEdgeDetail(selectedEdge, definition: definition, run: run)
                } else {
                    inspectorRunOverview(for: run)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.space4)
        }
        .background(theme.base)
    }

    private func inspectorRunOverview(for run: WorkflowRun) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            sectionTitle("Run Overview")
            workflowFact("Branch", value: run.branchName)
            workflowFact(
                "Started",
                value: run.startedAt.formatted(date: .abbreviated, time: .shortened)
            )
            workflowFact("Attempts", value: "\(run.attempts.count)")

            if !run.attempts.isEmpty {
                sectionSubtitle("Attempts")
                ForEach(run.attempts.reversed()) { attempt in
                    attemptCard(attempt)
                }
            }

            if run.latestPlanSnapshot?.currentPhaseIndex != nil {
                sectionSubtitle("Add Follow-Up")
                followUpForm(for: run)
            }
        }
    }

    private func inspectorNodeDetail(_ node: WorkflowNode, run: WorkflowRun) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            sectionTitle("Node")
            workflowFact("Title", value: node.displayTitle)
            workflowFact("Kind", value: node.kind.displayName)

            let nodeAttempts = run.attempts.filter { $0.nodeID == node.id }
            if !nodeAttempts.isEmpty {
                sectionSubtitle("Attempts for this node")
                ForEach(nodeAttempts.reversed()) { attempt in
                    attemptCard(attempt)
                }
            } else {
                Text("No attempts for this node yet.")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
            }

            HStack(spacing: Spacing.space2) {
                if let terminalID = nodeAttempts.last?.terminalID, terminalID == run.currentTerminalID {
                    ActionButton("Open Terminal", icon: "terminal", style: .ghost, action: onOpenTerminal)
                }
                if nodeAttempts.last?.promptArtifactPath != nil {
                    ActionButton("Open Prompt", icon: "text.append", style: .ghost, action: onOpenPromptArtifact)
                }
            }
        }
    }

    private func inspectorEdgeDetail(
        _ edge: WorkflowEdge,
        definition: WorkflowDefinition,
        run: WorkflowRun
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            sectionTitle("Edge")
            workflowFact("Label", value: edge.displayLabel)
            workflowFact("Route", value: edgeSummary(edge, definition: definition))
            if run.status == .awaitingOperator,
               run.currentNodeID == edge.sourceNodeID {
                ActionButton("Choose This Edge", icon: "arrow.right", style: .primary) {
                    onChooseEdge(edge.id)
                }
            }
        }
    }

    private func attemptCard(_ attempt: WorkflowRunAttempt) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            Text(attemptTitle(attempt))
                .font(Typography.body)
                .foregroundStyle(theme.text)
            Text(attemptSummary(attempt))
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
            Text(attempt.startedAt.formatted(date: .omitted, time: .shortened))
                .font(Typography.micro)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.space3)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
    }

    private func followUpForm(for run: WorkflowRun) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            WorkflowFormField("Section") {
                TextInput("Follow-Ups", text: $followUpSectionTitle)
            }
            WorkflowFormField("Ticket") {
                TextEditorField(text: $followUpText, minHeight: 100, isMonospaced: true)
            }
            ActionButton("Append Ticket", icon: "plus.rectangle.on.rectangle", style: .ghost) {
                let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
                let sectionTitle = followUpSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !sectionTitle.isEmpty else { return }
                onAppendFollowUpTicket(sectionTitle, text)
                followUpText = ""
            }
            .disabled(
                followUpSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Typography.heading)
            .foregroundStyle(theme.text)
    }

    private func sectionSubtitle(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(theme.textSecondary)
            .padding(.top, Spacing.space1)
    }
}
