// PRListView.swift
// View for listing pull requests.

import SwiftUI
import UI

/// View for listing pull requests.
@MainActor
struct PRListView: View {
    @Environment(\.devysTheme) private var theme
    @Bindable var store: GitStore
    
    @State private var prs: [PullRequest] = []
    @State private var stateFilter: PRStateFilter = .open
    @State private var isLoading: Bool = false
    @State private var showingCreatePR: Bool = false
    
    init(store: GitStore) {
        self.store = store
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            if !store.isRepositoryAvailable {
                gitUnavailableView
            } else if !store.isPRAvailable {
                ghNotAvailableView
            } else if isLoading && prs.isEmpty {
                loadingView
            } else if prs.isEmpty {
                emptyStateView
            } else {
                prListContent
            }
        }
        .task {
            await store.checkPRAvailability()
            if store.isPRAvailable {
                await loadPRs()
            }
        }
        .sheet(isPresented: $showingCreatePR) {
            CreatePRSheet(store: store) { _ in
                Task { await loadPRs() }
            }
        }
    }

    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text("Pull Requests")
                .font(.headline)
            
            Spacer()
            
            // State filter
            Picker("State", selection: $stateFilter) {
                Text("Open").tag(PRStateFilter.open)
                Text("Closed").tag(PRStateFilter.closed)
                Text("All").tag(PRStateFilter.all)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .onChange(of: stateFilter) { _, _ in
                Task { await loadPRs() }
            }
            
            Button {
                Task { await loadPRs() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            
            Button {
                showingCreatePR = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - PR List
    
    private var prListContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(prs) { pr in
                    prRow(pr)
                }
            }
        }
    }
    
    private func prRow(_ pr: PullRequest) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // PR icon
            prIcon(pr)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(pr.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)

                prMetadataRow(pr)
                prBranchRow(pr)
            }
            
            Spacer()
            
            prStatusColumn(pr)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(store.selectedPR?.id == pr.id ? theme.accentMuted : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await store.selectPR(pr) }
        }
    }
    
    private func prIcon(_ pr: PullRequest) -> some View {
        Image(systemName: prIconName(pr))
            .font(.system(size: 14))
            .foregroundStyle(prIconColor(pr))
            .frame(width: 20)
    }

    private func prMetadataRow(_ pr: PullRequest) -> some View {
        HStack(spacing: 8) {
            Text("#\(pr.number)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("•")
                .foregroundStyle(.tertiary)

            Text(pr.author)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text("•")
                .foregroundStyle(.tertiary)

            Text(pr.relativeCreatedAt)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func prBranchRow(_ pr: PullRequest) -> some View {
        HStack(spacing: 4) {
            Text(pr.headBranch)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.accent)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)

            Text(pr.baseBranch)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func prStatusColumn(_ pr: PullRequest) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let checks = pr.checksStatus {
                checksIndicator(checks)
            }

            if let review = pr.reviewDecision {
                reviewIndicator(review)
            }

            HStack(spacing: 4) {
                Text("+\(pr.additions)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green)

                Text("-\(pr.deletions)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
    }
    
    private func prIconName(_ pr: PullRequest) -> String {
        switch pr.state {
        case .open:
            return pr.isDraft ? "circle.dotted" : "arrow.triangle.pull"
        case .merged:
            return "arrow.triangle.merge"
        case .closed:
            return "xmark.circle"
        }
    }
    
    private func prIconColor(_ pr: PullRequest) -> Color {
        switch pr.state {
        case .open:
            return pr.isDraft ? .secondary : .green
        case .merged:
            return .purple
        case .closed:
            return .red
        }
    }
    
    private func checksIndicator(_ status: ChecksStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: checksIconName(status))
                .font(.system(size: 10))
            Text(checksLabel(status))
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(checksColor(status))
    }
    
    private func checksIconName(_ status: ChecksStatus) -> String {
        switch status {
        case .passing: return "checkmark.circle.fill"
        case .failing: return "xmark.circle.fill"
        case .pending: return "clock.fill"
        }
    }
    
    private func checksLabel(_ status: ChecksStatus) -> String {
        switch status {
        case .passing: return "Passing"
        case .failing: return "Failing"
        case .pending: return "Pending"
        }
    }
    
    private func checksColor(_ status: ChecksStatus) -> Color {
        switch status {
        case .passing: return .green
        case .failing: return .red
        case .pending: return .orange
        }
    }
    
    private func reviewIndicator(_ decision: ReviewDecision) -> some View {
        HStack(spacing: 4) {
            Image(systemName: reviewIconName(decision))
                .font(.system(size: 10))
            Text(reviewLabel(decision))
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(reviewColor(decision))
    }
    
    private func reviewIconName(_ decision: ReviewDecision) -> String {
        switch decision {
        case .approved: return "checkmark.seal.fill"
        case .changesRequested: return "exclamationmark.bubble.fill"
        case .reviewRequired: return "person.crop.circle.badge.questionmark"
        }
    }
    
    private func reviewLabel(_ decision: ReviewDecision) -> String {
        switch decision {
        case .approved: return "Approved"
        case .changesRequested: return "Changes"
        case .reviewRequired: return "Review needed"
        }
    }
    
    private func reviewColor(_ decision: ReviewDecision) -> Color {
        switch decision {
        case .approved: return .green
        case .changesRequested: return .orange
        case .reviewRequired: return .secondary
        }
    }
    
    // MARK: - Empty States
    
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading pull requests...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            
            Text("No Pull Requests")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("No \(stateFilter.rawValue) pull requests found.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Button("Create Pull Request") {
                showingCreatePR = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var ghNotAvailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            
            Text("GitHub CLI Not Available")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Install and authenticate the GitHub CLI to manage pull requests.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let url = URL(string: "https://cli.github.com") {
                Link("Install GitHub CLI", destination: url)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func loadPRs() async {
        isLoading = true
        prs = await store.loadPRs(state: stateFilter)
        isLoading = false
    }
}

private extension PRListView {
    var gitUnavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("Git Not Initialized")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Initialize Git for this project before using pull requests.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Initialize Git") {
                Task {
                    await store.initializeRepository()
                    await store.checkPRAvailability()
                    if store.isPRAvailable {
                        await loadPRs()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
