import AppFeatures
import Foundation
import SwiftUI
import UI
import Workspace

@MainActor
struct ReviewRunTabView: View {
    @Environment(\.devysTheme) private var theme

    let run: ReviewRun
    let issues: [ReviewIssue]
    let onRerun: () -> Void
    let onOpenArtifact: (String) -> Void
    let onOpenFile: (ReviewIssue) -> Void
    let onDismiss: (ReviewIssue) -> Void
    let onSelectFixHarness: (BuiltInLauncherKind) -> Void
    let onFix: (ReviewIssue, BuiltInLauncherKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.space5) {
                header

                if let lastErrorMessage = run.lastErrorMessage,
                   !lastErrorMessage.isEmpty {
                    errorBanner(message: lastErrorMessage)
                }

                if run.status.isActive && displayedIssues.isEmpty {
                    loadingState
                } else if displayedIssues.isEmpty {
                    EmptyState(
                        icon: emptyStateIcon,
                        title: emptyStateTitle,
                        description: emptyStateDescription
                    )
                    .frame(minHeight: 280)
                } else {
                    issueList
                }
            }
            .padding(Spacing.space4)
        }
        .background(theme.base)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            HStack(alignment: .top, spacing: Spacing.space3) {
                VStack(alignment: .leading, spacing: Spacing.space1) {
                    Text(run.target.displayTitle)
                        .font(Typography.title)
                        .foregroundStyle(theme.text)
                    Text(runSummaryLine)
                        .font(Typography.body)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer(minLength: Spacing.space3)

                HStack(spacing: Spacing.space2) {
                    if !runArtifactButtons.isEmpty {
                        Menu {
                            ForEach(runArtifactButtons) { button in
                                Button {
                                    onOpenArtifact(button.path)
                                } label: {
                                    Label(button.title, systemImage: button.systemImage)
                                }
                            }
                        } label: {
                            ReviewActionLabel(
                                title: "Artifacts",
                                systemImage: "ellipsis.circle",
                                emphasis: .secondary
                            )
                        }
                        .menuStyle(.borderlessButton)
                    }

                    if canRerun {
                        ReviewActionButton(
                            title: "Rerun",
                            systemImage: "arrow.clockwise"
                        ) {
                            onRerun()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.space1) {
                Text(runTimelineLine)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                if let reviewModelLine {
                    Text(reviewModelLine)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Review is still running.")
                .font(Typography.heading)
                .foregroundStyle(theme.text)
            Text("Issues will appear here as soon as the headless audit finishes.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(Spacing.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .stroke(theme.border, lineWidth: Spacing.borderWidth)
        )
    }

    private var issueList: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.space3) {
            ForEach(displayedIssues) { issue in
                ReviewIssueCard(
                    issue: issue,
                    selectedFixHarness: run.profile.followUpHarness,
                    onOpenFile: {
                        onOpenFile(issue)
                    },
                    onDismiss: {
                        onDismiss(issue)
                    },
                    onSelectFixHarness: { harness in
                        onSelectFixHarness(harness)
                    },
                    onFix: {
                        onFix(issue, run.profile.followUpHarness)
                    }
                )
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            HStack(spacing: Spacing.space2) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Review Error")
                    .font(Typography.heading)
            }
            .foregroundStyle(theme.error)

            Text(message)
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(Spacing.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.errorSubtle, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .stroke(theme.error.opacity(0.35), lineWidth: Spacing.borderWidth)
        )
    }

    private var runSummaryLine: String {
        let trigger = run.trigger.source.title
        let audit = run.profile.auditHarness.title
        return "\(run.displayStatus) • \(trigger) • \(audit)"
    }

    private var emptyStateDescription: String {
        if !issues.isEmpty {
            return "All review items in this run are already handled."
        }

        switch run.status {
        case .completed:
            return "The audit completed without producing review items."
        case .failed:
            return "The run did not complete cleanly. Check the error details and raw output."
        case .cancelled:
            return "This review was cancelled before it produced any issues."
        case .queued, .preparing, .running:
            return "This review has not produced issues yet."
        }
    }

    private var displayedIssues: [ReviewIssue] {
        issues.filter(reviewIssueIsOutstanding)
    }

    private var reviewModelLine: String? {
        let trimmed = run.profile.auditModelOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return "Model: \(trimmed)"
    }

    private var canRerun: Bool {
        true
    }

    private var runTimelineLine: String {
        var parts = [
            "Created \(reviewTimestampLabel(run.createdAt))",
            issueSummaryLine
        ]
        if let completedAt = run.completedAt {
            parts.append("Completed \(reviewTimestampLabel(completedAt))")
        }
        return parts.joined(separator: " • ")
    }

    private var issueSummaryLine: String {
        if run.status.isActive {
            return "Review running"
        }
        if displayedIssues.isEmpty, !issues.isEmpty {
            return "All items handled"
        }
        let count = displayedIssues.count
        let suffix = count == 1 ? "item" : "items"
        return "\(count) open \(suffix)"
    }

    private var emptyStateTitle: String {
        if !issues.isEmpty {
            return "All Items Handled"
        }
        return run.status == .completed ? "No Issues Found" : "No Issues Yet"
    }

    private var emptyStateIcon: String {
        if !issues.isEmpty {
            return "checkmark.circle"
        }
        return run.status == .completed ? "checkmark.circle" : "checklist"
    }

    private var runArtifactButtons: [ArtifactButton] {
        [
            ArtifactButton(
                title: "View Input Snapshot",
                systemImage: "doc.text.magnifyingglass",
                path: run.artifactSet.inputSnapshotPath
            ),
            ArtifactButton(
                title: "View Audit Prompt",
                systemImage: "text.quote",
                path: run.artifactSet.auditPromptPath
            ),
            ArtifactButton(
                title: "View Raw Output",
                systemImage: "terminal",
                path: run.artifactSet.rawStdoutPath
            ),
            ArtifactButton(
                title: "View Error Output",
                systemImage: "exclamationmark.bubble",
                path: run.artifactSet.rawStderrPath
            ),
            ArtifactButton(
                title: "View Parsed Result",
                systemImage: "curlybraces",
                path: run.artifactSet.parsedResultPath
            ),
            ArtifactButton(
                title: "View Summary",
                systemImage: "list.bullet.rectangle",
                path: run.artifactSet.renderedSummaryPath
            )
        ]
        .compactMap { $0 }
    }
}

private struct ReviewActionButton: View {
    enum Emphasis {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    var emphasis: Emphasis = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ReviewActionLabel(
                title: title,
                systemImage: systemImage,
                emphasis: emphasis
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewActionLabel: View {
    @Environment(\.devysTheme) private var theme

    let title: String
    let systemImage: String
    let emphasis: ReviewActionButton.Emphasis

    private var foregroundStyle: Color {
        switch emphasis {
        case .primary:
            theme.accent
        case .secondary:
            theme.textSecondary
        }
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(Typography.caption.weight(.semibold))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, Spacing.space2)
            .padding(.vertical, Spacing.space1)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .fill(theme.overlay)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .stroke(theme.border, lineWidth: Spacing.borderWidth)
            )
    }
}

private struct ReviewIssueCard: View {
    @Environment(\.devysTheme) private var theme

    let issue: ReviewIssue
    let selectedFixHarness: BuiltInLauncherKind
    let onOpenFile: () -> Void
    let onDismiss: () -> Void
    let onSelectFixHarness: (BuiltInLauncherKind) -> Void
    let onFix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            header

            Text(issue.summary)
                .font(Typography.body)
                .foregroundStyle(theme.text)

            Text(issue.rationale)
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)

            if let referenceLabel = referenceLabel {
                Button(action: onOpenFile) {
                    HStack(spacing: Spacing.space1) {
                        Image(systemName: referenceIcon)
                        Text(referenceLabel)
                    }
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            actionRow
        }
        .padding(Spacing.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .stroke(theme.border, lineWidth: Spacing.borderWidth)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            Text(headerMetadataLine)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(issue.severity.tint(theme))

            Text(issue.title)
                .font(Typography.heading)
                .foregroundStyle(theme.text)
        }
    }

    private var referenceLabel: String? {
        issue.locations.first?.label ?? issue.paths.first
    }

    private var referenceIcon: String {
        issue.locations.isEmpty ? "doc.text" : "location"
    }

    private var headerMetadataLine: String {
        var parts = [
            issue.severity.title,
            issue.confidence.title
        ]
        if issue.status == .followUpPrepared {
            parts.append(issue.status.title)
        }
        return parts.joined(separator: " • ")
    }

    private var actionRow: some View {
        HStack(spacing: Spacing.space2) {
            ReviewActionButton(
                title: "Dismiss",
                systemImage: "eye.slash",
                emphasis: .secondary
            ) {
                onDismiss()
            }

            ReviewHarnessPicker(
                selection: selectedFixHarness,
                onSelect: onSelectFixHarness
            )

            ReviewActionButton(
                title: "Fix",
                systemImage: "wrench.and.screwdriver"
            ) {
                onFix()
            }
        }
    }
}

private struct ReviewHarnessPicker: View {
    @Environment(\.devysTheme) private var theme

    let selection: BuiltInLauncherKind
    let onSelect: (BuiltInLauncherKind) -> Void

    var body: some View {
        Menu {
            ForEach(BuiltInLauncherKind.allCases, id: \.self) { harness in
                Button {
                    onSelect(harness)
                } label: {
                    if harness == selection {
                        Label(harness.title, systemImage: "checkmark")
                    } else {
                        Text(harness.title)
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.space1) {
                Text(selection.title)
                    .font(Typography.caption.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(Typography.micro.weight(.semibold))
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, Spacing.space2)
            .padding(.vertical, Spacing.space1)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .fill(theme.overlay)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .stroke(theme.border, lineWidth: Spacing.borderWidth)
            )
        }
        .menuStyle(.borderlessButton)
    }
}
