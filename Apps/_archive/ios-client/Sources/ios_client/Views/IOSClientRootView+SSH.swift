import SwiftUI
import UI

extension IOSClientRootView {
    var sshProfilesCard: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("SSH Connection")

            if store.sshProfiles.isEmpty == false {
                VStack(alignment: .leading, spacing: DevysSpacing.space1) {
                    Text("Saved")
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textSecondary)

                    ForEach(store.sshProfiles, id: \.id) { profile in
                        sshProfileRow(profile)
                    }
                }
                .padding(.bottom, DevysSpacing.space1)
            } else {
                Text("No saved connections yet. Enter details below and tap [save].")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }

            Picker(
                "Saved Connection",
                selection: Binding(
                    get: { store.selectedSSHProfileID },
                    set: { store.selectSSHProfile(id: $0) }
                )
            ) {
                Text("New Connection").tag(Optional<String>.none)
                ForEach(store.sshProfiles, id: \.id) { profile in
                    Text("\(profile.name) · \(profile.username)@\(profile.host):\(profile.port)")
                        .tag(Optional(profile.id))
                }
            }
            .pickerStyle(.menu)

            TextField(
                "Connection Name",
                text: Binding(
                    get: { store.sshProfileDraft.name },
                    set: { store.sshProfileDraft.name = $0 }
                )
            )
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .font(DevysTypography.sm)

            HStack(spacing: DevysSpacing.space2) {
                TextField(
                    "Hostname or IP",
                    text: Binding(
                        get: { store.sshProfileDraft.host },
                        set: { store.sshProfileDraft.host = $0 }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)

                TextField(
                    "Port",
                    text: Binding(
                        get: { store.sshProfileDraft.portText },
                        set: { store.sshProfileDraft.portText = $0 }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)
                .frame(maxWidth: 96)
            }

            TextField(
                "Username",
                text: Binding(
                    get: { store.sshProfileDraft.username },
                    set: { store.sshProfileDraft.username = $0 }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .font(DevysTypography.sm)

            Picker(
                "Auth",
                selection: Binding(
                    get: { store.sshProfileDraft.authKind },
                    set: { store.sshProfileDraft.authKind = $0 }
                )
            ) {
                ForEach(SSHAuthMethodKind.allCases) { method in
                    Text(method.label).tag(method)
                }
            }
            .pickerStyle(.segmented)

            if store.sshProfileDraft.authKind == .password {
                SecureField(
                    "Password (leave blank to keep existing)",
                    text: Binding(
                        get: { store.sshProfileDraft.password },
                        set: { store.sshProfileDraft.password = $0 }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)
            } else {
                Text(
                    "Supported key formats: unencrypted OpenSSH Ed25519, " +
                        "or unencrypted PEM P-256/P-384/P-521."
                )
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)

                TextEditor(
                    text: Binding(
                        get: { store.sshProfileDraft.privateKey },
                        set: { store.sshProfileDraft.privateKey = $0 }
                    )
                )
                .frame(minHeight: 120, maxHeight: 180)
                .font(DevysTypography.xs)
                .padding(.horizontal, DevysSpacing.space1)
                .overlay(
                    RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                        .stroke(theme.borderSubtle, lineWidth: 1)
                )

                SecureField(
                    "Key passphrase (optional, encrypted keys unsupported)",
                    text: Binding(
                        get: { store.sshProfileDraft.passphrase },
                        set: { store.sshProfileDraft.passphrase = $0 }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)
            }

            TextField(
                "Notes (optional)",
                text: Binding(
                    get: { store.sshProfileDraft.notes },
                    set: { store.sshProfileDraft.notes = $0 }
                ),
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
            .font(DevysTypography.sm)

            HStack(spacing: DevysSpacing.space2) {
                terminalButton("[new]", tint: theme.textSecondary) {
                    store.prepareNewSSHProfileDraft()
                    store.selectSSHProfile(id: nil)
                }

                terminalButton("[save]", tint: theme.accent) {
                    store.saveSSHProfileDraft()
                }

                terminalButton("[delete]", tint: DevysColors.warning) {
                    store.deleteSelectedSSHProfile()
                }
                .disabled(store.selectedSSHProfileID == nil)

                Spacer(minLength: 0)

                terminalButton("[connect]", tint: theme.accent) {
                    store.connectSelectedSSHProfile()
                    isKeyboardFocused = true
                }
                .disabled(!store.hasSSHProfile || store.state == .connecting)

                terminalButton("[disconnect]", tint: theme.textSecondary) {
                    store.disconnectSSHSession()
                }
                .disabled(!store.sshTerminalSession.chromeState.canDisconnect)

                terminalButton("[reconnect]", tint: theme.textSecondary) {
                    store.reconnectSSHSession()
                }
                .disabled(!store.sshTerminalSession.chromeState.canReconnect)

                statusPill
            }

            if let message = store.sshStatusMessage {
                Text(message)
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }

            if let trustPrompt = store.sshHostTrustPrompt {
                VStack(alignment: .leading, spacing: DevysSpacing.space1) {
                    Text("Unknown host key: \(trustPrompt.host):\(trustPrompt.port)")
                        .font(DevysTypography.xs)
                        .foregroundStyle(DevysColors.warning)
                    Text("algorithm: \(trustPrompt.algorithm)")
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textSecondary)
                    Text("fingerprint: \(trustPrompt.fingerprint)")
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                    HStack(spacing: DevysSpacing.space2) {
                        terminalButton("[trust once]", tint: theme.accent) {
                            store.trustUnknownSSHHostOnce()
                        }
                        terminalButton("[trust always]", tint: theme.accent) {
                            store.trustUnknownSSHHostPermanently()
                        }
                        terminalButton("[reject]", tint: DevysColors.warning) {
                            store.rejectUnknownSSHHost()
                        }
                    }
                }
                .padding(DevysSpacing.space2)
                .background(theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
            }
        }
        .terminalCardStyle(theme: theme)
    }

    func sshProfileRow(_ profile: SSHConnectionProfile) -> some View {
        HStack(spacing: DevysSpacing.space2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(DevysTypography.sm)
                    .foregroundStyle(theme.text)

                Text("\(profile.username)@\(profile.host):\(profile.port)")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer(minLength: 0)

            if store.selectedSSHProfileID == profile.id {
                Text("selected")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.accent)
            }

            terminalButton("[use]", tint: theme.textSecondary) {
                store.selectSSHProfile(id: profile.id)
            }

            terminalButton("[connect]", tint: theme.accent) {
                store.selectSSHProfile(id: profile.id)
                store.connectSelectedSSHProfile()
                isKeyboardFocused = true
            }
            .disabled(store.state == .connecting)
        }
        .padding(.vertical, DevysSpacing.space1)
    }
}
