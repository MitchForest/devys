// WorktreeManager.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

/// Manages worktree state, selection, and persistence.
@MainActor
@Observable
public final class WorktreeManager {
    /// All known worktrees for the current repository root.
    public private(set) var worktrees: [Worktree] = []

    /// Persistent state for each worktree.
    public private(set) var statesById: [Worktree.ID: WorktreeState] = [:]

    /// Current worktree selection.
    public private(set) var selection: WorktreeSelection

    /// The repository root associated with the current list.
    public private(set) var repositoryRoot: URL?

    /// Whether the manager is currently refreshing.
    public private(set) var isLoading = false

    private let persistenceService: WorktreePersistenceService
    private let listingService: any WorktreeListingService

    public init(
        persistenceService: WorktreePersistenceService = UserDefaultsWorktreePersistenceService(),
        listingService: any WorktreeListingService
    ) {
        self.persistenceService = persistenceService
        self.listingService = listingService
        self.selection = persistenceService.loadSelection()
        let states = persistenceService.loadStates()
        self.statesById = Dictionary(uniqueKeysWithValues: states.map { ($0.worktreeId, $0) })
    }

    /// Refreshes the worktree list for a repository root.
    public func refresh(for repositoryRoot: URL?) async {
        self.repositoryRoot = repositoryRoot
        guard let repositoryRoot else {
            worktrees = []
            updateSelectionIfNeeded()
            return
        }
        isLoading = true
        defer { isLoading = false }

        let updatedWorktrees: [Worktree]
        do {
            updatedWorktrees = try await listingService.listWorktrees(for: repositoryRoot)
        } catch {
            updatedWorktrees = []
        }

        if updatedWorktrees.isEmpty {
            worktrees = [
                Worktree(
                    workingDirectory: repositoryRoot,
                    repositoryRootURL: repositoryRoot,
                    name: repositoryRoot.lastPathComponent,
                    detail: "."
                )
            ]
        } else {
            worktrees = updatedWorktrees
        }

        mergeStates()
        updateSelectionIfNeeded()
    }

    /// Returns the currently selected worktree, if any.
    public var selectedWorktree: Worktree? {
        guard let id = selection.selectedWorktreeId else { return nil }
        return worktrees.first { $0.id == id }
    }

    /// Returns ordered worktrees excluding archived entries.
    public var orderedWorktrees: [Worktree] {
        visibleWorktrees(from: worktrees)
    }

    /// Returns archived worktrees only.
    public var archivedWorktrees: [Worktree] {
        archivedWorktrees(from: worktrees)
    }

    /// Updates the selected worktree.
    public func selectWorktree(_ worktreeId: Worktree.ID?) {
        selection.selectedWorktreeId = worktreeId
        persistenceService.saveSelection(selection)
        if let worktreeId {
            updateState(worktreeId: worktreeId) { state in
                state.lastFocused = Date()
            }
        }
    }

    /// Updates pin state for a worktree.
    public func setPinned(_ worktreeId: Worktree.ID, isPinned: Bool) {
        updateState(worktreeId: worktreeId) { state in
            state.isPinned = isPinned
        }
    }

    /// Updates archive state for a worktree.
    public func setArchived(_ worktreeId: Worktree.ID, isArchived: Bool) {
        updateState(worktreeId: worktreeId) { state in
            state.isArchived = isArchived
        }
        updateSelectionIfNeeded()
    }

    /// Updates the explicit order for a worktree.
    public func setOrder(_ worktreeId: Worktree.ID, order: Int?) {
        updateState(worktreeId: worktreeId) { state in
            state.order = order
        }
    }

    /// Assigns an agent name to a worktree.
    public func setAssignedAgent(_ worktreeId: Worktree.ID, name: String?) {
        updateState(worktreeId: worktreeId) { state in
            state.assignedAgentName = name
        }
    }

