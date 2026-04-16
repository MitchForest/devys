// WorkspacePortStore+Lifecycle.swift
// Devys - Lifecycle and logging helpers for scoped workspace port refreshes.

import AppFeatures
import Foundation
import Workspace

@MainActor
extension WorkspacePortStore {
    func refresh(
        workspaceIDs: [Workspace.ID],
        reason: RefreshReason
    ) {
        guard isActiveRepository else { return }
        let now = Date()
        let shouldDedup = reason == .selectedPeriodic || reason == .backgroundPeriodic
        let filteredWorkspaceIDs = workspaceIDs
            .filter { worktreesByID[$0] != nil }
            .filter { workspaceID in
                guard shouldDedup else { return true }
                guard let lastRefresh = lastRefreshByWorkspace[workspaceID] else { return true }
                return now.timeIntervalSince(lastRefresh) >= configuration.refreshDedupInterval
            }

        guard !filteredWorkspaceIDs.isEmpty else { return }

        // If a refresh is already in flight, queue these workspace IDs for
        // a follow-up refresh instead of cancelling the running scan.
        if refreshTask != nil {
            enqueuePendingRefresh(
                WorkspacePortRefreshRequest(
                    reason: reason,
                    workspaceIDs: filteredWorkspaceIDs.sorted()
                )
            )
            return
        }

        executeRefresh(workspaceIDs: filteredWorkspaceIDs, reason: reason, now: now)
    }

