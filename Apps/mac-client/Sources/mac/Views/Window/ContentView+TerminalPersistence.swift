// ContentView+TerminalPersistence.swift
// Devys - Persistent relaunch snapshot support for repositories, layouts, and terminals.

import Foundation
import CoreGraphics
import AppKit
import AppFeatures
import GhosttyTerminal
import Split
import Workspace

@MainActor
extension ContentView {
    func refreshAvailableRelaunchSnapshot() {
        guard let snapshot = terminalRelaunchPersistenceStore.load(),
              snapshot.hasRepositories else {
            availableRelaunchSnapshot = nil
            return
        }

        availableRelaunchSnapshot = snapshot
    }

    func requestWindowRelaunchRestore(force: Bool) async {
        await store.send(.requestWindowRelaunchRestore(force: force)).finish()
    }

    func restorePreviousSession() async {
        await requestWindowRelaunchRestore(force: true)
    }

    func warmPersistentTerminalHostIfNeeded() async {
        guard terminalHostWarmupState.beginIfNeeded() else { return }
        _ = try? await persistentTerminalHostController.ensureRunning()
    }

    func warmTerminalRendererIfNeeded() async {
        guard terminalRendererWarmupState.beginIfNeeded() else { return }
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2
        _ = try? GhosttyTerminalRendererWarmup.prepareSharedResources(scaleFactor: scaleFactor)
    }

    func persistTerminalRelaunchSnapshot() async {
        let hostedSessions = (try? await persistentTerminalHostController.listSessions())
            ?? rehydratableHostedSessions()
        await store.send(.persistWindowRelaunchSnapshot(hostedSessions)).finish()
        refreshAvailableRelaunchSnapshot()
    }

    func persistTerminalRelaunchSnapshotIfNeeded() {
        Task { @MainActor in
            await persistTerminalRelaunchSnapshot()
        }
    }

    func createPendingHostedTerminalSession(
        in workspaceID: Workspace.ID,
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil,
        stagedCommand: String? = nil,
        tabIcon: String = "terminal",
        id: UUID = UUID(),
        traceSource: String? = nil,
        launchProfile: TerminalSessionLaunchProfile = .compatibilityShell,
        openMode: String = "permanent"
    ) -> GhosttyTerminalSession {
        beginTerminalOpenTraceIfRequested(
            traceSource,
            sessionID: id,
            workspaceID: workspaceID,
            openMode: openMode,
            launchProfile: launchProfile
        )

        return createTerminalSession(
            in: workspaceID,
            workingDirectory: workingDirectory,
            requestedCommand: requestedCommand,
            stagedCommand: stagedCommand,
            tabIcon: tabIcon,
            startupPhase: .startingHost,
            id: id
        )
    }

    func startPendingHostedTerminalSession(
        _ session: GhosttyTerminalSession,
        in workspaceID: Workspace.ID,
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil,
        launchProfile: TerminalSessionLaunchProfile = .compatibilityShell,
        traceSource: String? = nil
    ) async throws {
        do {
            let effectiveRequestedCommand = requestedCommand ?? session.requestedCommand
            guard let controller = try await ensureTerminalStartupController(
                sessionID: session.id,
                workspaceID: workspaceID,
                shouldTrace: traceSource != nil
            ) else { return }
            guard let viewport = await awaitTerminalStartupViewport(
                for: session,
                workspaceID: workspaceID,
                controller: controller
            ) else { return }
            guard let record = try await createPendingHostedTerminalRecord(
                for: session,
                workspaceID: workspaceID,
                workingDirectory: workingDirectory,
                requestedCommand: effectiveRequestedCommand,
                viewport: viewport,
                launchProfile: launchProfile
            ) else { return }
            finalizePendingHostedTerminalSessionStart(
                session: session,
                record: record,
                controller: controller,
                shouldTrace: traceSource != nil
            )
        } catch {
            if terminalSessionExists(session.id, workspaceID: workspaceID) {
                session.lastErrorDescription = error.localizedDescription
                session.isRunning = false
                session.startupPhase = .failed
            }
            if traceSource != nil {
                endTerminalOpenTrace(
                    sessionID: session.id,
                    outcome: "failed",
                    context: ["error": error.localizedDescription]
                )
            }
            throw error
        }
    }

