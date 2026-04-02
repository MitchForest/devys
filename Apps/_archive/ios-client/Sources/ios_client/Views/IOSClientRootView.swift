import ServerClient
import ServerProtocol
import SwiftUI
import TerminalCore
import UI

struct IOSClientRootView: View {
    @Environment(\.devysTheme) var theme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State var store: IOSClientConnectionStore
    @State var isKeyboardFocused = false
    @State var selectionMode = false
    @State var showSetupPanels: Bool
    @State var presentedSetupSheet: PresentedSetupSheet?
    @State var isSettingsPresented = false

    init() {
        let store = IOSClientConnectionStore()
        _store = State(initialValue: store)
        _showSetupPanels = State(initialValue: false)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DevysSpacing.space3) {
                        header

                        sshProfilesCard

                        if shouldShowQuickCommandBar {
                            quickCommandBar
                        }

                        if shouldShowPrimaryCards {
                            connectionCard
                            if !store.hasCompletedSetup {
                                setupCard
                            }
                            launchCard
                        }

                        terminalCard(availableHeight: proxy.size.height)

                        if shouldShowPrimaryCards {
                            streamCard
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(DevysSpacing.space4)
                }
                .background(theme.base)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("ios-client")
        }
        .onChange(of: scenePhase) { _, newValue in
            store.handleScenePhaseChange(newValue)
        }
        .onChange(of: store.hasCompletedSetup) { _, completed in
            if completed {
                showSetupPanels = false
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            IOSClientSettingsSheet(store: store)
        }
        .task {
            store.bootstrapConnectionIfNeeded()
        }
    }
}