    func executeRefresh(
        workspaceIDs: [Workspace.ID],
        reason: RefreshReason,
        now: Date
    ) {
        let filteredWorkspaceIDs = workspaceIDs.filter { worktreesByID[$0] != nil }
        guard !filteredWorkspaceIDs.isEmpty else {
            drainPendingRefresh()
            return
        }

        let context = WorkspacePortObservationContext(
            worktreesByID: worktreesByID.filtered(to: filteredWorkspaceIDs),
            managedProcessesByWorkspace: managedProcessesByWorkspace.filtered(to: filteredWorkspaceIDs)
        )
        let refreshStart = Date()

        for workspaceID in filteredWorkspaceIDs {
            lastRefreshByWorkspace[workspaceID] = now
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await snapshotProvider.snapshot(context: context)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                var updatedPortsByWorkspace = self.portsByWorkspace
                for workspaceID in filteredWorkspaceIDs {
                    updatedPortsByWorkspace.removeValue(forKey: workspaceID)
                }
                for (workspaceID, ports) in snapshot where self.worktreesByID[workspaceID] != nil {
                    updatedPortsByWorkspace[workspaceID] = ports
                }
                self.portsByWorkspace = updatedPortsByWorkspace
                self.refreshTask = nil
                self.recordRefresh(
                    reason: reason,
                    workspaceIDs: filteredWorkspaceIDs.sorted(),
                    startedAt: refreshStart
                )
                self.drainPendingRefresh()
            }
        }
    }

    func drainPendingRefresh() {
        guard !pendingRefreshRequests.isEmpty else { return }
        let request = pendingRefreshRequests.removeFirst()
        executeRefresh(workspaceIDs: request.workspaceIDs, reason: request.reason, now: Date())
    }

    func updatePeriodicRefresh(isActive: Bool) {
        if !isActive {
            selectedPeriodicTask?.cancel()
            selectedPeriodicTask = nil
            backgroundPeriodicTask?.cancel()
            backgroundPeriodicTask = nil
            refreshTask?.cancel()
            refreshTask = nil
            pendingRefreshRequests.removeAll()
            return
        }

        guard selectedPeriodicTask == nil else { return }
        selectedPeriodicTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(configuration.selectedRefreshInterval * 1_000_000_000)
                )
                if Task.isCancelled { break }
                await MainActor.run {
                    guard let selectedWorktreeId = self.selectedWorktreeId else { return }
                    self.refresh(workspaceIDs: [selectedWorktreeId], reason: .selectedPeriodic)
                }
            }
        }

        guard backgroundPeriodicTask == nil else { return }
        backgroundPeriodicTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(configuration.backgroundRefreshInterval * 1_000_000_000)
                )
                if Task.isCancelled { break }
                await MainActor.run {
                    guard let backgroundWorkspaceID = self.nextBackgroundRefreshWorkspaceID() else {
                        return
                    }
                    self.refresh(
                        workspaceIDs: [backgroundWorkspaceID],
                        reason: .backgroundPeriodic
                    )
                }
            }
        }
    }

    func managedProcessRefreshRequests(
        from previous: [Workspace.ID: [ManagedWorkspaceProcess]],
        to next: [Workspace.ID: [ManagedWorkspaceProcess]]
    ) -> [WorkspacePortRefreshRequest] {
        let previousWorkspaceIDs = Set(previous.keys)
        let nextWorkspaceIDs = Set(next.keys)
        let allWorkspaceIDs = previousWorkspaceIDs.union(nextWorkspaceIDs)
        var launchWorkspaceIDs: [Workspace.ID] = []
        var exitWorkspaceIDs: [Workspace.ID] = []
        var contextWorkspaceIDs: [Workspace.ID] = []

        for workspaceID in allWorkspaceIDs.sorted() {
            let previousProcessIDs = Set(previous[workspaceID]?.map(\.processID) ?? [])
            let nextProcessIDs = Set(next[workspaceID]?.map(\.processID) ?? [])
            let inserted = nextProcessIDs.subtracting(previousProcessIDs)
            let removed = previousProcessIDs.subtracting(nextProcessIDs)

            guard !inserted.isEmpty || !removed.isEmpty else { continue }

            if !inserted.isEmpty, removed.isEmpty {
                launchWorkspaceIDs.append(workspaceID)
            } else if inserted.isEmpty, !removed.isEmpty {
                exitWorkspaceIDs.append(workspaceID)
            } else {
                contextWorkspaceIDs.append(workspaceID)
            }
        }

        var requests: [WorkspacePortRefreshRequest] = []
        if !launchWorkspaceIDs.isEmpty {
            requests.append(
                WorkspacePortRefreshRequest(
                    reason: .managedProcessLaunch,
                    workspaceIDs: launchWorkspaceIDs
                )
            )
        }
        if !exitWorkspaceIDs.isEmpty {
            requests.append(
                WorkspacePortRefreshRequest(
                    reason: .managedProcessExit,
                    workspaceIDs: exitWorkspaceIDs
                )
            )
        }
        if !contextWorkspaceIDs.isEmpty {
            requests.append(
                WorkspacePortRefreshRequest(
                    reason: .contextChange,
                    workspaceIDs: contextWorkspaceIDs
                )
            )
        }

        return requests
    }

    func enqueuePendingRefresh(_ request: WorkspacePortRefreshRequest) {
        if let index = pendingRefreshRequests.firstIndex(where: { $0.reason == request.reason }) {
            let mergedWorkspaceIDs = Array(
                Set(pendingRefreshRequests[index].workspaceIDs).union(request.workspaceIDs)
            ).sorted()
            pendingRefreshRequests[index] = WorkspacePortRefreshRequest(
                reason: request.reason,
                workspaceIDs: mergedWorkspaceIDs
            )
            return
        }

        pendingRefreshRequests.append(request)
    }

    func recordRefresh(
        reason: RefreshReason,
        workspaceIDs: [Workspace.ID],
        startedAt: Date
    ) {
        let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let record = WorkspacePortRefreshRecord(
            reason: reason,
            workspaceIDs: workspaceIDs,
            workspaceCount: workspaceIDs.count
        )
        refreshRecords.append(record)
        let message =
            "refresh reason=\(reason.rawValue) " +
            "workspaces=\(record.workspaceCount) " +
            "duration_ms=\(durationMilliseconds)"
        Self.logger.debug("\(message, privacy: .public)")
    }

    func nextBackgroundRefreshWorkspaceID() -> Workspace.ID? {
        let candidateIDs = worktreesByID.keys.sorted().filter { workspaceID in
            workspaceID != selectedWorktreeId
        }
        guard !candidateIDs.isEmpty else { return nil }
        if backgroundRefreshCursor >= candidateIDs.count {
            backgroundRefreshCursor = 0
        }
        let workspaceID = candidateIDs[backgroundRefreshCursor]
        backgroundRefreshCursor = (backgroundRefreshCursor + 1) % candidateIDs.count
        return workspaceID
    }
}
