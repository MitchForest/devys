import AppFeatures
import Foundation
import SwiftUI
import UI
import Workspace

struct ArtifactButton: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let path: String

    init?(
        title: String,
        systemImage: String,
        path: String?
    ) {
        guard let path else { return nil }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        self.id = title
        self.title = title
        self.systemImage = systemImage
        self.path = trimmedPath
    }
}

func reviewTimestampLabel(
    _ date: Date
) -> String {
    reviewDateFormatter.string(from: date)
}

private let reviewDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

func reviewIssueIsOutstanding(
    _ issue: ReviewIssue
) -> Bool {
    switch issue.status {
    case .open:
        true
    case .followUpPrepared:
        false
    case .dismissed, .acceptedRisk, .resolved:
        false
    }
}

extension BuiltInLauncherKind {
    var title: String {
        switch self {
        case .claude:
            "Claude Code"
        case .codex:
            "Codex"
        }
    }
}

extension ReviewTargetKind {
    var title: String {
        switch self {
        case .unstagedChanges:
            "Unstaged"
        case .stagedChanges:
            "Staged"
        case .lastCommit:
            "Last Commit"
        case .currentBranch:
            "Current Branch"
        case .commitRange:
            "Commit Range"
        case .pullRequest:
            "Pull Request"
        case .selection:
            "Selection"
        }
    }
}

extension ReviewTriggerSource {
    var title: String {
        switch self {
        case .manual:
            "Manual"
        case .postCommitHook:
            "On Commit"
        case .pullRequestCommand:
            "PR Command"
        case .pullRequestHook:
            "PR Update"
        case .workspaceOpen:
            "Workspace Open"
        case .scheduled:
            "Scheduled"
        case .remoteHost:
            "Remote Host"
        }
    }
}

extension ReviewRunStatus {
    var icon: String {
        switch self {
        case .queued:
            "clock"
        case .preparing:
            "shippingbox"
        case .running:
            "play.circle.fill"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .cancelled:
            "xmark.circle.fill"
        }
    }

    func tint(
        _ theme: Theme
    ) -> Color {
        switch self {
        case .queued, .preparing:
            theme.textSecondary
        case .running:
            theme.accent
        case .completed:
            theme.success
        case .failed:
            theme.error
        case .cancelled:
            theme.warning
        }
    }
}

extension ReviewOverallRisk {
    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .low:
            "checkmark.shield"
        case .medium:
            "exclamationmark.shield"
        case .high:
            "flame.fill"
        }
    }

    func tint(
        _ theme: Theme
    ) -> Color {
        switch self {
        case .low:
            theme.success
        case .medium:
            theme.warning
        case .high:
            theme.error
        }
    }
}

extension ReviewIssueSeverity {
    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .minor:
            "info.circle"
        case .major:
            "exclamationmark.circle"
        case .critical:
            "exclamationmark.octagon.fill"
        }
    }

    func tint(
        _ theme: Theme
    ) -> Color {
        switch self {
        case .minor:
            theme.textSecondary
        case .major:
            theme.warning
        case .critical:
            theme.error
        }
    }
}

extension ReviewIssueConfidence {
    var title: String {
        "\(rawValue.capitalized) Confidence"
    }
}

extension ReviewIssueStatus {
    var title: String {
        switch self {
        case .open:
            "Open"
        case .dismissed:
            "Dismissed"
        case .acceptedRisk:
            "Accepted"
        case .followUpPrepared:
            "Fix Prepared"
        case .resolved:
            "Resolved"
        }
    }

    var icon: String {
        switch self {
        case .open:
            "circle"
        case .dismissed:
            "eye.slash"
        case .acceptedRisk:
            "shield"
        case .followUpPrepared:
            "terminal"
        case .resolved:
            "checkmark.circle"
        }
    }

    func tint(
        _ theme: Theme
    ) -> Color {
        switch self {
        case .open:
            theme.textSecondary
        case .dismissed:
            theme.textTertiary
        case .acceptedRisk:
            theme.warning
        case .followUpPrepared:
            theme.accent
        case .resolved:
            theme.success
        }
    }
}

extension ReviewIssueLocation {
    var label: String {
        var result = path
        if let line {
            result += ":\(line)"
        }
        if let column {
            result += ":\(column)"
        }
        return result
    }
}
