import SwiftUI
import UI

extension IOSClientRootView {
    enum PresentedSetupSheet: String, Identifiable {
        case pairingQRScanner

        var id: String { rawValue }
    }

    var setupCard: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("Setup Wizard")

            Text(store.setupProgressLabel)
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: DevysSpacing.space1) {
                ForEach(IOSClientConnectionStore.SetupStep.allCases) { step in
                    Text(step.title.lowercased())
                        .font(DevysTypography.xs)
                        .foregroundStyle(step.rawValue == store.setupStep.rawValue ? theme.accent : theme.textTertiary)
                        .padding(.horizontal, DevysSpacing.space2)
                        .padding(.vertical, DevysSpacing.space1)
                        .background(theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
                }
            }

            setupStepContent

            if let message = store.setupStatusMessage {
                Text(message)
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .terminalCardStyle(theme: theme)
        .sheet(item: $presentedSetupSheet) { sheet in
            switch sheet {
            case .pairingQRScanner:
                PairingQRCodeScannerSheet { payload in
                    store.importPairingPayload(payload)
                }
            }
        }
    }

    @ViewBuilder
    var setupStepContent: some View {
        switch store.setupStep {
        case .pair:
            setupPairStep
        case .trust:
            setupTrustStep
        case .validation:
            setupValidationStep
        case .defaults:
            setupDefaultsStep
        case .done:
            setupDoneStep
        }
    }

    var setupPairStep: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            Text("Create a challenge or import QR payload data, then exchange setup code to register this iPhone.")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            if store.pairingChallengeIsExpired {
                Text("Current setup challenge is expired. Import a new payload or create a new challenge.")
                    .font(DevysTypography.xs)
                    .foregroundStyle(DevysColors.warning)
            }

            pairingSection

            terminalButton("[next:trust]", tint: theme.accent) {
                store.goToSetupStep(.trust)
            }
            .disabled(!store.setupCanAdvanceFromPairing)
        }
    }

    var setupTrustStep: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            if let trustContext = store.pairingTrustContext ?? store.pairingChallenge {
                Text("server: \(trustContext.serverName)")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)

                Text("fingerprint: \(trustContext.serverFingerprint)")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled)

                if let hostname = trustContext.canonicalHostname, !hostname.isEmpty {
                    Text("hostname: \(hostname)")
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textTertiary)
                }

                if let fallbackAddress = trustContext.fallbackAddress, !fallbackAddress.isEmpty {
                    Text("fallback: \(fallbackAddress)")
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textTertiary)
                }
            } else {
                Text("No active challenge. Generate one in Pair to capture trust details.")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }

            if let trusted = store.currentTrustedFingerprint {
                Text("trusted fingerprint: \(trusted)")
                    .font(DevysTypography.xs)
                    .foregroundStyle(DevysColors.success)
                    .textSelection(.enabled)
            }

            if let mismatchMessage = store.trustMismatchMessage {
                Text(mismatchMessage)
                    .font(DevysTypography.xs)
                    .foregroundStyle(DevysColors.warning)
                    .textSelection(.enabled)
            }

            HStack(spacing: DevysSpacing.space2) {
                terminalButton("[back]", tint: theme.textSecondary) {
                    store.goToSetupStep(.pair)
                }

                terminalButton(
                    store.trustFingerprintMismatch ? "[replace trust]" : "[confirm trust]",
                    tint: theme.accent
                ) {
                    store.confirmCurrentServerTrust()
                }

                terminalButton("[next:validate]", tint: theme.textSecondary) {
                    store.goToSetupStep(.validation)
                }
                .disabled(!store.setupCanAdvanceFromTrust)
            }
        }
    }

    var setupValidationStep: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            Text("Run required checks before enabling daily auto-connect and resume.")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            terminalButton("[run checks]", tint: theme.accent) {
                store.runSetupPreflightChecks()
            }

            if store.setupPreflightChecks.isEmpty {
                Text("No checks run yet.")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: DevysSpacing.space1) {
                    ForEach(store.setupPreflightChecks) { check in
                        Text("\(check.passed ? "ok" : "fail") \(check.label) · \(check.detail)")
                            .font(DevysTypography.xs)
                            .foregroundStyle(check.passed ? DevysColors.success : DevysColors.warning)
                    }
                }
            }

            HStack(spacing: DevysSpacing.space2) {
                terminalButton("[back]", tint: theme.textSecondary) {
                    store.goToSetupStep(.trust)
                }

                terminalButton("[next:defaults]", tint: theme.textSecondary) {
                    store.goToSetupStep(.defaults)
                }
                .disabled(store.setupPreflightChecks.isEmpty || store.setupHasRequiredPreflightFailures)
            }
        }
    }

    var setupDefaultsStep: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            Text("Recommended defaults are enabled for fast daily reconnects.")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            Toggle(
                "Auto-connect on launch",
                isOn: Binding(
                    get: { store.setupAutoConnectOnLaunch },
                    set: { store.setupAutoConnectOnLaunch = $0 }
                )
            )
            .font(DevysTypography.xs)
            .tint(theme.accent)

            Toggle(
                "Auto-resume last session",
                isOn: Binding(
                    get: { store.setupAutoResumeLastSession },
                    set: { store.setupAutoResumeLastSession = $0 }
                )
            )
            .font(DevysTypography.xs)
            .tint(theme.accent)

            HStack(spacing: DevysSpacing.space2) {
                terminalButton("[back]", tint: theme.textSecondary) {
                    store.goToSetupStep(.validation)
                }

                terminalButton("[save defaults]", tint: theme.accent) {
                    store.persistSetupDefaults()
                }
            }
        }
    }

    var setupDoneStep: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            Text("Setup is complete. Daily launch now targets command-first flow.")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: DevysSpacing.space2) {
                terminalButton("[back]", tint: theme.textSecondary) {
                    store.goToSetupStep(.defaults)
                }

                terminalButton("[complete setup]", tint: theme.accent) {
                    store.completeSetup()
                }
                .disabled(!store.setupCanComplete)
            }
        }
    }

    var pairingSection: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            Text("Pairing")
                .font(DevysTypography.heading)
                .foregroundStyle(theme.textSecondary)

            TextField("Device Name", text: $store.pairingDeviceName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)

            if let challenge = store.pairingChallenge {
                Text("setup code: \(challenge.setupCode) · expires: \(challenge.expiresAt.formatted())")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }

            TextField("Setup Code", text: $store.pairingSetupCodeInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)

            TextField("QR Payload (JSON or devys://...)", text: $store.pairingPayloadTextInput, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)
                .lineLimit(2...4)

            HStack(spacing: DevysSpacing.space2) {
                terminalButton("[scan qr]", tint: theme.accent) {
                    presentedSetupSheet = .pairingQRScanner
                }

                terminalButton("[challenge]", tint: theme.accent) {
                    store.createPairingChallenge()
                }

                terminalButton("[pair]", tint: theme.textSecondary) {
                    store.exchangePairingChallenge()
                }

                terminalButton("[pairings]", tint: theme.textSecondary) {
                    store.refreshPairings()
                }

                terminalButton("[import payload]", tint: theme.textSecondary) {
                    store.importPairingPayloadFromText()
                }
            }

            if let status = store.pairingStatusMessage {
                Text(status)
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }

            if let tokenPreview = store.lastPairingAuthTokenPreview {
                Text("token preview: \(tokenPreview)...")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textTertiary)
            }

            if let payloadSummary = store.pairingPayloadImportSummary {
                Text(payloadSummary)
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textTertiary)
            }

            if !store.pairings.isEmpty {
                Text("paired devices: \(store.pairings.count)")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)

                VStack(alignment: .leading, spacing: DevysSpacing.space1) {
                    ForEach(store.pairings) { pairing in
                        VStack(alignment: .leading, spacing: DevysSpacing.space1) {
                            Text(
                                "\(pairing.deviceName) [\(pairing.status.rawValue)] · " +
                                    "\(pairing.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                            )
                            .font(DevysTypography.xs)
                            .foregroundStyle(theme.textSecondary)

                            if pairing.status == .active {
                                HStack(spacing: DevysSpacing.space2) {
                                    terminalButton("[rotate]", tint: theme.textSecondary) {
                                        store.rotatePairingToken(pairing.id)
                                    }

                                    terminalButton("[revoke]", tint: DevysColors.warning) {
                                        store.revokePairing(pairing.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
