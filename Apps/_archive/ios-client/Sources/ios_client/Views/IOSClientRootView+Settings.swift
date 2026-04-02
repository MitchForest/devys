import ServerProtocol
import SwiftUI
import UI

struct IOSClientSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme
    @State private var isProfileEditorPresented = false
    @State private var profileDraft = IOSClientConnectionStore.CommandProfileDraft()

    let store: IOSClientConnectionStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DevysSpacing.space3) {
                    connectionSection
                    commandProfilesSection
                    sessionBehaviorSection
                    diagnosticsSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(DevysSpacing.space4)
            }
            .background(theme.base)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $isProfileEditorPresented) {
            IOSClientCommandProfileEditorSheet(store: store, draft: $profileDraft)
        }
    }
}

private extension IOSClientSettingsSheet {
    var connectionSection: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("Legacy mac-server")

            TextField(
                "http://100.64.0.1:8787",
                text: Binding(
                    get: { store.serverURLText },
                    set: { newValue in
                        store.serverURLText = newValue
                        store.persistConnectionDraft()
                    }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .font(DevysTypography.sm)

            TextField(
                "/Users/you/path/to/repo",
                text: Binding(
                    get: { store.workspacePathText },
                    set: { newValue in
                        store.workspacePathText = newValue
                        store.persistConnectionDraft()
                    }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .font(DevysTypography.sm)

            Picker(
                "Command Profile",
                selection: Binding(
                    get: { store.selectedCommandProfileID },
                    set: { newValue in
                        store.selectedCommandProfileID = newValue
                        store.handleSelectedCommandProfileChanged()
                    }
                )
            ) {
                ForEach(store.commandProfiles, id: \.id) { profile in
                    Text(commandProfilePickerLabel(for: profile)).tag(profile.id)
                }
            }
            .pickerStyle(.menu)

            Picker(
                "Session Type",
                selection: Binding(
                    get: { store.launchMode },
                    set: { newValue in
                        store.launchMode = newValue
                        store.handleLaunchModeChanged()
                    }
                )
            ) {
                ForEach(IOSClientConnectionStore.TerminalLaunchMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if store.launchMode == .attachExisting {
                Picker(
                    "Session",
                    selection: Binding(
                        get: { store.selectedSessionID },
                        set: { newValue in
                            store.selectedSessionID = newValue
                            store.persistConnectionDraft()
                        }
                    )
                ) {
                    Text("Select Session").tag(Optional<String>.none)
                    ForEach(store.sessions, id: \.id) { session in
                        Text(store.sessionPickerLabel(for: session)).tag(Optional(session.id))
                    }
                }
                .pickerStyle(.menu)
                .font(DevysTypography.xs)
            }

            HStack(spacing: DevysSpacing.space2) {
                settingsButton("[connect]", tint: theme.accent) {
                    store.connect()
                }
                .disabled(store.state == .connecting)

                settingsButton("[disconnect]", tint: theme.textSecondary) {
                    store.disconnect()
                }

                settingsButton("[refresh]", tint: theme.textSecondary) {
                    store.refreshSessions()
                    store.refreshCommandProfiles()
                }
                .disabled(!store.hasConnection)
            }

            if let validationMessage = store.launchValidationMessage {
                Text(validationMessage)
                    .font(DevysTypography.xs)
                    .foregroundStyle(DevysColors.warning)
            }
        }
        .terminalCardStyle(theme: theme)
    }

    var commandProfilesSection: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("Legacy Command Profiles")

            HStack(spacing: DevysSpacing.space2) {
                settingsButton("[new]", tint: theme.accent) {
                    store.clearCommandProfileEditorFeedback()
                    profileDraft = store.makeNewCommandProfileDraft()
                    isProfileEditorPresented = true
                }

                settingsButton("[refresh]", tint: theme.textSecondary) {
                    store.refreshCommandProfiles()
                }
                .disabled(!store.hasConnection)
            }

            if store.commandProfiles.isEmpty {
                Text("No command profiles found.")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: DevysSpacing.space2) {
                    ForEach(store.commandProfiles, id: \.id) { profile in
                        commandProfileRow(profile)
                    }
                }
            }

            if let message = store.commandProfileEditorMessage {
                Text(message)
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }

            ForEach(store.commandProfileValidationErrors, id: \.self) { message in
                Text(message)
                    .font(DevysTypography.xs)
                    .foregroundStyle(DevysColors.error)
            }

            ForEach(store.commandProfileValidationWarnings, id: \.self) { message in
                Text(message)
                    .font(DevysTypography.xs)
                    .foregroundStyle(DevysColors.warning)
            }
        }
        .terminalCardStyle(theme: theme)
    }

    func commandProfileRow(_ profile: CommandProfile) -> some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space1) {
            HStack(spacing: DevysSpacing.space2) {
                Text("\(profile.label) [\(profile.id)]")
                    .font(DevysTypography.sm)
                    .foregroundStyle(theme.text)

                if profile.isDefault {
                    Text("server-default")
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textSecondary)
                }

                if store.selectedCommandProfileID == profile.id {
                    Text("startup")
                        .font(DevysTypography.xs)
                        .foregroundStyle(DevysColors.success)
                }

                Spacer(minLength: 0)
            }

