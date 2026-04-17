import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

#if canImport(GhosttyKit) && os(macOS)
import GhosttyKit

public struct GhosttyTerminalView: NSViewRepresentable {
    public typealias NSViewType = NSView

    public let session: GhosttyTerminalSession
    public let onOpenURL: ((URL) -> Void)?

    public init(
        session: GhosttyTerminalSession,
        onOpenURL: ((URL) -> Void)? = nil
    ) {
        self.session = session
        self.onOpenURL = onOpenURL
    }

    public func makeNSView(context: Context) -> NSView {
        GhosttySurfaceHostView(session: session, onOpenURL: onOpenURL)
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let hostView = nsView as? GhosttySurfaceHostView else { return }
        hostView.bind(session: session, onOpenURL: onOpenURL)
    }
}

// swiftlint:disable type_body_length
@MainActor
final class GhosttySurfaceHostView: NSView {
    let session: GhosttyTerminalSession
    var onOpenURL: ((URL) -> Void)?

    var rendererHealthy = true
    var isReadonly = false
    var focused = false
    var markedText = NSMutableAttributedString()
    var keyTextAccumulator: [String]?
    var lastPerformKeyEvent: TimeInterval?
    var focusTransferState = GhosttyFocusTransferState()

    var lastHandledFocusRequestID = 0
    var hasAppliedInitialStageCommand = false

    let surfaceBox = GhosttySurfaceBox()
    var eventMonitor: Any?

    override var acceptsFirstResponder: Bool {
        true
    }

