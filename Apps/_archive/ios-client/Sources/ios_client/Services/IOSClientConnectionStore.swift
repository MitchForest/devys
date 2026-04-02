import Foundation
import Observation
import ServerClient
import ServerProtocol
import SwiftUI
import UIKit

@MainActor
@Observable
final class IOSClientConnectionStore {
    var serverURLText: String
    var workspacePathText: String
    var state: ConnectionState = .disconnected
    var health: HealthResponse?
    var capabilities: ServerCapabilitiesResponse?
    var events: [StreamEventEnvelope] = []
    var sessions: [SessionSummary] = []
    var pairings: [PairingRecord] = []
    var pairingChallenge: PairingChallengeResponse?
    var pairingTrustContext: PairingChallengeResponse?
    var pairingSetupCodeInput = ""
    var pairingPayloadTextInput = ""
    var pairingPayloadImportSummary: String?
    var pairingDeviceName = UIDevice.current.name
    var pairingStatusMessage: String?
    var lastPairingAuthTokenPreview: String?
    var setupStep: SetupStep
    var setupPreflightChecks: [SetupPreflightCheck] = []
    var setupStatusMessage: String?
    var setupAutoConnectOnLaunch: Bool
    var setupAutoResumeLastSession: Bool
    var hasCompletedSetup: Bool
    var trustedServerFingerprints: [String: String]
    var sshProfiles: [SSHConnectionProfile]
    var selectedSSHProfileID: String?
    var sshProfileDraft: SSHProfileDraft
    var sshStatusMessage: String?
    var sshHostTrustPrompt: SSHHostTrustPrompt?
    var sshTerminalSession = SSHTerminalSession()
    var terminalSession = RemoteTerminalSession()
    var commandProfiles: [CommandProfile]
    var selectedCommandProfileID: String
    var launchMode: TerminalLaunchMode
    var selectedSessionID: String?
    var preferredTerminalCols: Int
    var preferredTerminalRows: Int
    var reconnectAttemptMessage: String?
    var commandProfileEditorMessage: String?
    var commandProfileValidationErrors: [String] = []
    var commandProfileValidationWarnings: [String] = []
    var isMutatingCommandProfile = false
    var readinessTelemetry = ReadinessTelemetrySnapshot()
    var isCtrlLatched = false
    var isAltLatched = false

    let client = ServerClient()
    let sshProfileStore = SSHProfileStore()
    let sshCredentialStore = SSHCredentialStore()
    let knownHostsStore = KnownHostsStore()
    var streamTask: Task<Void, Never>?
    var connectedBaseURL: URL?
    var didAttemptBootstrapConnect = false
    var shouldResumeOnActive = false
    var lastAppliedViewportGrid: (cols: Int, rows: Int)?
    var pendingViewportResizeTask: Task<Void, Never>?
    var promptObservationTask: Task<Void, Never>?
    var sshHostTrustContinuation: CheckedContinuation<SSHHostKeyValidationDecision, Never>?

    init() {
        let persisted = Self.loadPersistedState()
        let loadedSSHProfiles = SSHProfileStore().loadProfiles()
        let initialSelectedSSHProfileID = loadedSSHProfiles.first?.id

        commandProfiles = Self.fallbackCommandProfiles
        setupStep = persisted.setupCompleted ? .done : .pair
        setupAutoConnectOnLaunch = persisted.autoConnectOnLaunch
        setupAutoResumeLastSession = persisted.autoResumeLastSession
        hasCompletedSetup = persisted.setupCompleted
        trustedServerFingerprints = persisted.trustedFingerprints
        sshProfiles = loadedSSHProfiles
        selectedSSHProfileID = initialSelectedSSHProfileID
        sshProfileDraft = SSHProfileDraft(profile: loadedSSHProfiles.first)
        sshStatusMessage = nil
        sshHostTrustPrompt = nil

        serverURLText = persisted.serverURL
        workspacePathText = persisted.workspacePath
        selectedCommandProfileID = persisted.commandProfileID
        launchMode = persisted.launchMode
        selectedSessionID = persisted.selectedSessionID
        preferredTerminalCols = 120
        preferredTerminalRows = 40

        if let snapshot = Self.loadResumeSnapshot() {
            serverURLText = snapshot.serverURL
            workspacePathText = snapshot.workspacePath
            selectedCommandProfileID = snapshot.commandProfileID ?? persisted.commandProfileID
            launchMode = TerminalLaunchMode(rawValue: snapshot.launchMode ?? "") ?? persisted.launchMode
            selectedSessionID = snapshot.sessionID ?? persisted.selectedSessionID
            preferredTerminalCols = snapshot.cols
            preferredTerminalRows = snapshot.rows

            if let sessionID = snapshot.sessionID, let baseURL = Self.normalizedServerURL(from: snapshot.serverURL) {
                try? terminalSession.restore(
                    baseURL: baseURL,
                    sessionID: sessionID,
                    terminalID: snapshot.terminalID,
                    cols: snapshot.cols,
                    rows: snapshot.rows,
                    cursor: snapshot.cursor ?? 0
                )
            }
        }
    }

