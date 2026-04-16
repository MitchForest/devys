// WorkspacePortStore.swift
// Devys - Workspace-owned port detection and summaries.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Foundation
import Observation
import OSLog
import Workspace

struct WorkspacePortObservationContext: Sendable {
    let worktreesByID: [Workspace.ID: Worktree]
    let managedProcessesByWorkspace: [Workspace.ID: [ManagedWorkspaceProcess]]
}

protocol WorkspacePortSnapshotProvider: Sendable {
    func snapshot(context: WorkspacePortObservationContext) async -> [Workspace.ID: [WorkspacePort]]
}

struct DefaultWorkspacePortSnapshotProvider: WorkspacePortSnapshotProvider {
    typealias CommandRunner = @Sendable (_ executable: String, _ arguments: [String]) async throws -> String

    private let commandRunner: CommandRunner

    init(commandRunner: @escaping CommandRunner = Self.runCommand) {
        self.commandRunner = commandRunner
    }

    func snapshot(context: WorkspacePortObservationContext) async -> [Workspace.ID: [WorkspacePort]] {
        guard !context.worktreesByID.isEmpty else { return [:] }

        do {
            let listeningPortsOutput = try await commandRunner(
                "/usr/sbin/lsof",
                ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]
            )
            let listeningRecords = parseListeningPorts(listeningPortsOutput)
            guard !listeningRecords.isEmpty else { return [:] }

            let parentByProcessID = try await loadParentProcessMap()
            let allRelevantProcessIDs = collectRelevantProcessIDs(
                from: listeningRecords,
                parentByProcessID: parentByProcessID
            )
            let workingDirectoryByProcessID = try await loadWorkingDirectories(
                processIDs: allRelevantProcessIDs
            )

            return buildSnapshot(
                from: listeningRecords,
                context: context,
                parentByProcessID: parentByProcessID,
                workingDirectoryByProcessID: workingDirectoryByProcessID
            )
        } catch {
            return [:]
        }
    }
}

private extension DefaultWorkspacePortSnapshotProvider {
    private func loadParentProcessMap() async throws -> [Int32: Int32] {
        let output = try await commandRunner("/bin/ps", ["-axo", "pid=,ppid="])
        var result: [Int32: Int32] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { continue }
            result[pid] = ppid
        }