extension IOSClientRootView {
    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DevysSpacing.space2) {
                Text("Devys SSH")
                    .font(DevysTypography.title)
                    .foregroundStyle(theme.text)

                Spacer(minLength: 0)

                terminalButton(
                    showSetupPanels ? "[hide legacy tools]" : "[show legacy tools]",
                    tint: theme.textSecondary
                ) {
                    showSetupPanels.toggle()
                }

                terminalButton("[settings]", tint: theme.textSecondary) {
                    isSettingsPresented = true
                }
            }

            Text("Terminus-style SSH terminal. Connect directly to any SSH host, including Tailscale nodes.")
                .font(DevysTypography.sm)
                .foregroundStyle(theme.textSecondary)
        }
    }

    var quickCommandBar: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("Legacy Command")

            Text("profile: \(store.selectedCommandProfile.label) · mode: \(store.launchMode.label.lowercased())")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: DevysSpacing.space2) {
                if store.hasConnection {
                    terminalButton("[launch]", tint: theme.accent) {
                        store.launchTerminal()
                        isKeyboardFocused = true
                    }
                    .disabled(!store.canLaunchTerminal)
                } else {
                    terminalButton("[connect]", tint: theme.accent) {
                        store.connect()
                    }
                    .disabled(store.state == .connecting)
                }

                terminalButton("[settings]", tint: theme.textSecondary) {
                    isSettingsPresented = true
                }

                if let validationMessage = store.launchValidationMessage {
                    Text(validationMessage)
                        .font(DevysTypography.xs)
                        .foregroundStyle(DevysColors.warning)
                        .lineLimit(2)
                } else {
                    Spacer(minLength: 0)
                }

                statusPill
            }
        }
        .terminalCardStyle(theme: theme)
    }

    var connectionCard: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("Legacy mac-server")

            TextField("http://100.64.0.1:8787", text: $store.serverURLText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)

            HStack(spacing: DevysSpacing.space2) {
                terminalButton("[connect]", tint: theme.accent) {
                    store.connect()
                }
                .disabled(store.state == .connecting)

                terminalButton("[disconnect]", tint: theme.textSecondary) {
                    store.disconnect()
                }

                Spacer(minLength: 0)

                statusPill
            }

            if let health = store.health {
                Text("server: \(health.serverName)  version: \(health.version)")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }

            if let capabilities = store.capabilities {
                HStack(spacing: DevysSpacing.space2) {
                    capabilityTag("tmux", enabled: capabilities.tmuxAvailable)
                    capabilityTag("claude", enabled: capabilities.claudeAvailable)
                    capabilityTag("codex", enabled: capabilities.codexAvailable)
                }
            }
        }
        .terminalCardStyle(theme: theme)
    }

    var launchCard: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("Legacy Launch")

            TextField("/Users/you/path/to/repo", text: $store.workspacePathText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)

            Picker("Command Profile", selection: $store.selectedCommandProfileID) {
                ForEach(store.commandProfiles, id: \.id) { profile in
                    Text(commandProfilePickerLabel(for: profile)).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: store.selectedCommandProfileID) { _, _ in
                store.handleSelectedCommandProfileChanged()
            }

            Picker("Session Type", selection: $store.launchMode) {
                ForEach(IOSClientConnectionStore.TerminalLaunchMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: store.launchMode) { _, _ in
                store.handleLaunchModeChanged()
            }

            if store.launchMode == .attachExisting {
                Picker("Session", selection: $store.selectedSessionID) {
                    Text("Select Session").tag(Optional<String>.none)
                    ForEach(store.sessions, id: \.id) { session in
                        Text(store.sessionPickerLabel(for: session)).tag(Optional(session.id))
                    }
                }
                .pickerStyle(.menu)
                .font(DevysTypography.xs)
            }

            if let validationMessage = store.launchValidationMessage {
                Text(validationMessage)
                    .font(DevysTypography.xs)
                    .foregroundStyle(DevysColors.warning)
            }

            HStack(spacing: DevysSpacing.space2) {
                terminalButton("[launch]", tint: theme.accent) {
                    store.launchTerminal()
                    isKeyboardFocused = true
                }
                .disabled(!store.canLaunchTerminal)

                terminalButton("[reconnect]", tint: theme.textSecondary) {
                    store.reconnectTerminal()
                }
                .disabled(!store.terminalSession.chromeState.canReconnect || store.reconnectAttemptMessage != nil)

                terminalButton("[stop]", tint: DevysColors.warning) {
                    store.stopActiveRun()
                }
                .disabled(store.terminalSession.sessionID == nil)

                terminalButton("[close]", tint: theme.textTertiary) {
                    store.disconnectTerminal()
                }
                .disabled(!store.terminalSession.chromeState.canDisconnect)

                terminalButton("[refresh]", tint: theme.textSecondary) {
                    store.refreshSessions()
                    store.refreshCommandProfiles()
                }
                .disabled(!store.hasConnection)

                Spacer(minLength: 0)

                terminalButton(
                    selectionMode ? "[select:on]" : "[select:off]",
                    tint: selectionMode ? theme.accent : theme.textSecondary
                ) {
                    selectionMode.toggle()
                    if !selectionMode {
                        store.clearSelection()
                    }
                }
            }
        }
        .terminalCardStyle(theme: theme)
    }

    func terminalCard(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("Terminal")
            terminalStatusRow
            terminalSurface(availableHeight: availableHeight)
            terminalAccessory
            terminalActionRow
            terminalErrors
            keyboardCapture
        }
        .terminalCardStyle(theme: theme)
    }

    var terminalStatusRow: some View {
        HStack(spacing: DevysSpacing.space2) {
            Text(store.sshTerminalSession.chromeState.subtitle)
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(telemetryText)
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(store.sshTerminalStateText)
                .font(DevysTypography.xs)
                .foregroundStyle(statusColor(for: store.sshTerminalSession.chromeState.connectionStatus))
        }
    }

    func terminalSurface(availableHeight: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            IOSTerminalSurfaceView(
                renderState: store.sshTerminalSession.renderState,
                selectionMode: selectionMode,
                onTap: { isKeyboardFocused = true },
                onSelectionBegin: { row, col in
                    store.beginSelection(row: row, col: col)
                },
                onSelectionMove: { row, col in
                    store.updateSelection(row: row, col: col)
                },
                onSelectionEnd: { store.finishSelection() },
                onSelectWord: { row, col in
                    store.selectWord(row: row, col: col)
                },
                onScroll: { lines in
                    store.scrollViewport(lines: lines)
                },
                onViewportSizeChange: { size in
                    store.updateTerminalViewport(size: size)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: terminalHeight(availableHeight: availableHeight))
            .background(theme.content)
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            )

            if store.sshTerminalSession.renderState.viewportOffset > 0 {
                terminalButton("[bottom]", tint: theme.textSecondary) {
                    store.scrollToBottom()
                }
                .padding(DevysSpacing.space2)
            }
        }
    }

    var terminalAccessory: some View {
        IOSTerminalAccessoryRow(
            isCtrlLatched: store.isCtrlLatched,
            isAltLatched: store.isAltLatched,
            onToggleCtrl: { store.toggleCtrlLatch() },
            onToggleAlt: { store.toggleAltLatch() },
            onKeyPress: { key in
                store.sendSpecialKey(key)
            },
            onPaste: { store.pasteFromClipboard() },
            onCopy: { store.copySelectionOrScreenToClipboard() },
            onTop: { store.scrollToTop() },
            onBottom: { store.scrollToBottom() }
        )
    }

    var terminalActionRow: some View {
        HStack(spacing: DevysSpacing.space2) {
            terminalButton(isKeyboardFocused ? "[keyboard:on]" : "[keyboard]", tint: theme.accent) {
                isKeyboardFocused.toggle()
            }

            terminalButton("[copy]", tint: theme.textSecondary) {
                store.copySelectionOrScreenToClipboard()
            }

            terminalButton("[paste]", tint: theme.textSecondary) {
                store.pasteFromClipboard()
            }

            terminalButton("[clear]", tint: theme.textSecondary) {
                store.clearTerminalOutput()
            }
            .disabled(!store.sshTerminalSession.chromeState.canClearOutput)
        }
    }

    @ViewBuilder
    var terminalErrors: some View {
        if let error = store.sshTerminalSession.chromeState.lastError {
            Text("error: \(error)")
                .font(DevysTypography.xs)
                .foregroundStyle(DevysColors.error)
        }

        if let reconnectStatus = store.reconnectAttemptMessage {
            Text(reconnectStatus)
                .font(DevysTypography.xs)
                .foregroundStyle(DevysColors.warning)
        }
    }

    var keyboardCapture: some View {
        IOSTerminalInputCaptureView(
            isFocused: $isKeyboardFocused,
            appCursorMode: store.sshTerminalSession.appCursorMode,
            onInput: store.sendHardwareInput
        )
        .frame(width: 1, height: 1)
        .opacity(0.01)
    }

    var streamCard: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            cardTitle("Legacy Stream")

            if store.events.isEmpty {
                Text("No events yet")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DevysSpacing.space1) {
                        ForEach(store.events.prefix(20)) { event in
                            Text("#\(event.id) [\(event.type.rawValue)] \(event.message)")
                                .font(DevysTypography.xs)
                                .foregroundStyle(theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .terminalCardStyle(theme: theme)
    }

    var statusPill: some View {
        Text(connectionStatusText)
            .font(DevysTypography.xs)
            .padding(.horizontal, DevysSpacing.space2)
            .padding(.vertical, DevysSpacing.space1)
            .background(statusColor(for: store.sshTerminalSession.chromeState.connectionStatus).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
    }

    var connectionStatusText: String {
        switch store.state {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .failed(let message):
            return message
        }
    }

    var isTerminalActive: Bool {
        store.sshTerminalSession.sessionID != nil
    }

    var shouldShowPrimaryCards: Bool {
        showSetupPanels
    }

    var shouldShowQuickCommandBar: Bool {
        showSetupPanels
    }

    func terminalHeight(availableHeight: CGFloat) -> CGFloat {
        let minHeight = verticalSizeClass == .compact ? 260.0 : 340.0
        let maxHeight = verticalSizeClass == .compact ? 460.0 : 760.0

        let reserved: CGFloat
        if isTerminalActive {
            reserved = shouldShowPrimaryCards ? 420.0 : 190.0
        } else {
            reserved = shouldShowPrimaryCards ? 420.0 : 240.0
        }

        let preferred = max(availableHeight - reserved, minHeight)
        return min(max(preferred, minHeight), maxHeight)
    }

    var telemetryText: String {
        let telemetry = store.sshTerminalSession.telemetry
        return "attach:\(telemetry.attachCount) reconnect:\(telemetry.reconnectCount) " +
            "stale:\(telemetry.staleCursorRecoveryCount)"
    }

    func cardTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DevysTypography.heading)
            .foregroundStyle(theme.textSecondary)
    }

    func capabilityTag(_ name: String, enabled: Bool) -> some View {
        Text(enabled ? "\(name):on" : "\(name):off")
            .font(DevysTypography.xs)
            .foregroundStyle(enabled ? DevysColors.success : DevysColors.warning)
            .padding(.horizontal, DevysSpacing.space2)
            .padding(.vertical, DevysSpacing.space1)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
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

    func terminalButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
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

    func statusColor(for status: RemoteTerminalConnectionStatus) -> Color {
        switch status {
        case .connected:
            return DevysColors.success
        case .connecting, .reconnecting:
            return DevysColors.warning
        case .failed:
            return DevysColors.error
        case .offline:
            return theme.textSecondary
        }
    }
}

extension View {
    func terminalCardStyle(theme: DevysTheme) -> some View {
        self
            .padding(DevysSpacing.space3)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            )
    }
}

#Preview {
    IOSClientRootView()
}
