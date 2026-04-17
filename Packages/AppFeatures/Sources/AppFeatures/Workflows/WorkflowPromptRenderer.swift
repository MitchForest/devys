import Foundation

public enum WorkflowPromptRenderer {
    public static func renderPrompt(
        definition: WorkflowDefinition,
        node: WorkflowNode,
        worker: WorkflowWorker,
        snapshot: WorkflowPlanSnapshot?
    ) -> String {
        let artifactLines = definition.artifactBindings.map { binding in
            "- \(binding.kind.rawValue.capitalized): \(binding.path)"
        }
        let artifactSection = artifactLines.isEmpty
            ? "None."
            : artifactLines.joined(separator: "\n")

        let phaseTitle = snapshot?.currentPhase?.title ?? "No Active Phase"
        let ticketLines = snapshot?.currentPhase?.openTickets.enumerated().map { offset, ticket in
            "\(offset + 1). [\(ticket.section.displayName)] \(ticket.text)"
        } ?? []
        let planSection = ticketLines.isEmpty
            ? "No open tickets remain in the active phase."
            : ticketLines.joined(separator: "\n")

        let promptBody: String
        if let override = node.promptOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            promptBody = override
        } else {
            promptBody = worker.prompt
        }

        return """
        Workflow: \(definition.displayName)
        Node: \(node.displayTitle)
        Node kind: \(node.kind.displayName)
        Worker: \(worker.resolvedDisplayName)
        Plan file: \(snapshot?.planFilePath ?? "Not bound")
        Active phase: \(phaseTitle)

        Bound artifacts:
        \(artifactSection)

        Open tickets in the active phase:
        \(planSection)

        Instructions:
        \(promptBody)
        """
    }
}