    /// Updates the display name override for a worktree.
    public func setDisplayNameOverride(_ value: String?, for worktreeId: Worktree.ID) {
        updateState(worktreeId: worktreeId) { state in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            state.displayNameOverride = (trimmed?.isEmpty == false) ? trimmed : nil
        }
    }

    /// Returns persisted state for a worktree, if any.
    public func state(for worktreeId: Worktree.ID) -> WorktreeState? {
        statesById[worktreeId]
    }

    /// Returns the user-visible display name for a worktree.
    public func displayName(for worktree: Worktree) -> String {
        let override = statesById[worktree.id]?.displayNameOverride?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let override, !override.isEmpty {
            return override
        }
        return worktree.name
    }

    /// Returns ordered visible worktrees for any repository slice.
    public func visibleWorktrees(from worktrees: [Worktree]) -> [Worktree] {
        orderedWorktrees(from: worktrees, includeArchived: false)
    }

    /// Returns ordered archived worktrees for any repository slice.
    public func archivedWorktrees(from worktrees: [Worktree]) -> [Worktree] {
        orderedWorktrees(from: worktrees, includeArchived: true).filter {
            statesById[$0.id]?.isArchived == true
        }
    }

    /// Removes persisted state for a worktree.
    public func removeState(for worktreeId: Worktree.ID) {
        statesById.removeValue(forKey: worktreeId)
        if selection.selectedWorktreeId == worktreeId {
            selection.selectedWorktreeId = nil
            persistenceService.saveSelection(selection)
        }
        persistStates()
    }

    private func orderedWorktrees(from worktrees: [Worktree], includeArchived: Bool) -> [Worktree] {
        let entries = worktrees.compactMap { worktree -> (Worktree, WorktreeState)? in
            let state = statesById[worktree.id] ?? WorktreeState(worktreeId: worktree.id)
            if !includeArchived && state.isArchived { return nil }
            return (worktree, state)
        }

        return entries.sorted { lhs, rhs in
            let left = sortKey(for: lhs.0, state: lhs.1)
            let right = sortKey(for: rhs.0, state: rhs.1)
            if left.pinned != right.pinned { return left.pinned < right.pinned }
            if left.order != right.order { return left.order < right.order }
            if left.lastFocused != right.lastFocused { return left.lastFocused > right.lastFocused }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
        .map { $0.0 }
    }

    private func sortKey(for worktree: Worktree, state: WorktreeState) -> (
        pinned: Int,
        order: Int,
        lastFocused: TimeInterval,
        name: String
    ) {
        let pinned = state.isPinned ? 0 : 1
        let order = state.order ?? Int.max
        let lastFocused = state.lastFocused?.timeIntervalSince1970 ?? 0
        return (pinned: pinned, order: order, lastFocused: lastFocused, name: displayName(for: worktree))
    }

    private func mergeStates() {
        var merged = statesById
        for worktree in worktrees {
            merged[worktree.id] = merged[worktree.id] ?? WorktreeState(worktreeId: worktree.id)
        }
        statesById = merged
        persistStates()
    }

    private func updateSelectionIfNeeded() {
        let validIds = Set(worktrees.map(\Worktree.id))
        if let selected = selection.selectedWorktreeId, validIds.contains(selected) {
            if statesById[selected]?.isArchived == true {
                selection.selectedWorktreeId = visibleWorktrees(from: worktrees).first?.id
                persistenceService.saveSelection(selection)
            }
            return
        }
        let defaultId = visibleWorktrees(from: worktrees).first?.id
        selection.selectedWorktreeId = defaultId
        persistenceService.saveSelection(selection)
    }

    private func updateState(
        worktreeId: Worktree.ID,
        update: (inout WorktreeState) -> Void
    ) {
        var state = statesById[worktreeId] ?? WorktreeState(worktreeId: worktreeId)
        update(&state)
        statesById[worktreeId] = state
        persistStates()
    }

    private func persistStates() {
        let states = Array(statesById.values)
        persistenceService.saveStates(states)
    }
}
