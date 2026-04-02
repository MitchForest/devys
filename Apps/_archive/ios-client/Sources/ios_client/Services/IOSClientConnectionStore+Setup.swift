import Foundation
import ServerProtocol

extension IOSClientConnectionStore {
    var pairingChallengeIsExpired: Bool {
        guard let challenge = pairingChallenge else { return false }
        return challenge.expiresAt <= Date()
    }

    var setupProgressLabel: String {
        "Step \(setupStep.rawValue + 1) of \(SetupStep.allCases.count): \(setupStep.title)"
    }

    var currentTrustedFingerprint: String? {
        guard let serverURLKey = normalizedServerURLString else { return nil }
        return trustedServerFingerprints[serverURLKey]
    }

    var setupCanAdvanceFromPairing: Bool {
        (pairingChallenge != nil && !pairingChallengeIsExpired) || pairings.contains { $0.status == .active }
    }

    var setupCanAdvanceFromTrust: Bool {
        isCurrentServerTrusted
    }

    var trustFingerprintMismatch: Bool {
        guard let trusted = currentTrustedFingerprint else { return false }
        guard let incoming = (pairingTrustContext ?? pairingChallenge)?.serverFingerprint else { return false }
        return trusted != incoming
    }

    var trustMismatchMessage: String? {
        guard trustFingerprintMismatch else { return nil }
        guard let trusted = currentTrustedFingerprint else { return nil }
        guard let incoming = (pairingTrustContext ?? pairingChallenge)?.serverFingerprint else { return nil }
        return "Trusted fingerprint differs from incoming fingerprint.\ntrusted: \(trusted)\nincoming: \(incoming)"
    }

    var setupHasRequiredPreflightFailures: Bool {
        setupPreflightChecks.contains { $0.isRequired && !$0.passed }
    }

    var setupCanComplete: Bool {
        hasConnection && !setupHasRequiredPreflightFailures && isCurrentServerTrusted
    }

    func bootstrapConnectionIfNeeded() {
        guard !didAttemptBootstrapConnect else { return }
        didAttemptBootstrapConnect = true

        guard setupAutoConnectOnLaunch else { return }
        guard normalizedServerURL != nil else { return }
        guard state == .disconnected else { return }
        connect()
    }

    func applySetupProgressAfterConnect() {
        let hasActivePairings = pairings.contains { $0.status == .active }

        if hasCompletedSetup {
            setupStep = .done
            return
        }

        if !hasActivePairings, pairingChallenge == nil {
            setupStep = .pair
            return
        }

        if !isCurrentServerTrusted {
            setupStep = .trust
            return
        }

        if setupPreflightChecks.isEmpty || setupHasRequiredPreflightFailures {
            setupStep = .validation
            return
        }

        setupStep = .defaults
    }

    func goToSetupStep(_ step: SetupStep) {
        setupStep = step
    }

    func importPairingPayloadFromText() {
        importPairingPayload(pairingPayloadTextInput)
    }

    func importPairingPayload(_ payloadText: String) {
        let rawPayload = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPayload.isEmpty else {
            pairingStatusMessage = "Paste pairing payload text first."
            return
        }
        guard let payload = decodePairingPayload(from: rawPayload) else {
            pairingStatusMessage = "Invalid pairing payload format."
            return
        }
        switch validatePairingPayload(payload) {
        case .success(let validatedPayload):
            pairingPayloadTextInput = rawPayload
            applyPairingPayload(validatedPayload)
        case .failure(let validationError):
            pairingStatusMessage = validationError.message
            pairingPayloadImportSummary = nil
        }
    }

    func confirmCurrentServerTrust() {
        guard let trustContext = pairingTrustContext ?? pairingChallenge else {
            setupStatusMessage = "Create a pairing challenge to confirm trust."
            return
        }
        guard let serverURLKey = normalizedServerURLString else {
            setupStatusMessage = "Server URL is invalid."
            return
        }

        trustedServerFingerprints[serverURLKey] = trustContext.serverFingerprint
        persistSetupPreferences()
        setupStatusMessage = "Trust confirmed for \(trustContext.serverName)."
        if setupStep.rawValue < SetupStep.validation.rawValue {
            setupStep = .validation
        }
    }

    func runSetupPreflightChecks() {
        guard let baseURL = connectedBaseURL else {
            setupStatusMessage = "Connect to mac-server before validation."
            return
        }

        Task {
            do {
                async let healthResult = client.health(baseURL: baseURL)
                async let capabilitiesResult = client.capabilities(baseURL: baseURL)

                let health = try await healthResult
                let capabilities = try await capabilitiesResult
                self.health = health
                self.capabilities = capabilities

                setupPreflightChecks = makePreflightChecks(health: health, capabilities: capabilities)
                applyPreflightCheckOutcome()
            } catch {
                setupStatusMessage = "Validation failed: \(error.localizedDescription)"
            }
        }
    }