        return result
    }

    private func collectRelevantProcessIDs(
        from listeningRecords: [ListeningPortRecord],
        parentByProcessID: [Int32: Int32]
    ) -> [Int32] {
        var result: Set<Int32> = []

        for record in listeningRecords {
            var current = record.processID
            var visited: Set<Int32> = []

            while current > 0, visited.insert(current).inserted {
                result.insert(current)
                guard let parent = parentByProcessID[current], parent != current else { break }
                current = parent
            }
        }

        return result.sorted()
    }

    private func loadWorkingDirectories(processIDs: [Int32]) async throws -> [Int32: URL] {
        guard !processIDs.isEmpty else { return [:] }

        let pidList = processIDs.map(String.init).joined(separator: ",")
        let output = try await commandRunner(
            "/usr/sbin/lsof",
            ["-a", "-d", "cwd", "-p", pidList, "-F", "pn"]
        )

        var currentProcessID: Int32?
        var result: [Int32: URL] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentProcessID = Int32(value)
            case "n":
                guard let currentProcessID else { continue }
                result[currentProcessID] = URL(fileURLWithPath: value).standardizedFileURL
            default:
                continue
            }
        }

        return result
    }

    private func buildSnapshot(
        from listeningRecords: [ListeningPortRecord],
        context: WorkspacePortObservationContext,
        parentByProcessID: [Int32: Int32],
        workingDirectoryByProcessID: [Int32: URL]
    ) -> [Workspace.ID: [WorkspacePort]] {
        let managedWorkspaceByProcessID = context.managedProcessesByWorkspace.reduce(
            into: [Int32: Workspace.ID]()
        ) { partialResult, entry in
            let (workspaceID, processes) = entry
            for process in processes {
                partialResult[process.processID] = workspaceID
            }
        }

        let workingDirectoriesByWorkspace = context.worktreesByID.reduce(
            into: [Workspace.ID: URL]()
        ) { partialResult, entry in
            partialResult[entry.key] = entry.value.workingDirectory.standardizedFileURL
        }

        let ownershipState = assignPorts(
            listeningRecords: listeningRecords,
            managedWorkspaceByProcessID: managedWorkspaceByProcessID,
            workingDirectoriesByWorkspace: workingDirectoriesByWorkspace,
            parentByProcessID: parentByProcessID,
            workingDirectoryByProcessID: workingDirectoryByProcessID
        )

        return finalizedPorts(
            assignmentsByWorkspaceAndPort: ownershipState.assignmentsByWorkspaceAndPort,
            ambiguousPortsByWorkspace: ownershipState.ambiguousPortsByWorkspace
        )
    }

    private func resolveWorkspaceIDs(
        for processID: Int32,
        managedWorkspaceByProcessID: [Int32: Workspace.ID],
        workingDirectoriesByWorkspace: [Workspace.ID: URL],
        parentByProcessID: [Int32: Int32],
        workingDirectoryByProcessID: [Int32: URL]
    ) -> Set<Workspace.ID> {
        var result: Set<Workspace.ID> = []
        var currentProcessID = processID
        var visited: Set<Int32> = []

        while currentProcessID > 0, visited.insert(currentProcessID).inserted {
            if let managedWorkspaceID = managedWorkspaceByProcessID[currentProcessID] {
                result.insert(managedWorkspaceID)
            }

            if let workingDirectory = workingDirectoryByProcessID[currentProcessID] {
                for (workspaceID, workspaceRoot) in workingDirectoriesByWorkspace
                where workingDirectory.isDescendant(of: workspaceRoot) {
                    result.insert(workspaceID)
                }
            }

            guard let parentProcessID = parentByProcessID[currentProcessID],
                  parentProcessID != currentProcessID else {
                break
            }
            currentProcessID = parentProcessID
        }

        return result
    }

    private func parseListeningPorts(_ output: String) -> [ListeningPortRecord] {
        var currentProcessID: Int32?
        var currentProcessName: String?
        var seen: Set<ListeningPortRecord> = []
        var result: [ListeningPortRecord] = []

        for line in output.split(whereSeparator: \.isNewline) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentProcessID = Int32(value)
            case "c":
                currentProcessName = value
            case "n":
                guard let currentProcessID,
                      let port = parsePort(value) else { continue }
                let record = ListeningPortRecord(
                    processID: currentProcessID,
                    processName: currentProcessName ?? "",
                    port: port
                )
                if seen.insert(record).inserted {
                    result.append(record)
                }
            default:
                continue
            }
        }

        return result
    }

    private func parsePort(_ value: String) -> Int? {
        let cleaned = value.replacingOccurrences(of: " (LISTEN)", with: "")
        guard let colonIndex = cleaned.lastIndex(of: ":") else { return nil }
        let suffix = cleaned[cleaned.index(after: colonIndex)...]
        let digits = suffix.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    private func assignPorts(
        listeningRecords: [ListeningPortRecord],
        managedWorkspaceByProcessID: [Int32: Workspace.ID],
        workingDirectoriesByWorkspace: [Workspace.ID: URL],
        parentByProcessID: [Int32: Int32],
        workingDirectoryByProcessID: [Int32: URL]
    ) -> WorkspacePortOwnershipState {
        var assignmentsByWorkspaceAndPort: [Workspace.ID: [Int: WorkspacePortAssignment]] = [:]
        var ambiguousPortsByWorkspace: [Workspace.ID: Set<Int>] = [:]

        for record in listeningRecords {
            let workspaceIDs = resolveWorkspaceIDs(
                for: record.processID,
                managedWorkspaceByProcessID: managedWorkspaceByProcessID,
                workingDirectoriesByWorkspace: workingDirectoriesByWorkspace,
                parentByProcessID: parentByProcessID,
                workingDirectoryByProcessID: workingDirectoryByProcessID
            )

            guard !workspaceIDs.isEmpty else { continue }

            if workspaceIDs.count > 1 {
                for workspaceID in workspaceIDs {
                    ambiguousPortsByWorkspace[workspaceID, default: []].insert(record.port)
                }
            }

            for workspaceID in workspaceIDs {
                addAssignment(
                    record,
                    to: workspaceID,
                    assignmentsByWorkspaceAndPort: &assignmentsByWorkspaceAndPort
                )
            }
        }

        return WorkspacePortOwnershipState(
            assignmentsByWorkspaceAndPort: assignmentsByWorkspaceAndPort,
            ambiguousPortsByWorkspace: ambiguousPortsByWorkspace
        )
    }

    private func addAssignment(
        _ record: ListeningPortRecord,
        to workspaceID: Workspace.ID,
        assignmentsByWorkspaceAndPort: inout [Workspace.ID: [Int: WorkspacePortAssignment]]
    ) {
        var workspaceAssignments = assignmentsByWorkspaceAndPort[workspaceID] ?? [:]
        var assignment = workspaceAssignments[record.port] ?? WorkspacePortAssignment(port: record.port)
        assignment.processIDs.insert(record.processID)
        if let processName = workspacePortNilIfEmpty(record.processName) {
            assignment.processNames.insert(processName)
        }
        workspaceAssignments[record.port] = assignment
        assignmentsByWorkspaceAndPort[workspaceID] = workspaceAssignments
    }

    private func finalizedPorts(
        assignmentsByWorkspaceAndPort: [Workspace.ID: [Int: WorkspacePortAssignment]],
        ambiguousPortsByWorkspace: [Workspace.ID: Set<Int>]
    ) -> [Workspace.ID: [WorkspacePort]] {
        let workspacesByPort = assignmentsByWorkspaceAndPort.reduce(
            into: [Int: Set<Workspace.ID>]()
        ) { partialResult, entry in
            let (workspaceID, assignments) = entry
            for port in assignments.keys {
                partialResult[port, default: []].insert(workspaceID)
            }
        }

        return assignmentsByWorkspaceAndPort.reduce(into: [Workspace.ID: [WorkspacePort]]()) { partialResult, entry in
            let (workspaceID, assignments) = entry
            let ports = assignments.values.sorted { $0.port < $1.port }.map { assignment in
                let hasGlobalConflict = (workspacesByPort[assignment.port]?.count ?? 0) > 1
                let hasAmbiguousOwnership = ambiguousPortsByWorkspace[workspaceID]?.contains(assignment.port) == true

                return WorkspacePort(
                    workspaceID: workspaceID,
                    port: assignment.port,
                    processIDs: assignment.processIDs.sorted(),
                    processNames: assignment.processNames.sorted(),
                    ownership: (hasGlobalConflict || hasAmbiguousOwnership) ? .conflicted : .owned
                )
            }

            if !ports.isEmpty {
                partialResult[workspaceID] = ports
            }
        }
    }

    private static func runCommand(
        executable: String,
        arguments: [String]
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "WorkspacePortStore",
                            code: Int(process.terminationStatus),
                            userInfo: [
                                NSLocalizedDescriptionKey: workspacePortNilIfEmpty(error)
                                    ?? workspacePortNilIfEmpty(output)
                                    ?? "Command failed: \(executable)"
                            ]
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

@MainActor
@Observable
final class WorkspacePortStore {
    struct Configuration {
        let selectedRefreshInterval: TimeInterval
        let backgroundRefreshInterval: TimeInterval
        let refreshDedupInterval: TimeInterval

        static let `default` = Configuration(
            selectedRefreshInterval: 10,
            backgroundRefreshInterval: 60,
            refreshDedupInterval: 1.5
        )
    }

    enum RefreshReason: String {
        case contextChange
        case managedProcessLaunch
        case managedProcessExit
        case selectedPeriodic
        case backgroundPeriodic
        case manual
    }

    enum UpdateMode {
        case structureOnly
        case refreshIfNeeded
    }

    static let logger = Logger(subsystem: "com.devys.mac-client", category: "WorkspacePortStore")

    let snapshotProvider: any WorkspacePortSnapshotProvider
    var refreshTask: Task<Void, Never>?
    var selectedPeriodicTask: Task<Void, Never>?
    var backgroundPeriodicTask: Task<Void, Never>?
    var worktreesByID: [Workspace.ID: Worktree] = [:]
    var managedProcessesByWorkspace: [Workspace.ID: [ManagedWorkspaceProcess]] = [:]
    var selectedWorktreeId: Workspace.ID?
    var lastRefreshByWorkspace: [Workspace.ID: Date] = [:]
    var pendingRefreshRequests: [WorkspacePortRefreshRequest] = []
    let configuration: Configuration
    var isActiveRepository = true
    var backgroundRefreshCursor = 0

    var portsByWorkspace: [Workspace.ID: [WorkspacePort]] = [:]
    var refreshRecords: [WorkspacePortRefreshRecord] = []

    init(
        snapshotProvider: any WorkspacePortSnapshotProvider = DefaultWorkspacePortSnapshotProvider(),
        configuration: Configuration = .default
    ) {
        self.snapshotProvider = snapshotProvider
        self.configuration = configuration
    }

    deinit {
        MainActor.assumeIsolated {
            refreshTask?.cancel()
            selectedPeriodicTask?.cancel()
            backgroundPeriodicTask?.cancel()
        }
    }
}

@MainActor
extension WorkspacePortStore {
    var summariesByWorkspace: [Workspace.ID: WorkspacePortSummary] {
        portsByWorkspace.reduce(into: [:]) { partialResult, entry in
            let ports = entry.value
            guard !ports.isEmpty else { return }
            partialResult[entry.key] = WorkspacePortSummary(
                totalCount: ports.count,
                conflictCount: ports.filter { $0.ownership == .conflicted }.count
            )
        }
    }

    func ports(for workspaceID: Workspace.ID?) -> [WorkspacePort] {
        guard let workspaceID else { return [] }
        return portsByWorkspace[workspaceID] ?? []
    }

    func summary(for workspaceID: Workspace.ID?) -> WorkspacePortSummary? {
        guard let workspaceID else { return nil }
        return summariesByWorkspace[workspaceID]
    }

    func update(
        worktrees: [Worktree],
        managedProcessesByWorkspace: [Workspace.ID: [ManagedWorkspaceProcess]],
        selectedWorktreeId: Workspace.ID? = nil,
        isActiveRepository: Bool = true,
        mode: UpdateMode = .refreshIfNeeded
    ) {
        let previousManagedProcessesByWorkspace = self.managedProcessesByWorkspace
        let nextWorktreesByID = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.id, $0) })
        let nextManagedProcessesByWorkspace = managedProcessesByWorkspace.filter {
            nextWorktreesByID[$0.key] != nil
        }
        let nextSelectedWorktreeId = selectedWorktreeId.flatMap { nextWorktreesByID[$0] != nil ? $0 : nil }
        let selectedDidChange = nextSelectedWorktreeId != self.selectedWorktreeId
        let worktreeContextDidChange = nextWorktreesByID != worktreesByID
        let refreshWorkspaceIDs = refreshWorkspaceIDs(
            nextWorktreesByID: nextWorktreesByID,
            nextSelectedWorktreeId: nextSelectedWorktreeId,
            selectedDidChange: selectedDidChange,
            worktreeContextDidChange: worktreeContextDidChange
        )

        self.worktreesByID = nextWorktreesByID
        self.managedProcessesByWorkspace = nextManagedProcessesByWorkspace
        self.selectedWorktreeId = isActiveRepository ? nextSelectedWorktreeId : nil
        self.isActiveRepository = isActiveRepository
        portsByWorkspace = portsByWorkspace.filter { worktreesByID[$0.key] != nil }
        lastRefreshByWorkspace = lastRefreshByWorkspace.filter { worktreesByID[$0.key] != nil }
        pendingRefreshRequests = pendingRefreshRequests.compactMap { request in
            let workspaceIDs = request.workspaceIDs.filter { worktreesByID[$0] != nil }
            guard !workspaceIDs.isEmpty else { return nil }
            return WorkspacePortRefreshRequest(reason: request.reason, workspaceIDs: workspaceIDs)
        }
        if worktreeContextDidChange || selectedDidChange {
            backgroundRefreshCursor = 0
        } else if backgroundRefreshCursor >= worktreesByID.count {
            backgroundRefreshCursor = 0
        }
        updatePeriodicRefresh(isActive: isActiveRepository && !nextWorktreesByID.isEmpty)

        guard isActiveRepository, mode == .refreshIfNeeded else { return }

        enqueueRefreshRequests(
            contextWorkspaceIDs: refreshWorkspaceIDs,
            managedProcessRequests: managedProcessRefreshRequests(
                from: previousManagedProcessesByWorkspace,
                to: nextManagedProcessesByWorkspace
            )
        )
    }

    func clearWorkspace(_ workspaceID: Workspace.ID) {
        portsByWorkspace.removeValue(forKey: workspaceID)
        lastRefreshByWorkspace.removeValue(forKey: workspaceID)
    }

    func refresh(workspaceIDs: [Workspace.ID]) {
        refresh(workspaceIDs: workspaceIDs, reason: .manual)
    }

    private func refreshWorkspaceIDs(
        nextWorktreesByID: [Workspace.ID: Worktree],
        nextSelectedWorktreeId: Workspace.ID?,
        selectedDidChange: Bool,
        worktreeContextDidChange: Bool
    ) -> Set<Workspace.ID> {
        var refreshWorkspaceIDs: Set<Workspace.ID> = []

        if let nextSelectedWorktreeId,
           selectedDidChange || worktreeContextDidChange || portsByWorkspace[nextSelectedWorktreeId] == nil {
            refreshWorkspaceIDs.insert(nextSelectedWorktreeId)
        } else if nextSelectedWorktreeId == nil, worktreeContextDidChange {
            refreshWorkspaceIDs.formUnion(nextWorktreesByID.keys)
        }

        return refreshWorkspaceIDs
    }

    private func enqueueRefreshRequests(
        contextWorkspaceIDs: Set<Workspace.ID>,
        managedProcessRequests: [WorkspacePortRefreshRequest]
    ) {
        for request in managedProcessRequests {
            refresh(workspaceIDs: request.workspaceIDs, reason: request.reason)
        }

        guard !contextWorkspaceIDs.isEmpty else { return }
        refresh(
            workspaceIDs: Array(contextWorkspaceIDs).sorted(),
            reason: .contextChange
        )
    }
}
