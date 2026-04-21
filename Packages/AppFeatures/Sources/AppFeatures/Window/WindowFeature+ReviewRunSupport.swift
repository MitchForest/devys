import Foundation

func reviewIssueNeedsAttention(
    _ issue: ReviewIssue
) -> Bool {
    issue.status == .open
}

func reviewRunNeedsAttention(
    _ run: ReviewRun
) -> Bool {
    run.status.isActive || run.status == .failed || run.issueCounts.open > 0
}

func reviewRunShouldPersist(
    _ run: ReviewRun
) -> Bool {
    reviewRunNeedsAttention(run)
}

func upsertReviewRun(
    _ run: ReviewRun,
    in workspaceState: inout WindowFeature.ReviewWorkspaceState
) {
    if let index = workspaceState.runs.firstIndex(where: { $0.id == run.id }) {
        workspaceState.runs[index] = run
    } else {
        workspaceState.runs.append(run)
    }
}

func normalizedReviewIssues(
    _ issues: [ReviewIssue],
    runID: UUID
) -> [ReviewIssue] {
    issues.map { issue in
        var normalized = issue
        normalized.runID = runID
        return normalized
    }
}

func reviewIssueSort(
    _ lhs: ReviewIssue,
    _ rhs: ReviewIssue
) -> Bool {
    let lhsSeverity = reviewSeverityRank(lhs.severity)
    let rhsSeverity = reviewSeverityRank(rhs.severity)
    if lhsSeverity != rhsSeverity {
        return lhsSeverity > rhsSeverity
    }

    if lhs.status != rhs.status {
        return reviewIssueStatusRank(lhs.status) < reviewIssueStatusRank(rhs.status)
    }

    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
}

func reviewSeverityRank(
    _ severity: ReviewIssueSeverity
) -> Int {
    switch severity {
    case .critical:
        3
    case .major:
        2
    case .minor:
        1
    }
}

func reviewIssueStatusRank(
    _ status: ReviewIssueStatus
) -> Int {
    switch status {
    case .open:
        0
    case .followUpPrepared:
        1
    case .acceptedRisk:
        2
    case .dismissed:
        3
    case .resolved:
        4
    }
}

func reviewIssueCounts(
    from issues: [ReviewIssue]
) -> ReviewIssueCounts {
    ReviewIssueCounts(
        total: issues.count,
        open: issues.filter(reviewIssueNeedsAttention).count,
        dismissed: issues.filter { $0.status == .dismissed }.count,
        acceptedRisk: issues.filter { $0.status == .acceptedRisk }.count,
        resolved: issues.filter { $0.status == .resolved }.count,
        critical: issues.filter { $0.severity == .critical }.count,
        major: issues.filter { $0.severity == .major }.count,
        minor: issues.filter { $0.severity == .minor }.count
    )
}

func reviewOverallRisk(
    from issues: [ReviewIssue]
) -> ReviewOverallRisk? {
    if issues.contains(where: { $0.severity == .critical }) {
        return .high
    }

    if issues.contains(where: { $0.severity == .major }) {
        return .medium
    }

    return issues.isEmpty ? nil : .low
}