    func persistSetupDefaults() {
        persistSetupPreferences()
        setupStatusMessage = "Defaults saved."
        setupStep = .done
    }

    func completeSetup() {
        hasCompletedSetup = true
        setupStep = .done
        setupStatusMessage = "Setup complete. Daily launch path is ready."
        persistSetupPreferences()
    }

    func persistSessionBehaviorPreferences() {
        persistSetupPreferences()
    }

    private var normalizedServerURLString: String? {
        normalizedServerURL?.absoluteString
    }

    private var isCurrentServerTrusted: Bool {
        guard let trusted = currentTrustedFingerprint else { return false }
        guard let challengeFingerprint = (pairingTrustContext ?? pairingChallenge)?.serverFingerprint else {
            return true
        }
        return trusted == challengeFingerprint
    }

    private func persistSetupPreferences() {
        UserDefaults.standard.set(hasCompletedSetup, forKey: Keys.setupCompleted)
        UserDefaults.standard.set(setupAutoConnectOnLaunch, forKey: Keys.setupAutoConnect)
        UserDefaults.standard.set(setupAutoResumeLastSession, forKey: Keys.setupAutoResume)
        UserDefaults.standard.set(trustedServerFingerprints, forKey: Keys.trustedFingerprints)
    }

    private func applyPreflightCheckOutcome() {
        if setupHasRequiredPreflightFailures {
            setupStatusMessage = "Validation found required failures."
            setupStep = .validation
            return
        }

        setupStatusMessage = "Validation passed required checks."
        setupStep = .defaults
    }

    private func makePreflightChecks(
        health: HealthResponse,
        capabilities: ServerCapabilitiesResponse
    ) -> [SetupPreflightCheck] {
        [
            SetupPreflightCheck(
                id: "server_reachable",
                label: "Server reachable",
                passed: true,
                isRequired: true,
                detail: "\(health.serverName) \(health.version)"
            ),
            SetupPreflightCheck(
                id: "tmux_available",
                label: "tmux available",
                passed: capabilities.tmuxAvailable,
                isRequired: true,
                detail: capabilities.tmuxAvailable ? "Detected" : "Not found on host"
            ),
            SetupPreflightCheck(
                id: "claude_available",
                label: "claude available",
                passed: capabilities.claudeAvailable,
                isRequired: false,
                detail: capabilities.claudeAvailable ? "Detected" : "Optional"
            ),
            SetupPreflightCheck(
                id: "codex_available",
                label: "codex available",
                passed: capabilities.codexAvailable,
                isRequired: false,
                detail: capabilities.codexAvailable ? "Detected" : "Optional"
            )
        ]
    }

    private func applyPairingPayload(_ payload: ValidatedPairingPayload) {
        applyPairingPayloadServerTarget(payload)
        applyPairingPayloadChallenge(payload)
        applyPairingPayloadStatus()
    }

    private func applyPairingPayloadServerTarget(_ payload: ValidatedPairingPayload) {
        serverURLText = payload.serverURL
        persistConnectionDraft()
    }

    private func applyPairingPayloadChallenge(_ payload: ValidatedPairingPayload) {
        pairingSetupCodeInput = payload.setupCode

        let challenge = PairingChallengeResponse(
            challengeID: payload.challengeID,
            setupCode: payload.setupCode,
            expiresAt: payload.expiresAt,
            serverName: payload.serverName ?? health?.serverName ?? "Devys Server",
            serverFingerprint: payload.serverFingerprint ?? "unknown",
            canonicalHostname: payload.canonicalHostname,
            fallbackAddress: payload.fallbackAddress
        )
        pairingChallenge = challenge
        pairingTrustContext = challenge
        if setupStep.rawValue < SetupStep.trust.rawValue {
            setupStep = .trust
        }
    }

    private func applyPairingPayloadStatus() {
        let summary = "Imported challenge, setup-code, server target, and expiry."
        pairingPayloadImportSummary = summary
        pairingStatusMessage = summary
    }

