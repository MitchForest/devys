import ComposableArchitecture
import GhosttyTerminal
import GhosttyTerminalCore
import RemoteFeatures
import RemoteCore
import SSH
import SwiftUI
import UI
import UIKit

struct IOSRemoteSessionView: View {
    @Bindable var store: StoreOf<RemoteTerminalFeature>
    let hostKeyValidator: SSHHostKeyValidator?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var terminalController = GhosttyRemoteTerminalController()
    @State private var isKeyboardFocused = true
    @State private var isCtrlLatched = false
    @State private var isAltLatched = false
    @State private var isSelectionMode = false

    var body: some View {
        if let session = store.activeSession,
           let repository = repository(for: session),
           let worktree = worktree(for: session) {
            NavigationStack {
                VStack(spacing: Spacing.space3) {
                    header(session, repository: repository, worktree: worktree)
                    terminalSurface
                    accessoryRow
                }
                .padding(.horizontal, Spacing.space3)
                .padding(.top, Spacing.space2)
                .padding(.bottom, Spacing.space3)
                .background(theme.base.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            terminalController.disconnect()
                            store.send(.dismissActiveSession)
                            dismiss()
                        }
                        .tint(theme.text)
                    }

                    ToolbarItem(placement: .principal) {
                        Menu {
                            Section("Authority") {
                                Text(repository.authority.railDisplayName)
                            }
                            Section("Branch") {
                                Text(worktree.branchName)
                            }
                            Section("Host") {
                                Text(repository.authority.hostLabel)
                            }
                            Section("Session") {
                                Text(session.session.sessionName)
                            }
                        } label: {
                            HStack(spacing: Spacing.space1) {
                                Text(session.title)
                                    .font(Typography.label.weight(.semibold))
                                    .foregroundStyle(theme.text)
                                Image(systemName: "chevron.down")
                                    .font(Typography.micro.weight(.semibold))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.send(.reconnectActiveSession)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .tint(theme.textSecondary)
                    }
                }
                .task(id: session.connectRequestID) {
                    let prepared = SSHRemotePreparedShellSession(
                        session: session.session,
                        remoteAttachCommand: session.remoteAttachCommand
                    )
                    terminalController.connect(
                        configuration: repository.connection,
                        preparedSession: prepared,
                        hostKeyValidator: hostKeyValidator
                    )
                }
            }
        } else {
            EmptyView()
        }
    }