    var hasConnection: Bool { connectedBaseURL != nil && state == .connected }

    var sshTerminalStateText: String { sshTerminalSession.chromeState.statusText }

    var hasSSHProfile: Bool {
        sshProfiles.isEmpty == false
    }

    var selectedSSHProfile: SSHConnectionProfile? {
        guard let selectedSSHProfileID else { return sshProfiles.first }
        return sshProfiles.first { $0.id == selectedSSHProfileID } ?? sshProfiles.first
    }

    var selectedCommandProfile: CommandProfile {
        if let matched = commandProfiles.first(where: { $0.id == selectedCommandProfileID }) {
            return matched
        }
        if let shell = commandProfiles.first(where: { $0.id == "shell" }) {
            return shell
        }
        return commandProfiles.first ?? Self.fallbackCommandProfiles[0]
    }

    var canLaunchSelectedCommandProfile: Bool {
        guard let capabilities else { return true }
        return missingCapabilities(for: selectedCommandProfile, in: capabilities).isEmpty
    }

    var canLaunchTerminal: Bool {
        hasConnection && canLaunchSelectedCommandProfile &&
            (launchMode != .attachExisting || selectedSessionID != nil)
    }

    var launchValidationMessage: String? {
        guard hasConnection else { return "Connect to legacy mac-server to launch." }
        guard canLaunchSelectedCommandProfile else {
            return unavailableLaunchReason ?? "Selected command profile is not available on this server."
        }
        if launchMode == .attachExisting, selectedSessionID == nil {
            return "Select an existing session before launching attach mode."
        }
        return nil
    }

    var unavailableLaunchReason: String? {
        guard let capabilities else { return nil }
        let missing = missingCapabilities(for: selectedCommandProfile, in: capabilities)
        guard !missing.isEmpty else { return nil }

        let mapped = missing.map { capability in
            switch capability {
            case .tmux:
                return "tmux"
            case .claude:
                return "claude"
            case .codex:
                return "codex"
            }
        }

        return "Missing required capabilities: \(mapped.joined(separator: ", "))."
    }

    fileprivate func missingCapabilities(
        for profile: CommandProfile,
        in capabilities: ServerCapabilitiesResponse
    ) -> [CommandProfileCapability] {
        profile.requiredCapabilities.filter { capability in
            switch capability {
            case .tmux:
                return !capabilities.tmuxAvailable
            case .claude:
                return !capabilities.claudeAvailable
            case .codex:
                return !capabilities.codexAvailable
            }
        }
    }

}

extension IOSClientConnectionStore {
    func connect() {
        guard let baseURL = normalizedServerURL else {
            state = .failed("Invalid server URL")
            return
        }

        resetConnectionAttemptState()
        let connectStartedAt = Date()
        readinessTelemetry.connectionAttempts += 1
        readinessTelemetry.lastUpdatedAt = Date()

        Task {
            do {
                let health = try await client.health(baseURL: baseURL)
                async let capabilitiesResult = client.capabilities(baseURL: baseURL)
                async let sessionsResult = client.listSessions(baseURL: baseURL)
                async let profilesResult = client.listCommandProfiles(baseURL: baseURL)
                async let pairingsResult = client.listPairings(baseURL: baseURL)

                self.health = health
                self.capabilities = try? await capabilitiesResult
                if let listed = try? await sessionsResult {
                    self.sessions = listed.sessions
                    self.reconcileSelectionAfterSessionRefresh()
                }
                if let listedPairings = try? await pairingsResult {
                    self.pairings = listedPairings.pairings
                }

                let resolvedProfiles = (try? await profilesResult)?.profiles ?? Self.fallbackCommandProfiles
                applyCommandProfiles(resolvedProfiles)

                self.state = .connected
                self.connectedBaseURL = baseURL
                self.readinessTelemetry.connectionSuccesses += 1
                self.readinessTelemetry.lastTimeToConnectedMs = Self.elapsedMilliseconds(since: connectStartedAt)
                self.readinessTelemetry.lastUpdatedAt = Date()
                self.persistConnectionDraft()
                self.startStream(baseURL: baseURL)
                self.applySetupProgressAfterConnect()

                if self.setupAutoResumeLastSession, self.terminalSession.sessionID != nil {
                    self.resumeTerminalIfPossible()
                }
            } catch {
                self.readinessTelemetry.connectionFailures += 1
                self.readinessTelemetry.lastUpdatedAt = Date()
                self.state = .failed("Connect failed: \(error.localizedDescription)")
            }
        }
    }

