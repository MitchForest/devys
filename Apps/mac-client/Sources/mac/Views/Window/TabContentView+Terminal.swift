import Foundation
import GhosttyTerminal
import Observation
import SwiftUI
import UI

extension TabContentView {
    @ViewBuilder
    func terminalContentView(
        session: GhosttyTerminalSession,
        controller: HostedLocalTerminalController
    ) -> some View {
        HostedTerminalPaneView(
            session: session,
            controller: controller,
            terminalAppearance: terminalAppearance,
            onTerminalPerformanceCheckpoint: onTerminalPerformanceCheckpoint,
            terminalCheckpointHandler: terminalCheckpointHandler,
            terminalInteractiveFrameHandler: terminalInteractiveFrameHandler,
            terminalViewportHandler: terminalViewportHandler,
            terminalStartupView: terminalStartupView
        )
    }

    func terminalCheckpointHandler(
        _ sessionID: UUID,
        _ checkpoint: TerminalOpenPerformanceTracker.Checkpoint
    ) -> () -> Void {
        {
            onTerminalPerformanceCheckpoint(sessionID, checkpoint)
        }
    }

    func terminalInteractiveFrameHandler(
        _ sessionID: UUID,
        controller: HostedLocalTerminalController
    ) -> () -> Void {
        {
            onTerminalPerformanceCheckpoint(sessionID, .firstInteractiveFrame)
            controller.noteFirstInteractiveFrame()
        }
    }

    func terminalViewportHandler(
        _ controller: HostedLocalTerminalController
    ) -> (CGSize, Int, Int, Int, Int) -> Void {
        { _, cols, rows, cellWidthPx, cellHeightPx in
            controller.updateViewport(
                cols: cols,
                rows: rows,
                cellWidthPx: cellWidthPx,
                cellHeightPx: cellHeightPx
            )
        }
    }

    func terminalStartupView(for session: GhosttyTerminalSession) -> some View {
        HStack(alignment: .top, spacing: Spacing.space3) {
            Group {
                if session.startupPhase == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(Typography.body.weight(.semibold))
            .foregroundStyle(session.startupPhase == .failed ? theme.warning : theme.text)

            VStack(alignment: .leading, spacing: Spacing.space1) {
                Text(terminalStartupTitle(for: session))
                    .font(Typography.label.weight(.semibold))
                    .foregroundStyle(theme.text)

                let subtitle = terminalStartupSubtitle(for: session)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typography.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(.horizontal, Spacing.space3)
        .padding(.vertical, Spacing.space2)
        .elevation(.popover)
    }

    func terminalStartupTitle(for session: GhosttyTerminalSession) -> String {
        switch session.startupPhase {
        case .startingHost:
            "Starting Terminal Host"
        case .awaitingViewport:
            "Measuring Terminal"
        case .startingShell:
            "Starting Shell"
        case .ready:
            session.tabTitle
        case .failed:
            "Terminal Startup Failed"
        }
    }

    func terminalStartupSubtitle(for session: GhosttyTerminalSession) -> String {
        switch session.startupPhase {
        case .startingHost:
            "Preparing the detached terminal runtime."
        case .awaitingViewport:
            "Waiting for the terminal view to report its real size before starting the session."
        case .startingShell:
            "Attaching the hosted session and waiting for the first frame."
        case .ready:
            ""
        case .failed:
            session.lastErrorDescription ?? "The terminal session could not be started."
        }
    }
}

private struct HostedTerminalPaneView: View {
    @Bindable var session: GhosttyTerminalSession
    @Bindable var controller: HostedLocalTerminalController

    let terminalAppearance: GhosttyTerminalAppearance
    let onTerminalPerformanceCheckpoint: (UUID, TerminalOpenPerformanceTracker.Checkpoint) -> Void
    let terminalCheckpointHandler: (UUID, TerminalOpenPerformanceTracker.Checkpoint) -> () -> Void
    let terminalInteractiveFrameHandler: (UUID, HostedLocalTerminalController) -> () -> Void
    let terminalViewportHandler: (HostedLocalTerminalController) -> (CGSize, Int, Int, Int, Int) -> Void
    let terminalStartupView: (GhosttyTerminalSession) -> AnyView

    init(
        session: GhosttyTerminalSession,
        controller: HostedLocalTerminalController,
        terminalAppearance: GhosttyTerminalAppearance,
        onTerminalPerformanceCheckpoint: @escaping (UUID, TerminalOpenPerformanceTracker.Checkpoint) -> Void,
        terminalCheckpointHandler: @escaping (UUID, TerminalOpenPerformanceTracker.Checkpoint) -> () -> Void,
        terminalInteractiveFrameHandler: @escaping (UUID, HostedLocalTerminalController) -> () -> Void,
        terminalViewportHandler: @escaping (HostedLocalTerminalController) -> (CGSize, Int, Int, Int, Int) -> Void,
        terminalStartupView: @escaping (GhosttyTerminalSession) -> some View
    ) {
        self.session = session
        self.controller = controller
        self.terminalAppearance = terminalAppearance
        self.onTerminalPerformanceCheckpoint = onTerminalPerformanceCheckpoint
        self.terminalCheckpointHandler = terminalCheckpointHandler
        self.terminalInteractiveFrameHandler = terminalInteractiveFrameHandler
        self.terminalViewportHandler = terminalViewportHandler
        self.terminalStartupView = { session in AnyView(terminalStartupView(session)) }
    }

    var body: some View {
        ZStack {
            GhosttyTerminalView(
                surfaceState: controller.surfaceState,
                frameProjection: controller.frameProjection,
                appearance: terminalAppearance,
                selectionMode: true,
                focusRequestID: session.focusRequestID,
                onFirstAtlasMutation: terminalCheckpointHandler(session.id, .firstAtlasMutation),
                onFirstFrameCommit: terminalCheckpointHandler(session.id, .firstFrameCommit),
                onFirstInteractiveFrame: terminalInteractiveFrameHandler(
                    session.id,
                    controller
                ),
                onRenderFailure: { message in
                    controller.failStartup(message: message)
                },
                onSelectionBegin: { row, col in
                    controller.beginSelection(row: row, col: col)
                },
                onSelectionMove: { row, col in
                    controller.updateSelection(row: row, col: col)
                },
                onSelectionEnd: {
                    controller.finishSelection()
                },
                onSelectWord: { row, col in
                    controller.selectWord(row: row, col: col)
                },
                onClearSelection: {
                    controller.clearSelection()
                },
                onScroll: { lines in
                    controller.scrollViewport(lines: lines)
                },
                onViewportSizeChange: terminalViewportHandler(controller),
                onSendText: { text in
                    controller.sendText(text)
                },
                onSendSpecialKey: { key in
                    controller.sendSpecialKey(key)
                },
                onSendControlCharacter: { character in
                    controller.sendControlCharacter(character)
                },
                onSendAltText: { text in
                    controller.sendAltText(text)
                },
                onPasteText: { text in
                    controller.pasteText(text)
                },
                selectionTextProvider: {
                    controller.selectionText()
                }
            )

            if session.startupPhase != .ready {
                VStack {
                    HStack {
                        terminalStartupView(session)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.space3)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            onTerminalPerformanceCheckpoint(session.id, .tabVisible)
            if session.startupPhase != .startingHost {
                controller.attachIfNeeded()
            }
        }
        .onChange(of: session.startupPhase) { _, startupPhase in
            if startupPhase == .startingShell || startupPhase == .ready {
                controller.attachIfNeeded()
            }
        }
    }
}
