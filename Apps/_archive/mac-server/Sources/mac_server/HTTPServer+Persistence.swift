import Foundation

extension HTTPServer {
    func configureSessionPersistence(for session: RunSession) {
        session.onStateChange = { [weak self, weak session] in
            guard let self, let session else { return }
            do {
                try self.sessionStore.save(session: session.persistedState)
            } catch {
                writeServerLog("failed to persist run session \(session.id): \(error)")
            }
        }
        session.markDirty()
    }

    func loadPersistedRunSessions() {
        do {
            let persistedSessions = try sessionStore.loadAll()
            guard !persistedSessions.isEmpty else { return }

            for persisted in persistedSessions {
                let session = RunSession(persistedState: persisted)
                configureSessionPersistence(for: session)
                runSessions[session.id] = session
                recoverSessionAfterRestart(session)
            }
            writeServerLog("restored \(persistedSessions.count) persisted run session(s)")
        } catch {
            writeServerLog("failed to load persisted run sessions: \(error)")
        }
    }

    func recoverSessionAfterRestart(_ session: RunSession) {
        if session.usingTmux, let tmuxSessionName = session.tmuxSessionName {
            do {
                if try tmuxManager.hasSession(name: tmuxSessionName) {
                    try startTmuxOutputStream(for: session)
                    if session.status == .running || session.status == .stopping || session.awaitingExitMarker {
                        session.markStatus(.running)
                        session.appendText(type: .info, message: "session-recovered tmux-attached")
                    }
                    return
                }
            } catch {
                session.appendText(type: .error, message: "tmux-recovery-check-failed \(error.localizedDescription)")
            }

            stopTmuxOutputStream(for: session, terminateProcess: true)
            session.awaitingExitMarker = false
            session.usingTmux = false
            session.markDirty()
            if session.status == .running || session.status == .stopping {
                session.markStatus(.failed)
                session.appendTerminalStatus(.exited)
                session.appendTerminalClosed(exitCode: nil, reason: "recovery-failed")
                session.appendText(type: .error, message: "session-recovery-failed tmux-session-missing")
            }
            return
        }

        if session.status == .running || session.status == .stopping {
            session.markStatus(.failed)
            session.appendTerminalStatus(.exited)
            session.appendTerminalClosed(exitCode: nil, reason: "recovery-failed")
            session.appendText(type: .error, message: "session-recovery-failed non-tmux-runtime-unsupported")
        }
    }

    func loadPersistedPairings() {
        do {
            let persisted = try pairingStore.loadAll()
            guard !persisted.isEmpty else { return }
            for item in persisted {
                pairings[item.pairing.id] = item.pairing
                pairingTokens[item.pairing.id] = item.authToken
            }
            writeServerLog("restored \(persisted.count) persisted pairing(s)")
        } catch {
            writeServerLog("failed to load pairings: \(error)")
        }
    }

    func persistPairings() {
        do {
            let snapshot = pairings.values
                .sorted { $0.updatedAt > $1.updatedAt }
                .map { pairing in
                    PersistedPairing(
                        pairing: pairing,
                        authToken: pairingTokens[pairing.id] ?? ""
                    )
                }
            try pairingStore.save(snapshot)
        } catch {
            writeServerLog("failed to persist pairings: \(error)")
        }
    }

    func loadPersistedCommandProfiles() {
        do {
            let persisted = try commandProfileStore.loadAll()
            commandProfiles = Dictionary(uniqueKeysWithValues: persisted.map { ($0.id, $0.normalizedForStorage) })
        } catch {
            writeServerLog("failed to load command profiles: \(error)")
            commandProfiles = [:]
        }

        var insertedDefaults = false
        for profile in CommandProfileDefaults.all {
            let normalized = profile.normalizedForStorage
            if commandProfiles[normalized.id] == nil {
                commandProfiles[normalized.id] = normalized
                insertedDefaults = true
            }
        }

        if insertedDefaults || commandProfiles.isEmpty {
            persistCommandProfiles()
        }
    }

    func persistCommandProfiles() {
        do {
            let snapshot = commandProfiles.values.sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault {
                    return lhs.isDefault && !rhs.isDefault
                }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            try commandProfileStore.save(snapshot)
        } catch {
            writeServerLog("failed to persist command profiles: \(error)")
        }
    }
}
