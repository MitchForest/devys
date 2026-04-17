import AppFeatures
import SwiftUI
import UI

extension WorkflowTabView {
    func workflowFact(
        _ title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(Typography.body)
                .foregroundStyle(theme.text)
        }
    }

    func currentNode(for run: WorkflowRun) -> WorkflowNode? {
        guard let definition, let currentNodeID = run.currentNodeID else { return nil }
        return definition.node(id: currentNodeID)
    }

    func statusSummary(for run: WorkflowRun) -> String {
        switch run.status {
        case .running:
            return "The active node is running in a terminal tab. Open that terminal to steer."
        case .idle:
            return "The run is ready to launch the current node."
        case .awaitingOperator:
            return "The last node finished. Choose the next edge to continue."
        case .interrupted:
            return "The run was interrupted. Continue to relaunch the current node."
        case .failed(let message):
            return message.isEmpty ? "The run failed." : message
        case .completed:
            return "The workflow reached a terminal node."
        }
    }

    func attemptTitle(_ attempt: WorkflowRunAttempt) -> String {
        definition?.node(id: attempt.nodeID)?.displayTitle ?? attempt.nodeID
    }

    func attemptSummary(_ attempt: WorkflowRunAttempt) -> String {
        switch attempt.status {
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .interrupted:
            return "Interrupted"
        case .failed(let message):
            return message.isEmpty ? "Failed" : message
        }
    }

    func color(for level: WorkflowRunEventLevel) -> Color {
        switch level {
        case .info:
            theme.accent
        case .warning:
            theme.warning
        case .error:
            theme.error
        }
    }
}
