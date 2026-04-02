import Foundation
import ServerClient

extension IOSClientConnectionStore {
    func prepareNewSSHProfileDraft() {
        sshProfileDraft = SSHProfileDraft()
        sshStatusMessage = nil
    }

    func selectSSHProfile(id: String?) {
        selectedSSHProfileID = id
        if let id, let profile = sshProfiles.first(where: { $0.id == id }) {
            sshProfileDraft = SSHProfileDraft(profile: profile)
        }
    }

    func saveSSHProfileDraft() {
        let draft = sshProfileDraft
        let name = draft.normalizedName
        let host = draft.normalizedHost
        let username = draft.normalizedUsername

        guard !name.isEmpty else {
            sshStatusMessage = "Connection name is required."
            return
        }
        guard !host.isEmpty else {
            sshStatusMessage = "Hostname is required."
            return
        }
        guard !username.isEmpty else {
            sshStatusMessage = "Username is required."
            return
        }
        guard let port = draft.parsedPort, (1...65535).contains(port) else {
            sshStatusMessage = "Port must be between 1 and 65535."
            return
        }

        let profileID = draft.profileID ?? UUID().uuidString
        let existing = sshProfiles.first { $0.id == profileID }

        do {
            let authDescriptor = try resolveAuthDescriptor(
                draft: draft,
                profileID: profileID,
                existing: existing
            )

            var profile = SSHConnectionProfile(
                id: profileID,
                name: name,
                host: host,
                port: port,
                username: username,
                auth: authDescriptor,
                createdAt: existing?.createdAt ?? .now,
                updatedAt: .now,
                lastUsedAt: existing?.lastUsedAt,
                notes: draft.normalizedNotes
            )
            profile.markUpdated()
            sshProfiles = sshProfileStore.upsertProfile(profile)
            selectedSSHProfileID = profile.id
            sshProfileDraft = SSHProfileDraft(profile: profile)
            sshStatusMessage = "Saved connection \(profile.name)."
        } catch {
            sshStatusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func deleteSelectedSSHProfile() {
        guard let selectedSSHProfileID else {
            sshStatusMessage = "Select a connection first."
            return
        }
        deleteSSHProfile(id: selectedSSHProfileID)
    }

    func deleteSSHProfile(id: String) {
        do {
            try sshCredentialStore.deleteAllSecrets(for: id)
        } catch {
            sshStatusMessage = "Credential cleanup failed: \(error.localizedDescription)"
        }
        sshProfiles = sshProfileStore.deleteProfile(id: id)

        if selectedSSHProfileID == id {
            selectedSSHProfileID = sshProfiles.first?.id
        }
        sshProfileDraft = SSHProfileDraft(profile: selectedSSHProfile)
        sshStatusMessage = "Deleted connection."
    }

    func connectSelectedSSHProfile() {
        guard let profile = selectedSSHProfile else {
            sshStatusMessage = "Create a connection profile first."
            return
        }

        Task {
            await connectSSH(profile: profile)
        }
    }

    func reconnectSSHSession() {
        Task {
            do {
                state = .connecting
                try await sshTerminalSession.reconnect()
                state = .connected
            } catch {
                state = .failed("SSH reconnect failed: \(error.localizedDescription)")
                sshStatusMessage = "SSH reconnect failed: \(error.localizedDescription)"
            }
        }
    }

    func disconnectSSHSession() {
        if let continuation = sshHostTrustContinuation {
            sshHostTrustContinuation = nil
            sshHostTrustPrompt = nil
            continuation.resume(returning: .reject)
        }
        sshTerminalSession.disconnect()
        state = .disconnected
    }

    func trustUnknownSSHHostPermanently() {
        resolveSSHHostTrust(decision: .trust, remember: true)
    }

    func trustUnknownSSHHostOnce() {
        resolveSSHHostTrust(decision: .trust, remember: false)
    }

    func rejectUnknownSSHHost() {
        resolveSSHHostTrust(decision: .reject, remember: false)
    }
}

private extension IOSClientConnectionStore {
    func resolveAuthDescriptor(
        draft: SSHProfileDraft,
        profileID: String,
        existing: SSHConnectionProfile?
    ) throws -> SSHAuthDescriptor {
        switch draft.authKind {
        case .password:
            let password = draft.password.trimmingCharacters(in: .whitespacesAndNewlines)
            if password.isEmpty {
                guard existing?.auth.passwordCredentialID?.isEmpty == false else {
                    throw SSHDraftValidationError.passwordRequired
                }
            } else {
                try sshCredentialStore.setSecret(password, id: profileID, kind: .password)
            }
            try sshCredentialStore.deleteSecret(id: profileID, kind: .privateKey)
            try sshCredentialStore.deleteSecret(id: profileID, kind: .passphrase)
            return SSHAuthDescriptor.password(credentialID: profileID)

        case .privateKey:
            let privateKey = draft.privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if privateKey.isEmpty {
                guard existing?.auth.privateKeyCredentialID?.isEmpty == false else {
                    throw SSHDraftValidationError.privateKeyRequired
                }
            } else {
                try sshCredentialStore.setSecret(privateKey, id: profileID, kind: .privateKey)
            }

            let passphrase = draft.passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if passphrase.isEmpty {
                try sshCredentialStore.deleteSecret(id: profileID, kind: .passphrase)
            } else {
                try sshCredentialStore.setSecret(passphrase, id: profileID, kind: .passphrase)
            }
            try sshCredentialStore.deleteSecret(id: profileID, kind: .password)
            return SSHAuthDescriptor.privateKey(
                keyCredentialID: profileID,
                passphraseCredentialID: passphrase.isEmpty ? nil : profileID
            )
        }
    }

    func connectSSH(profile: SSHConnectionProfile) async {
        do {
            let authMethod = try resolveAuthenticationMethod(for: profile)
            let config = SSHConnectionConfiguration(
                host: profile.host,
                port: profile.port,
                username: profile.username,
                authentication: authMethod
            )

            state = .connecting
            sshStatusMessage = nil
            try await sshTerminalSession.connect(
                configuration: config,
                cols: preferredTerminalCols,
                rows: preferredTerminalRows
            ) { [weak self] context in
                guard let self else { return .reject }
                return await self.evaluateSSHHostKey(context)
            }

            state = .connected
            sshProfiles = sshProfileStore.markProfileUsed(id: profile.id)
            selectedSSHProfileID = profile.id
            sshStatusMessage = "Connected to \(profile.name)."
        } catch {
            state = .failed("SSH connect failed: \(error.localizedDescription)")
            sshStatusMessage = "SSH connect failed: \(error.localizedDescription)"
        }
    }

    func resolveAuthenticationMethod(for profile: SSHConnectionProfile) throws -> SSHAuthenticationMethod {
        switch profile.auth.kind {
        case .password:
            guard let credentialID = profile.auth.passwordCredentialID,
                  let password = try sshCredentialStore.getSecret(id: credentialID, kind: .password),
                  !password.isEmpty else {
                throw SSHDraftValidationError.passwordUnavailable
            }
            return .password(password)
        case .privateKey:
            guard let credentialID = profile.auth.privateKeyCredentialID,
                  let privateKey = try sshCredentialStore.getSecret(id: credentialID, kind: .privateKey),
                  !privateKey.isEmpty else {
                throw SSHDraftValidationError.privateKeyUnavailable
            }

            let passphraseID = profile.auth.passphraseCredentialID
            let passphrase = try passphraseID.flatMap { id in
                try sshCredentialStore.getSecret(id: id, kind: .passphrase)
            }

            return .privateKey(privateKeyPEM: privateKey, passphrase: passphrase)
        }
    }

    func evaluateSSHHostKey(_ context: SSHHostKeyValidationContext) async -> SSHHostKeyValidationDecision {
        let verification = knownHostsStore.verify(
            host: context.host,
            port: context.port,
            algorithm: context.algorithm,
            fingerprint: context.fingerprintSHA256
        )

        switch verification {
        case .trusted:
            return .trust
        case .mismatch(let existing):
            sshStatusMessage = "Host key mismatch for \(context.host). " +
                "Expected \(existing.fingerprint), got \(context.fingerprintSHA256)."
            return .reject
        case .unknown:
            return await withCheckedContinuation { continuation in
                sshHostTrustPrompt = SSHHostTrustPrompt(
                    host: context.host,
                    port: context.port,
                    algorithm: context.algorithm,
                    fingerprint: context.fingerprintSHA256
                )
                sshHostTrustContinuation = continuation
            }
        }
    }

    func resolveSSHHostTrust(
        decision: SSHHostKeyValidationDecision,
        remember: Bool
    ) {
        guard let prompt = sshHostTrustPrompt else { return }
        if remember, decision == .trust {
            _ = knownHostsStore.trustRecord(
                host: prompt.host,
                port: prompt.port,
                algorithm: prompt.algorithm,
                fingerprint: prompt.fingerprint
            )
        }

        let continuation = sshHostTrustContinuation
        sshHostTrustContinuation = nil
        sshHostTrustPrompt = nil
        continuation?.resume(returning: decision)
    }
}

private enum SSHDraftValidationError: Error, LocalizedError {
    case passwordRequired
    case privateKeyRequired
    case passwordUnavailable
    case privateKeyUnavailable

    var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return "Password is required for password authentication."
        case .privateKeyRequired:
            return "Private key is required for key authentication."
        case .passwordUnavailable:
            return "Stored password is missing. Re-enter and save this connection."
        case .privateKeyUnavailable:
            return "Stored private key is missing. Re-enter and save this connection."
        }
    }
}