    private func resetConnectionAttemptState() {
        state = .connecting
        health = nil
        capabilities = nil
        sessions = []
        pairings = []
        pairingChallenge = nil
        pairingTrustContext = nil
        pairingStatusMessage = nil
        pairingPayloadImportSummary = nil
        lastPairingAuthTokenPreview = nil
        events = []
        shouldResumeOnActive = false
        setupPreflightChecks = []
        setupStatusMessage = nil
        commandProfileEditorMessage = nil
        commandProfileValidationErrors = []
        commandProfileValidationWarnings = []
        promptObservationTask?.cancel()
        promptObservationTask = nil
        streamTask?.cancel()
        streamTask = nil
        connectedBaseURL = nil
    }

    func disconnect() {
        shouldResumeOnActive = false
        if let continuation = sshHostTrustContinuation {
            sshHostTrustContinuation = nil
            sshHostTrustPrompt = nil
            continuation.resume(returning: .reject)
        }
        pendingViewportResizeTask?.cancel()
        pendingViewportResizeTask = nil
        promptObservationTask?.cancel()
        promptObservationTask = nil
        streamTask?.cancel()
        streamTask = nil
        connectedBaseURL = nil
        sshTerminalSession.disconnect()
        terminalSession.disconnect()
        state = .disconnected
    }