    func presentHostedTerminalTab(
        session: GhosttyTerminalSession,
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID?,
        failureMessage: String
    ) throws {
        let content = WorkspaceTabContent.terminal(workspaceID: workspaceID, id: session.id)
        guard let preferredPaneID else {
            openInPermanentTab(content: content)
            return
        }

        guard createTab(in: preferredPaneID, content: content) != nil else {
            shutdownWorkspaceTerminalSession(
                id: session.id,
                in: workspaceID,
                terminateHostedSession: false
            )
            endTerminalOpenTrace(
                sessionID: session.id,
                outcome: "failed",
                context: ["error": failureMessage]
            )
            throw NSError(
                domain: "HostedTerminalPresentation",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: failureMessage]
            )
        }
    }

    func shutdownWorkspaceTerminalSession(
        id: UUID,
        in workspaceID: Workspace.ID,
        terminateHostedSession: Bool = true
    ) {
        if terminateHostedSession,
           let session = workspaceTerminalRegistry.session(id: id, in: workspaceID),
           session.terminateHostedSessionOnClose {
            Task {
                try? await persistentTerminalHostController.terminateSession(id: id)
            }
            rehydratableHostedSessionsByID.removeValue(forKey: id)
            workspaceOperationalController.removeHostedSession(id)
        }

        workspaceOperationalController.shutdownTerminalSession(id: id, in: workspaceID)
        store.send(.removeWorkspaceRunTerminal(id))
        persistTerminalRelaunchSnapshotIfNeeded()
    }

    func executeWindowRelaunchRestore(
        _ request: WindowFeature.WindowRelaunchRestoreRequest
    ) async {
        let snapshot = request.snapshot
        rehydratableHostedSessionsByID = [:]
        workspaceOperationalController.replaceHostedSessions([:])

        if request.settings.restoreTerminalSessions {
            await prepareRehydratableHostedSessions()
        }

        await importWindowRelaunchRepositories(
            snapshot.repositoryRootURLs.map { Repository(rootURL: $0) }
        )
        store.send(.applyWindowRelaunchRestore(request))
        rehydrateWindowRelaunchHostedContent(request)

        if let selectedWorktree = selectedCatalogWorktree {
            persistVisibleWorkspaceState()
            resetWorkspaceState()
            restoreWorkspaceState(for: selectedWorktree)
        }
    }

    private func importWindowRelaunchRepositories(_ repositories: [Repository]) async {
        var seenRepositoryIDs: Set<Repository.ID> = []
        let uniqueRepositories = repositories.filter { repository in
            seenRepositoryIDs.insert(repository.id).inserted
        }
        guard !uniqueRepositories.isEmpty else { return }
        await store.send(.openResolvedRepositories(uniqueRepositories)).finish()
        await refreshRepositoryCatalogs(uniqueRepositories.map(\.id))
    }

    private func beginTerminalOpenTraceIfRequested(
        _ traceSource: String?,
        sessionID: UUID,
        workspaceID: Workspace.ID,
        openMode: String,
        launchProfile: TerminalSessionLaunchProfile
    ) {
        guard let traceSource else { return }

        beginTerminalOpenTrace(
            sessionID: sessionID,
            workspaceID: workspaceID,
            source: traceSource,
            openMode: openMode,
            sessionLifecycle: "new",
            launchProfile: launchProfile.rawValue
        )
        recordTerminalOpenCheckpoint(sessionID: sessionID, .hostEnsureStart)
    }

    private func ensurePersistentTerminalHost(
        for sessionID: UUID,
        shouldTrace: Bool
    ) async throws {
        let hostStartupMode = try await persistentTerminalHostController.ensureRunning()
        guard shouldTrace else { return }

        recordTerminalOpenCheckpoint(
            sessionID: sessionID,
            .hostReady,
            context: ["host_startup": hostStartupMode.rawValue]
        )
        recordTerminalOpenCheckpoint(sessionID: sessionID, .sessionCreateStart)
    }

    func ensureHostedTerminalController(
        sessionID: UUID,
        workspaceID: Workspace.ID
    ) -> HostedLocalTerminalController? {
        let existingController = workspaceTerminalRegistry.controller(id: sessionID, in: workspaceID)
        let controller = workspaceTerminalRegistry.ensureController(
            for: sessionID,
            in: workspaceID,
            socketPath: persistentTerminalHostController.socketPath,
            appearance: themeManager.ghosttyAppearance(systemColorScheme: systemColorScheme),
            performanceObserver: terminalPerformanceObserver(for: sessionID)
        )
        if existingController == nil, controller != nil {
            recordTerminalOpenCheckpoint(sessionID: sessionID, .controllerCreated)
        }
        return controller
    }

    private func ensureTerminalStartupController(
        sessionID: UUID,
        workspaceID: Workspace.ID,
        shouldTrace: Bool
    ) async throws -> HostedLocalTerminalController? {
        guard let controller = ensureHostedTerminalController(
            sessionID: sessionID,
            workspaceID: workspaceID
        ) else {
            endTerminalOpenTrace(sessionID: sessionID, outcome: "canceled")
            return nil
        }
        try await ensurePersistentTerminalHost(
            for: sessionID,
            shouldTrace: shouldTrace
        )
        guard terminalSessionExists(sessionID, workspaceID: workspaceID) else {
            endTerminalOpenTrace(sessionID: sessionID, outcome: "canceled")
            return nil
        }
        return controller
    }

    private func awaitTerminalStartupViewport(
        for session: GhosttyTerminalSession,
        workspaceID: Workspace.ID,
        controller: HostedLocalTerminalController
    ) async -> HostedTerminalViewport? {
        session.startupPhase = TerminalSessionStartupLifecycle.phaseAfterHostReady(
            viewportReady: controller.hasMeasuredViewport()
        )
        let viewport = await controller.awaitInitialViewport()
        guard let viewport else {
            endTerminalOpenTrace(sessionID: session.id, outcome: "canceled")
            return nil
        }
        recordTerminalOpenCheckpoint(
            sessionID: session.id,
            .viewportApplied,
            context: [
                "cols": String(viewport.size.cols),
                "rows": String(viewport.size.rows)
            ]
        )
        guard terminalSessionExists(session.id, workspaceID: workspaceID) else {
            endTerminalOpenTrace(sessionID: session.id, outcome: "canceled")
            return nil
        }
        return viewport
    }

    private func createPendingHostedTerminalRecord(
        for session: GhosttyTerminalSession,
        workspaceID: Workspace.ID,
        workingDirectory: URL?,
        requestedCommand: String?,
        viewport: HostedTerminalViewport,
        launchProfile: TerminalSessionLaunchProfile
    ) async throws -> HostedTerminalSessionRecord? {
        let record = try await persistentTerminalHostController.createSession(
            id: session.id,
            workspaceID: workspaceID,
            workingDirectory: workingDirectory,
            launchCommand: requestedCommand,
            initialSize: viewport.size,
            launchProfile: launchProfile,
            persistOnDisconnect: appSettings.restore.restoreTerminalSessions,
            skipEnsureRunning: true
        )
        guard terminalSessionExists(session.id, workspaceID: workspaceID) else {
            try? await persistentTerminalHostController.terminateSession(id: session.id)
            endTerminalOpenTrace(sessionID: session.id, outcome: "canceled")
            return nil
        }
        return record
    }

    private func finalizePendingHostedTerminalSessionStart(
        session: GhosttyTerminalSession,
        record: HostedTerminalSessionRecord,
        controller: HostedLocalTerminalController,
        shouldTrace: Bool
    ) {
        session.startupPhase = .startingShell
        recordTerminalSessionCreatedIfNeeded(
            sessionID: session.id,
            shouldTrace: shouldTrace
        )
        rehydratableHostedSessionsByID[record.id] = record
        workspaceOperationalController.upsertHostedSession(record)
        controller.attachIfNeeded()
    }

    private func recordTerminalSessionCreatedIfNeeded(
        sessionID: UUID,
        shouldTrace: Bool
    ) {
        guard shouldTrace else { return }
        recordTerminalOpenCheckpoint(sessionID: sessionID, .sessionCreated)
    }

    private func terminalSessionExists(
        _ sessionID: UUID,
        workspaceID: Workspace.ID
    ) -> Bool {
        workspaceTerminalRegistry.session(id: sessionID, in: workspaceID) != nil
    }

    private func rehydrateWindowRelaunchHostedContent(
        _ request: WindowFeature.WindowRelaunchRestoreRequest
    ) {
        guard request.settings.restoreWorkspaceLayoutAndTabs else { return }

        for workspaceState in request.snapshot.workspaceStates {
            let workspaceID = workspaceState.workspaceID
            for tabRecord in workspaceState.persistedTabs {
                switch tabRecord {
                case .terminal(let hostedSessionID):
                    guard request.settings.restoreTerminalSessions else { continue }
                    _ = rehydrateHostedSession(hostedSessionID, workspaceID: workspaceID)
                case .chat(let record):
                    guard request.settings.restoreChatSessions else { continue }
                    restoreChatSession(record, workspaceID: workspaceID)
                case .browser(let id, let url):
                    _ = ensureBrowserSession(id: id, in: workspaceID, initialURL: url)
                case .editor,
                     .gitDiff,
                     .workflowDefinition,
                     .workflowRun:
                    continue
                }
            }
        }
    }

    private func prepareRehydratableHostedSessions() async {
        do {
            let hostedSessions = try await persistentTerminalHostController.listSessions()
            rehydratableHostedSessionsByID = Dictionary(
                uniqueKeysWithValues: hostedSessions.map { ($0.id, $0) }
            )
            workspaceOperationalController.replaceHostedSessions(rehydratableHostedSessionsByID)
        } catch {
            rehydratableHostedSessionsByID = [:]
            workspaceOperationalController.replaceHostedSessions([:])
        }
    }

    private func rehydrateHostedSession(
        _ sessionID: UUID,
        workspaceID: Workspace.ID
    ) -> Bool {
        if workspaceTerminalRegistry.session(id: sessionID, in: workspaceID) != nil {
            return true
        }

        guard let record = rehydratableHostedSessionsByID[sessionID],
              record.workspaceID == workspaceID else {
            return false
        }

        _ = createTerminalSession(
            in: workspaceID,
            workingDirectory: record.workingDirectory,
            requestedCommand: record.launchCommand,
            preferredViewportSize: record.viewportSize.map {
                HostedTerminalViewportSize(cols: $0.cols, rows: $0.rows)
            },
            id: sessionID
        )
        return true
    }

    private func rehydratableHostedSessions() -> [HostedTerminalSessionRecord] {
        rehydratableHostedSessionsByID.values.sorted { $0.createdAt < $1.createdAt }
    }
}