    init(
        session: GhosttyTerminalSession,
        onOpenURL: ((URL) -> Void)?
    ) {
        self.session = session
        self.onOpenURL = onOpenURL
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 640))
        surfaceBox.bind(hostView: self)

        session.shutdownHandler = { [weak self] in
            self?.shutdown()
        }
        session.focusRequestHandler = { [weak self] requestID in
            self?.handleFocusRequest(requestID)
        }

        installLocalEventMonitor()
        createSurfaceIfNeeded()
        updateTrackingAreas()
        applyPendingFocusRequest()
        applyPendingStageCommand()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func bind(
        session: GhosttyTerminalSession,
        onOpenURL: ((URL) -> Void)?
    ) {
        guard session.id == self.session.id else { return }
        self.onOpenURL = onOpenURL
        session.focusRequestHandler = { [weak self] requestID in
            self?.handleFocusRequest(requestID)
        }
        createSurfaceIfNeeded()
        syncSurfaceMetrics()
        applyPendingFocusRequest()
        applyPendingStageCommand()
    }

    func handleCloseRequested(processAlive: Bool) {
        if !processAlive {
            session.isRunning = false
        }
    }

    func updateCurrentDirectory(_ path: String) {
        session.currentDirectory = URL(fileURLWithPath: path).standardizedFileURL
    }

    func readClipboard(
        surface: ghostty_surface_t,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard location == GHOSTTY_CLIPBOARD_STANDARD,
              let value = NSPasteboard.general.string(forType: .string)
        else {
            return false
        }

        value.withCString { pointer in
            ghostty_surface_complete_clipboard_request(surface, pointer, state, true)
        }
        return true
    }

    func confirmReadClipboard(
        surface: ghostty_surface_t,
        text: String?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard request == GHOSTTY_CLIPBOARD_REQUEST_PASTE,
              let text
        else {
            return
        }

        text.withCString { pointer in
            ghostty_surface_complete_clipboard_request(surface, pointer, state, true)
        }
    }

    func writeClipboard(
        location: ghostty_clipboard_e,
        string: String?,
        confirm: Bool
    ) {
        guard location == GHOSTTY_CLIPBOARD_STANDARD,
              let data = string?.nilIfEmpty
        else {
            return
        }

        _ = confirm
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(data, forType: .string)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            session.shutdownHandler = nil
            session.focusRequestHandler = nil
            invalidateEventMonitor()
            shutdown()
            return
        }
        syncSurfaceMetrics()
        if window?.firstResponder === self {
            focusDidChange(true)
        }
        applyPendingFocusRequest()
    }

    override func layout() {
        super.layout()
        syncSurfaceMetrics()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self
            )
        )
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncSurfaceMetrics()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            focusDidChange(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            focusDidChange(false)
        }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        guard surface != nil else {
            interpretKeyEvents([event])
            return
        }

        handleKeyDown(event)
    }

    override func keyUp(with event: NSEvent) {
        guard surface != nil else {
            super.keyUp(with: event)
            return
        }

        handleKeyUp(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard surface != nil else {
            super.flagsChanged(with: event)
            return
        }

        handleFlagsChanged(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handlePerformKeyEquivalent(event)
    }

    override func doCommand(by selector: Selector) {
        handleDoCommand(by: selector)
    }

    override func mouseDown(with event: NSEvent) {
        guard surface != nil else {
            super.mouseDown(with: event)
            return
        }

        handleMouseDown(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard surface != nil else {
            super.mouseUp(with: event)
            return
        }

        handleMouseUp(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard surface != nil else {
            super.rightMouseDown(with: event)
            return
        }

        handleRightMouseDown(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard surface != nil else {
            super.rightMouseUp(with: event)
            return
        }

        handleRightMouseUp(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard surface != nil else {
            super.otherMouseDown(with: event)
            return
        }

        handleOtherMouseDown(event)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard surface != nil else {
            super.otherMouseUp(with: event)
            return
        }

        handleOtherMouseUp(event)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseEntered(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseExited(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_pos(surface, -1, -1, ghosttyMods(from: event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }

        var mods: ghostty_input_scroll_mods_t = 0
        if event.hasPreciseScrollingDeltas {
            mods |= 1
        }

        let momentumPhase = Int32(event.momentumPhase.rawValue)
        mods |= momentumPhase << 1

        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, mods)
    }

    func createSurfaceIfNeeded() {
        guard surface == nil else { return }
        let sessionID = self.session.id.uuidString
        let runtimeSummary = GhosttyRuntimeIdentity.summary

        GhosttyRuntimeIdentity.logger.notice(
            "ghostty_surface_request session=\(sessionID, privacy: .public) \(runtimeSummary, privacy: .public)"
        )

        guard let createdSurface = GhosttyAppBridge.shared.makeSurface(
            for: self,
            session: session,
            surfaceBox: surfaceBox
        ) else {
            session.lastErrorDescription = "Failed to create Ghostty surface."
            session.isRunning = false
            GhosttyRuntimeIdentity.logger.error(
                "ghostty_surface_unavailable session=\(sessionID, privacy: .public) \(runtimeSummary, privacy: .public)"
            )
            return
        }

        surfaceBox.attachSurface(createdSurface)
        session.lastErrorDescription = nil
        GhosttyRuntimeIdentity.logger.notice(
            "ghostty_surface_ready session=\(sessionID, privacy: .public) \(runtimeSummary, privacy: .public)"
        )
        syncSurfaceMetrics()
        applyPendingStageCommand()
    }

    func shutdown() {
        let surface = surfaceBox.prepareForShutdown()
        GhosttyAppBridge.shared.unregister(surfaceBox)
        let sessionID = self.session.id.uuidString
        let runtimeSummary = GhosttyRuntimeIdentity.summary
        GhosttyRuntimeIdentity.logger.notice(
            "ghostty_surface_shutdown session=\(sessionID, privacy: .public) \(runtimeSummary, privacy: .public)"
        )
        GhosttyAppBridge.shared.destroySurface(surface)
    }

    func handleFocusRequest(_ requestID: Int) {
        guard requestID > lastHandledFocusRequestID else { return }
        guard claimKeyboardFocusIfPossible() else { return }
        lastHandledFocusRequestID = requestID
    }

    func applyPendingFocusRequest() {
        handleFocusRequest(session.focusRequestID)
    }

    func applyPendingStageCommand() {
        guard !hasAppliedInitialStageCommand,
              let stagedCommand = session.stagedCommand,
              !stagedCommand.isEmpty,
              surface != nil
        else {
            return
        }
        guard claimKeyboardFocusIfPossible() else { return }

        stageCommand(stagedCommand)
        hasAppliedInitialStageCommand = true
        session.stagedCommand = nil
    }

    @discardableResult
    func claimKeyboardFocusIfPossible() -> Bool {
        guard let window else { return false }
        if window.firstResponder === self {
            return true
        }

        window.makeFirstResponder(self)
        return window.firstResponder === self
    }

    func focusDidChange(_ focused: Bool) {
        guard self.focused != focused else { return }
        self.focused = focused

        if !focused {
            focusTransferState.clear()
        }

        if let surface {
            ghostty_surface_set_focus(surface, focused)
        }
    }

    func syncSurfaceMetrics() {
        guard let surface, !bounds.isEmpty else { return }

        let backingBounds = convertToBacking(bounds)
        let scaleFactor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        ghostty_surface_set_content_scale(
            surface,
            scaleFactor,
            scaleFactor
        )
        ghostty_surface_set_size(
            surface,
            UInt32(max(1, Int(backingBounds.width.rounded(.toNearestOrEven)))),
            UInt32(max(1, Int(backingBounds.height.rounded(.toNearestOrEven))))
        )
    }

    func stageCommand(_ command: String) {
        let preservedClipboard = NSPasteboard.general.string(forType: .string)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)

        defer {
            pasteboard.clearContents()
            if let preservedClipboard {
                pasteboard.setString(preservedClipboard, forType: .string)
            }
        }

        let flags: NSEvent.ModifierFlags = [.command]
        guard let keyDown = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        ),
        let keyUp = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        ) else {
            return
        }

        _ = sendKeyAction(GHOSTTY_ACTION_PRESS, event: keyDown)
        _ = sendKeyAction(GHOSTTY_ACTION_RELEASE, event: keyUp)
    }

    func sendMouseButton(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e
    ) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, state, button, ghosttyMods(from: event.modifierFlags))
    }

    func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let location = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(
            surface,
            location.x,
            bounds.height - location.y,
            ghosttyMods(from: event.modifierFlags)
        )
    }

    func updateHoveredURL(_ hoveredURL: String?) {
        toolTip = hoveredURL
        discardCursorRects()
    }

    func openURL(_ rawURL: String?) {
        guard let rawURL else { return }

        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme != nil else {
            return
        }

        onOpenURL?(url)
    }

    func invalidateEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    override func resetCursorRects() {
        if toolTip != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        } else {
            addCursorRect(bounds, cursor: .iBeam)
        }
    }

    var surface: ghostty_surface_t? {
        surfaceBox.surface
    }
}
// swiftlint:enable type_body_length

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#else

public struct GhosttyTerminalView: View {
    public let session: GhosttyTerminalSession
    public let onOpenURL: ((URL) -> Void)?

    public init(
        session: GhosttyTerminalSession,
        onOpenURL: ((URL) -> Void)? = nil
    ) {
        self.session = session
        self.onOpenURL = onOpenURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("terminal_unavailable")
                .font(.headline)
            Text("GhosttyKit is not linked for this build.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let error = session.lastErrorDescription {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

#endif