            Text(commandProfileDetailText(for: profile))
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: DevysSpacing.space2) {
                settingsButton("[edit]", tint: theme.textSecondary) {
                    store.clearCommandProfileEditorFeedback()
                    profileDraft = store.makeCommandProfileDraft(for: profile)
                    isProfileEditorPresented = true
                }
                .disabled(!store.hasConnection || store.isMutatingCommandProfile)

                settingsButton("[set startup]", tint: theme.accent) {
                    store.setStartupDefaultCommandProfile(profile.id)
                }
                .disabled(!store.hasConnection || store.selectedCommandProfileID == profile.id)

                settingsButton("[delete]", tint: DevysColors.warning) {
                    store.deleteCommandProfile(id: profile.id)
                }
                .disabled(!store.hasConnection || profile.isDefault || store.isMutatingCommandProfile)
            }
        }
        .padding(.vertical, DevysSpacing.space1)
    }

    var sessionBehaviorSection: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("Legacy Session Behavior")

            Toggle(
                "Auto-connect legacy mac-server on launch",
                isOn: Binding(
                    get: { store.setupAutoConnectOnLaunch },
                    set: { newValue in
                        store.setupAutoConnectOnLaunch = newValue
                        store.persistSessionBehaviorPreferences()
                    }
                )
            )
            .font(DevysTypography.xs)
            .tint(theme.accent)

            Toggle(
                "Auto-resume last legacy session",
                isOn: Binding(
                    get: { store.setupAutoResumeLastSession },
                    set: { newValue in
                        store.setupAutoResumeLastSession = newValue
                        store.persistSessionBehaviorPreferences()
                    }
                )
            )
            .font(DevysTypography.xs)
            .tint(theme.accent)

            HStack(spacing: DevysSpacing.space2) {
                settingsButton("[launch]", tint: theme.accent) {
                    store.launchTerminal()
                }
                .disabled(!store.canLaunchTerminal)

                settingsButton("[reconnect]", tint: theme.textSecondary) {
                    store.reconnectTerminal()
                }
                .disabled(!store.terminalSession.chromeState.canReconnect || store.reconnectAttemptMessage != nil)

                settingsButton("[stop]", tint: DevysColors.warning) {
                    store.stopActiveRun()
                }
                .disabled(store.terminalSession.sessionID == nil)

                settingsButton("[close]", tint: theme.textTertiary) {
                    store.disconnectTerminal()
                }
                .disabled(!store.terminalSession.chromeState.canDisconnect)
            }

            if let reconnectStatus = store.reconnectAttemptMessage {
                Text(reconnectStatus)
                    .font(DevysTypography.xs)
                    .foregroundStyle(DevysColors.warning)
            }
        }
        .terminalCardStyle(theme: theme)
    }

    var diagnosticsSection: some View {
        let telemetry = store.readinessTelemetry
        return VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("Diagnostics")

            Text("connect attempts: \(telemetry.connectionAttempts)")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            Text("last time-to-connected: \(formatMilliseconds(telemetry.lastTimeToConnectedMs))")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            Text("launch success: \(telemetry.terminalLaunchSuccesses)/\(telemetry.terminalLaunchAttempts)")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            Text("last time-to-prompt: \(formatMilliseconds(telemetry.lastTimeToPromptMs))")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            Text("reconnect success: \(telemetry.reconnectSuccesses)/\(telemetry.reconnectAttempts)")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            Text("last reconnect latency: \(formatMilliseconds(telemetry.lastReconnectLatencyMs))")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            Text("profile launch success: \(profileLaunchSuccessText(for: telemetry))")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            Text("last telemetry update: \(formatDateTime(telemetry.lastUpdatedAt))")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            if let profileID = telemetry.lastProfileLaunchProfileID {
                Text("last profile: \(profileID)")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }

            if let profileError = telemetry.lastProfileLaunchError {
                Text("last profile launch error: \(profileError)")
                    .font(DevysTypography.xs)
                    .foregroundStyle(DevysColors.warning)
            }

            let terminalTelemetry = store.terminalSession.telemetry
            Text(
                "terminal attach/reconnect/stale: " +
                    "\(terminalTelemetry.attachCount)/\(terminalTelemetry.reconnectCount)/" +
                    "\(terminalTelemetry.staleCursorRecoveryCount)"
            )
            .font(DevysTypography.xs)
            .foregroundStyle(theme.textSecondary)

            settingsButton("[reset metrics]", tint: theme.textSecondary) {
                store.resetReadinessTelemetry()
            }
        }
        .terminalCardStyle(theme: theme)
    }

    func cardTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DevysTypography.heading)
            .foregroundStyle(theme.textSecondary)
    }

    func settingsButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DevysTypography.sm)
                .foregroundStyle(tint)
                .padding(.horizontal, DevysSpacing.space2)
                .padding(.vertical, DevysSpacing.space1)
                .background(theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
        }
        .buttonStyle(.plain)
    }

    func commandProfilePickerLabel(for profile: CommandProfile) -> String {
        let commandText: String
        if let command = profile.command, !command.isEmpty {
            commandText = command
        } else {
            commandText = "shell"
        }
        return "\(profile.label) [\(profile.id)] · \(commandText)"
    }

    func commandProfileDetailText(for profile: CommandProfile) -> String {
        let commandText = profile.command?.isEmpty == false ? profile.command ?? "" : "shell"
        let capabilityText: String
        if profile.requiredCapabilities.isEmpty {
            capabilityText = "none"
        } else {
            capabilityText = profile.requiredCapabilities.map(\.rawValue).joined(separator: ",")
        }
        return "\(commandText) args:\(profile.arguments.count) env:\(profile.environment.count) req:\(capabilityText)"
    }

    func formatMilliseconds(_ value: Int?) -> String {
        guard let value else { return "n/a" }
        return "\(value)ms"
    }

    func formatDateTime(_ date: Date?) -> String {
        guard let date else { return "n/a" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    func profileLaunchSuccessText(for telemetry: IOSClientConnectionStore.ReadinessTelemetrySnapshot) -> String {
        let ratio = "\(telemetry.profileLaunchSuccesses)/\(telemetry.profileLaunchAttempts)"
        if let percent = telemetry.profileLaunchSuccessRatePercent {
            return "\(ratio) (\(percent)%)"
        }
        return ratio
    }
}