    private func validatePairingPayload(
        _ payload: PairingPayloadDraft
    ) -> Result<ValidatedPairingPayload, PairingPayloadValidationError> {
        let challengeID = payload.challengeID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let setupCode = payload.setupCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverURL = resolvedServerURLString(from: payload)
        let expiresAt = payload.expiresAt

        var missing: [String] = []
        if challengeID?.isEmpty ?? true {
            missing.append("challenge")
        }
        if setupCode?.isEmpty ?? true {
            missing.append("setup-code")
        }
        if serverURL == nil {
            missing.append("server target")
        }
        if expiresAt == nil {
            missing.append("expiry")
        }
        if !missing.isEmpty {
            let missingFields = missing.joined(separator: ", ")
            return .failure(
                PairingPayloadValidationError(
                    message: "Pairing payload is missing required field(s): \(missingFields). " +
                        "Generate a new QR payload from mac-server."
                )
            )
        }

        guard let challengeID, let setupCode, let serverURL, let expiresAt else {
            return .failure(PairingPayloadValidationError(message: "Invalid pairing payload."))
        }

        guard expiresAt > Date() else {
            let expiryText = expiresAt.formatted(date: .abbreviated, time: .shortened)
            return .failure(
                PairingPayloadValidationError(
                    message: "Pairing payload expired at \(expiryText). Generate a new QR payload."
                )
            )
        }

        return .success(
            ValidatedPairingPayload(
                challengeID: challengeID,
                setupCode: setupCode,
                serverURL: serverURL,
                serverName: payload.serverName,
                serverFingerprint: payload.serverFingerprint,
                canonicalHostname: payload.canonicalHostname,
                fallbackAddress: payload.fallbackAddress,
                expiresAt: expiresAt
            )
        )
    }

    private func resolvedServerURLString(from payload: PairingPayloadDraft) -> String? {
        if let serverURL = payload.serverURL,
           let normalized = normalizeServerURLText(serverURL) {
            return normalized
        }
        if let canonicalHostname = payload.canonicalHostname,
           let normalized = normalizeHostOrAddress(canonicalHostname) {
            return normalized
        }
        if let fallbackAddress = payload.fallbackAddress,
           let normalized = normalizeHostOrAddress(fallbackAddress) {
            return normalized
        }
        return nil
    }

    private func normalizeServerURLText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = URL(string: trimmed), parsed.host != nil else { return nil }
        return parsed.absoluteString
    }

    private func normalizeHostOrAddress(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let normalized = normalizeServerURLText(trimmed) {
            return normalized
        }

        guard let hostComponents = URLComponents(string: "http://\(trimmed)"),
              let host = hostComponents.host else {
            return nil
        }

        var resolved = URLComponents()
        resolved.scheme = normalizedServerURL?.scheme ?? "http"
        resolved.host = host
        resolved.port = hostComponents.port ?? normalizedServerURL?.port ?? 8787
        return resolved.string
    }

    private func decodePairingPayload(from rawPayload: String) -> PairingPayloadDraft? {
        if let parsedJSON = decodePairingPayloadJSON(from: rawPayload) {
            return parsedJSON
        }
        return decodePairingPayloadURL(from: rawPayload)
    }

    private func decodePairingPayloadJSON(from rawPayload: String) -> PairingPayloadDraft? {
        guard let data = rawPayload.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(PairingPayloadDraft.self, from: data) {
            return decoded
        }

        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(PairingPayloadDraft.self, from: data)
    }

    private func decodePairingPayloadURL(from rawPayload: String) -> PairingPayloadDraft? {
        guard let components = URLComponents(string: rawPayload),
              let queryItems = components.queryItems else {
            return nil
        }

        func item(_ names: [String]) -> String? {
            for name in names {
                if let value = queryItems.first(where: { $0.name == name })?.value, !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        return PairingPayloadDraft(
            challengeID: item(["challengeId", "challengeID", "challenge_id"]),
            setupCode: item(["setupCode", "setup_code", "code"]),
            serverURL: item(["serverURL", "serverUrl", "server_url"]),
            canonicalHostname: item(["canonicalHostname", "canonical_hostname", "hostname"]),
            fallbackAddress: item(["fallbackAddress", "fallback_address", "fallback"]),
            serverName: item(["serverName", "server_name"]),
            serverFingerprint: item(["serverFingerprint", "server_fingerprint", "fingerprint"]),
            expiresAt: decodePayloadExpiry(item(["expiresAt", "expires_at", "exp", "expiry"]))
        )
    }

    private func decodePayloadExpiry(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let seconds = TimeInterval(trimmed) {
            // Support both epoch seconds and milliseconds.
            if seconds > 9_999_999_999 {
                return Date(timeIntervalSince1970: seconds / 1000)
            }
            return Date(timeIntervalSince1970: seconds)
        }

        let formatter = ISO8601DateFormatter()
        return formatter.date(from: trimmed)
    }

    private struct PairingPayloadDraft: Decodable {
        let challengeID: String?
        let setupCode: String?
        let serverURL: String?
        let canonicalHostname: String?
        let fallbackAddress: String?
        let serverName: String?
        let serverFingerprint: String?
        let expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case challengeID = "challengeId"
            case setupCode
            case serverURL
            case canonicalHostname
            case fallbackAddress
            case serverName
            case serverFingerprint
            case expiresAt
        }
    }

    private struct ValidatedPairingPayload {
        let challengeID: String
        let setupCode: String
        let serverURL: String
        let serverName: String?
        let serverFingerprint: String?
        let canonicalHostname: String?
        let fallbackAddress: String?
        let expiresAt: Date
    }

    private struct PairingPayloadValidationError: Error {
        let message: String
    }
}
