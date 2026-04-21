import AppFeatures
import SwiftUI
import UI

@MainActor
struct ReviewSidebarSectionView: View {
    @Environment(\.devysTheme) private var theme

    let reviewState: WindowFeature.ReviewWorkspaceState
    let onOpenRun: (UUID) -> Void
    let onDeleteRun: (UUID) -> Void

    @State private var pendingDeleteRunID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            if displayedRuns.isEmpty {
                Text("No reviews need attention for this workspace.")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, Spacing.space3)
                    .padding(.vertical, 4)
            } else {
                if !activeRuns.isEmpty {
                    runSection(title: "Active", runs: activeRuns)
                }

                if !attentionRuns.isEmpty {
                    runSection(title: activeRuns.isEmpty ? "Needs Attention" : "Attention", runs: attentionRuns)
                }
            }
        }
        .padding(.horizontal, Spacing.space3)
        .padding(.bottom, Spacing.space3)
        .alert("Remove Review?", isPresented: deleteConfirmationBinding) {
            Button("Remove Review", role: .destructive) {
                guard let pendingDeleteRunID else { return }
                onDeleteRun(pendingDeleteRunID)
                self.pendingDeleteRunID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteRunID = nil
            }
        } message: {
            Text("This removes the saved review run and artifacts from Devys.")
        }
    }

    private var activeRuns: [ReviewRun] {
        Array(actionableRuns.filter { $0.status.isActive }.prefix(3))
    }

    private var attentionRuns: [ReviewRun] {
        Array(
            actionableRuns
                .filter { !$0.status.isActive }
                .prefix(max(0, 6 - activeRuns.count))
        )
    }

    private var actionableRuns: [ReviewRun] {
        reviewState.runs.filter(reviewRunNeedsAttention)
    }

    private var displayedRuns: [ReviewRun] {
        activeRuns + attentionRuns
    }

    private func runSection(
        title: String,
        runs: [ReviewRun]
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            Text(title)
                .font(Typography.micro.weight(.semibold))
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, Spacing.space1)

            ForEach(runs) { run in
                runRow(run)
            }
        }
    }

    private func runRow(
        _ run: ReviewRun
    ) -> some View {
        Button {
            onOpenRun(run.id)
        } label: {
            HStack(alignment: .top, spacing: Spacing.space2) {
                StatusDot(statusDotStatus(for: run))
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.space2) {
                        Text(run.target.displayTitle)
                            .font(Typography.body)
                            .foregroundStyle(theme.text)
                            .lineLimit(1)

                        Spacer(minLength: Spacing.space2)

                        Text(reviewSidebarTimestamp(for: run))
                            .font(Typography.micro)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }

                    Text(runSubtitle(for: run))
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space3)
            .background(theme.card)
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .stroke(theme.border, lineWidth: Spacing.borderWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open Review") {
                onOpenRun(run.id)
            }
            Divider()
            Button("Remove Review…", role: .destructive) {
                pendingDeleteRunID = run.id
            }
        }
    }

    private func reviewTriggerLabel(
        for source: ReviewTriggerSource
    ) -> String {
        switch source {
        case .manual:
            "Manual"
        case .postCommitHook:
            "Post-Commit"
        case .pullRequestCommand:
            "PR"
        case .pullRequestHook:
            "PR Auto"
        case .workspaceOpen:
            "Workspace"
        case .scheduled:
            "Scheduled"
        case .remoteHost:
            "Remote"
        }
    }

    private func runSubtitle(
        for run: ReviewRun
    ) -> String {
        if run.status.isActive {
            return "\(run.displayStatus) • \(reviewTriggerLabel(for: run.trigger.source))"
        }

        let statusSummary: String
        if run.status == .failed {
            statusSummary = "Review failed"
        } else if run.issueCounts.open > 0 {
            let count = run.issueCounts.open
            let suffix = count == 1 ? "open item" : "open items"
            statusSummary = "\(count) \(suffix)"
        } else {
            statusSummary = run.displayStatus
        }

        return "\(statusSummary) • \(reviewTriggerLabel(for: run.trigger.source))"
    }

    private func statusDotStatus(
        for run: ReviewRun
    ) -> StatusDot.Status {
        switch run.status {
        case .queued, .preparing:
            .waiting
        case .running:
            .running
        case .completed, .cancelled:
            .complete
        case .failed:
            .error
        }
    }
}

@MainActor
private func reviewSidebarTimestamp(
    for run: ReviewRun
) -> String {
    let referenceDate = run.completedAt ?? run.startedAt ?? run.createdAt
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: referenceDate, relativeTo: Date())
}

private extension ReviewSidebarSectionView {
    var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteRunID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteRunID = nil
                }
            }
        )
    }

    func reviewRunNeedsAttention(
        _ run: ReviewRun
    ) -> Bool {
        run.status.isActive || run.status == .failed || run.issueCounts.open > 0
    }
}