    func refreshSessions() {
        guard let baseURL = connectedBaseURL else { return }
        Task {
            do {
                let response = try await client.listSessions(baseURL: baseURL)
                sessions = response.sessions
                reconcileSelectionAfterSessionRefresh()
            } catch {
                state = .failed("Refresh sessions failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshPairings() {
        guard let baseURL = connectedBaseURL else { return }
        Task {
            do {
                let response = try await client.listPairings(baseURL: baseURL)
                pairings = response.pairings
                if let pairingID = currentConversationPairingID,
                   !response.pairings.contains(where: { $0.id == pairingID && $0.status == .active })
                {
                    clearConversationPairingTokenIfMatches(pairingID: pairingID)
                }
            } catch {
                pairingStatusMessage = "Pairing list refresh failed: \(error.localizedDescription)"
            }
        }
    }

    func createPairingChallenge() {
        guard let baseURL = connectedBaseURL else {
            pairingStatusMessage = "Connect to mac-server before pairing."
            return
        }

        Task {
            do {
                let normalizedDeviceName = pairingDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                let response = try await client.createPairingChallenge(
                    baseURL: baseURL,
                    deviceName: normalizedDeviceName.isEmpty ? nil : normalizedDeviceName
                )
                pairingChallenge = response
                pairingTrustContext = response
                pairingSetupCodeInput = response.setupCode
                pairingStatusMessage = "Pairing challenge ready."
                if setupStep.rawValue < SetupStep.trust.rawValue {
                    setupStep = .trust
                }
            } catch {
                pairingStatusMessage = "Pairing challenge failed: \(error.localizedDescription)"
            }
        }
    }

    func exchangePairingChallenge() {
        guard let baseURL = connectedBaseURL else {
            pairingStatusMessage = "Connect to mac-server before pairing."
            return
        }
        guard let challenge = pairingChallenge else {
            pairingStatusMessage = "Create a pairing challenge first."
            return
        }
        guard challenge.expiresAt > Date() else {
            let expiryText = challenge.expiresAt.formatted(date: .abbreviated, time: .shortened)
            pairingStatusMessage = "Current setup code expired at \(expiryText). Import or generate a new challenge."
            return
        }

        let code = pairingSetupCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceName = pairingDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !deviceName.isEmpty else {
            pairingStatusMessage = "Setup code and device name are required."
            return
        }

        Task {
            do {
                let response = try await client.exchangePairing(
                    baseURL: baseURL,
                    challengeID: challenge.challengeID,
                    setupCode: code,
                    deviceName: deviceName
                )
                pairingStatusMessage = "Pairing succeeded for \(response.pairing.deviceName)."
                lastPairingAuthTokenPreview = String(response.authToken.prefix(12))
                UserDefaults.standard.set(response.authToken, forKey: ConversationConnectionDefaults.authTokenKey)
                UserDefaults.standard.set(response.pairing.id, forKey: ConversationConnectionDefaults.pairingIDKey)
                pairingChallenge = nil
                if setupStep.rawValue < SetupStep.trust.rawValue {
                    setupStep = .trust
                }
                refreshPairings()
            } catch {
                pairingStatusMessage = "Pairing exchange failed: \(error.localizedDescription)"
            }
        }
    }

    func rotatePairingToken(_ pairingID: String) {
        guard let baseURL = connectedBaseURL else {
            pairingStatusMessage = "Connect to mac-server before rotating pairing tokens."
            return
        }

        Task {
            do {
                let response = try await client.rotatePairing(baseURL: baseURL, pairingID: pairingID)
                pairings = pairings.map { $0.id == response.pairing.id ? response.pairing : $0 }
                if currentConversationPairingID == response.pairing.id {
                    UserDefaults.standard.set(response.authToken, forKey: ConversationConnectionDefaults.authTokenKey)
                    lastPairingAuthTokenPreview = String(response.authToken.prefix(12))
                }
                pairingStatusMessage = "Rotated pairing token for \(response.pairing.deviceName)."
                refreshPairings()
            } catch {
                pairingStatusMessage = "Rotate pairing failed: \(error.localizedDescription)"
            }
        }
    }

    func revokePairing(_ pairingID: String) {
        guard let baseURL = connectedBaseURL else {
            pairingStatusMessage = "Connect to mac-server before revoking pairings."
            return
        }

        Task {
            do {
                let response = try await client.revokePairing(baseURL: baseURL, pairingID: pairingID)
                pairings = pairings.map { $0.id == response.pairing.id ? response.pairing : $0 }
                clearConversationPairingTokenIfMatches(pairingID: response.pairing.id)
                pairingStatusMessage = "Revoked pairing for \(response.pairing.deviceName)."
                refreshPairings()
            } catch {
                pairingStatusMessage = "Revoke pairing failed: \(error.localizedDescription)"
            }
        }
    }

    func persistConnectionDraft() {
        UserDefaults.standard.set(serverURLText, forKey: Keys.serverURL)
        UserDefaults.standard.set(serverURLText, forKey: ConversationConnectionDefaults.serverURLKey)
        UserDefaults.standard.set(workspacePathText, forKey: Keys.workspacePath)
        UserDefaults.standard.set(selectedCommandProfileID, forKey: Keys.commandProfileID)
        UserDefaults.standard.set(launchMode.rawValue, forKey: Keys.launchMode)
        UserDefaults.standard.set(selectedSessionID, forKey: Keys.selectedSessionID)
    }

    func persistResumeSnapshot() {
        let snapshot = ResumeSnapshot(
            serverURL: serverURLText,
            workspacePath: workspacePathText,
            sessionID: sshTerminalSession.sessionID,
            terminalID: sshTerminalSession.terminalID,
            cols: sshTerminalSession.cols,
            rows: sshTerminalSession.rows,
            cursor: nil,
            commandProfileID: selectedCommandProfileID,
            launchMode: launchMode.rawValue
        )

        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Keys.resumeSnapshot)
        }
    }

    fileprivate func startStream(baseURL: URL) {
        streamTask?.cancel()
        streamTask = Task {
            do {
                let stream = await client.stream(baseURL: baseURL)
                for try await event in stream {
                    events.insert(event, at: 0)
                    if events.count > 200 {
                        events.removeLast(events.count - 200)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    state = .failed("Stream failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func applyCommandProfiles(_ profiles: [CommandProfile]) {
        let resolved = profiles.isEmpty ? Self.fallbackCommandProfiles : profiles
        let sorted = resolved.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
        commandProfiles = sorted

        if commandProfiles.contains(where: { $0.id == selectedCommandProfileID }) == false {
            selectedCommandProfileID = sorted.first?.id ?? "shell"
        }
    }

    static func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1_000.0))
    }

    private var currentConversationPairingID: String? {
        UserDefaults.standard.string(forKey: ConversationConnectionDefaults.pairingIDKey)
    }

    private func clearConversationPairingTokenIfMatches(pairingID: String) {
        guard currentConversationPairingID == pairingID else { return }
        UserDefaults.standard.removeObject(forKey: ConversationConnectionDefaults.authTokenKey)
        UserDefaults.standard.removeObject(forKey: ConversationConnectionDefaults.pairingIDKey)
    }
}
