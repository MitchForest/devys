import ChatCore

public extension MessageBlock {
    /// SF Symbol icon name for this block kind.
    var iconName: String {
        switch kind {
        case .toolCall: return "wrench.fill"
        case .patch, .diff: return "doc.badge.plus"
        case .hunkList: return "text.badge.plus"
        case .plan: return "list.bullet.clipboard"
        case .todoList: return "checklist"
        case .userInputRequest: return "questionmark.circle.fill"
        case .reasoning: return "brain"
        case .systemStatus: return "info.circle.fill"
        case .fileSnippet: return "doc.text"
        case .gitCommitSummary: return "arrow.triangle.branch"
        case .pullRequestSummary: return "arrow.triangle.pull"
        }
    }

    /// Human-readable label for this block kind.
    var kindLabel: String {
        switch kind {
        case .toolCall: return "Tool Call"
        case .patch: return "Patch"
        case .diff: return "Diff"
        case .hunkList: return "Changes"
        case .plan: return "Plan"
        case .todoList: return "Tasks"
        case .userInputRequest: return "Input Required"
        case .reasoning: return "Thinking"
        case .systemStatus: return "Status"
        case .fileSnippet: return "File"
        case .gitCommitSummary: return "Commit"
        case .pullRequestSummary: return "Pull Request"
        }
    }

    /// Extract the approval request ID from a tool call block, if present.
    var approvalRequestID: String? {
        guard kind == .toolCall else { return nil }
        return payload?["approvalRequestId"]?.stringValue
            ?? payload?["requestId"]?.stringValue
    }

    /// Extract the user input request ID from a user input block, if present.
    var userInputRequestID: String? {
        guard kind == .userInputRequest else { return nil }
        return payload?["requestId"]?.stringValue
    }

    /// Extract the user input prompt, if present.
    var userInputPrompt: String? {
        guard kind == .userInputRequest else { return nil }
        return summary ?? payload?["prompt"]?.stringValue
    }
}