    private var terminalSurface: some View {
        ZStack(alignment: .topLeading) {
            GhosttyTerminalView(
                surfaceState: terminalController.surfaceState,
                frameProjection: terminalController.frameProjection,
                appearance: .defaultDark,
                selectionMode: isSelectionMode,
                onTap: {
                    isKeyboardFocused = true
                },
                onSelectionBegin: { row, col in
                    terminalController.beginSelection(row: row, col: col)
                },
                onSelectionMove: { row, col in
                    terminalController.updateSelection(row: row, col: col)
                },
                onSelectionEnd: {
                    terminalController.finishSelection()
                },
                onSelectWord: { row, col in
                    terminalController.selectWord(row: row, col: col)
                },
                onScroll: { lines in
                    terminalController.scrollViewport(lines: lines)
                },
                onViewportSizeChange: { _, cols, rows, cellWidthPx, cellHeightPx in
                    terminalController.resize(
                        cols: cols,
                        rows: rows,
                        cellWidthPx: cellWidthPx,
                        cellHeightPx: cellHeightPx
                    )
                }
            )

            IOSGhosttyTerminalInputCaptureView(
                isFocused: $isKeyboardFocused,
                onInput: handleHardwareInput
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)

            if case .connecting = terminalController.connectionState {
                connectionOverlay("Connecting…")
            } else if case .reconnecting = terminalController.connectionState {
                connectionOverlay("Reconnecting…")
            } else if case .failed(let message) = terminalController.connectionState {
                connectionOverlay(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .elevation(.card)
    }

    private var accessoryRow: some View {
        IOSGhosttyTerminalAccessoryRow(
            isCtrlLatched: isCtrlLatched,
            isAltLatched: isAltLatched,
            isSelectionMode: isSelectionMode,
            onToggleCtrl: { isCtrlLatched.toggle() },
            onToggleAlt: { isAltLatched.toggle() },
            onToggleSelectionMode: {
                isSelectionMode.toggle()
                if isSelectionMode == false {
                    terminalController.clearSelection()
                }
            },
            onKeyPress: { key in
                terminalController.sendSpecialKey(key)
            },
            onPaste: pasteFromClipboard,
            onCopy: copySelectionOrScreen,
            onTop: {
                terminalController.scrollViewport(
                    lines: -(terminalController.surfaceState.scrollbackRows + terminalController.surfaceState.rows)
                )
            },
            onBottom: {
                terminalController.scrollViewport(
                    lines: terminalController.surfaceState.scrollbackRows + terminalController.surfaceState.rows
                )
            }
        )
        .padding(Spacing.space4)
        .elevation(.card)
    }

    private func header(
        _ session: ActiveRemoteSession,
        repository: RemoteRepositoryRecord,
        worktree: RemoteWorktree
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            HStack(spacing: Spacing.space2) {
                Text(connectionStatusTitle)
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)

                Text("•")
                    .font(Typography.micro)
                    .foregroundStyle(theme.textTertiary)

                Text(statusDetail)
                    .font(Typography.micro)
                    .foregroundStyle(theme.textTertiary)

                Spacer()

                if let currentDirectory = terminalController.currentDirectory,
                   currentDirectory.isEmpty == false {
                    Text(currentDirectory)
                        .font(Typography.micro)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            if let errorMessage = session.errorMessage ?? terminalController.lastErrorDescription,
               errorMessage.isEmpty == false {
                Text(errorMessage)
                    .font(Typography.caption)
                    .foregroundStyle(theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.space3)
                    .padding(.vertical, Spacing.space2)
                    .background(
                        theme.errorSubtle,
                        in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionStatusTitle: String {
        switch terminalController.connectionState {
        case .idle:
            "Idle"
        case .connecting:
            "Connecting"
        case .connected:
            "Connected"
        case .reconnecting:
            "Reconnecting"
        case .failed:
            "Failed"
        case .closed:
            "Closed"
        }
    }

    private var statusDetail: String {
        let size = "\(terminalController.surfaceState.cols)x\(terminalController.surfaceState.rows)"
        return "\(size) • bell \(terminalController.bellCount)"
    }

    private func connectionOverlay(_ title: String) -> some View {
        VStack {
            Text(title)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(theme.text)
                .padding(.horizontal, Spacing.space3)
                .padding(.vertical, Spacing.space2)
                .elevation(.popover)
            Spacer()
        }
        .padding(Spacing.space3)
    }

    private func handleHardwareInput(_ input: IOSGhosttyTerminalHardwareInput) {
        switch input {
        case .text(let text):
            if isCtrlLatched, let character = text.first, text.count == 1 {
                terminalController.sendControlCharacter(character)
            } else if isAltLatched {
                terminalController.sendAltText(text)
            } else {
                terminalController.sendText(text)
            }
        case let .special(key):
            terminalController.sendSpecialKey(key)
        case let .control(character, withAlt):
            if withAlt {
                terminalController.sendAltText(String(character))
            }
            terminalController.sendControlCharacter(character)
        case let .altText(text):
            terminalController.sendAltText(text)
        }

        isCtrlLatched = false
        isAltLatched = false
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, text.isEmpty == false else { return }
        terminalController.pasteText(text)
    }

    private func copySelectionOrScreen() {
        if let selected = terminalController.selectionText() {
            UIPasteboard.general.string = selected
            return
        }

        Task {
            let screenText = await terminalController.screenText()
            guard screenText.isEmpty == false else { return }
            UIPasteboard.general.string = screenText
        }
    }

    private func repository(
        for session: ActiveRemoteSession
    ) -> RemoteRepositoryRecord? {
        store.repositories.first { $0.id == session.repositoryID }
    }

    private func worktree(
        for session: ActiveRemoteSession
    ) -> RemoteWorktree? {
        store.worktreesByRepository[session.repositoryID]?.first { $0.id == session.worktreeID }
    }
}
