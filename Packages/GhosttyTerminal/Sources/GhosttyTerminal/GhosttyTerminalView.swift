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

    public init(session: GhosttyTerminalSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> NSView {
        GhosttySurfaceHostView(session: session)
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let hostView = nsView as? GhosttySurfaceHostView else { return }
        hostView.bind(session: session)
    }
}

// swiftlint:disable type_body_length
@MainActor
final class GhosttySurfaceHostView: NSView {
    let session: GhosttyTerminalSession

    var rendererHealthy = true
    var isReadonly = false
    private var lastHandledFocusRequestID = 0
    private var hasAppliedInitialStageCommand = false

    private let surfaceBox = GhosttySurfaceBox()

    override var acceptsFirstResponder: Bool {
        true
    }

    init(session: GhosttyTerminalSession) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 640))
        surfaceBox.bind(hostView: self)

        session.shutdownHandler = { [weak self] in
            self?.shutdown()
        }
        session.focusRequestHandler = { [weak self] requestID in
            self?.handleFocusRequest(requestID)
        }

        createSurfaceIfNeeded()
        updateTrackingAreas()
        applyPendingFocusRequest()
        applyPendingStageCommand()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func bind(session: GhosttyTerminalSession) {
        guard session.id == self.session.id else { return }
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
            shutdown()
            return
        }
        syncSurfaceMetrics()
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
        if accepted, let surface {
            ghostty_surface_set_focus(surface, true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted, let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            super.keyDown(with: event)
            return
        }

        let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        _ = sendKeyEvent(surface: surface, event: event, action: action)
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else {
            super.keyUp(with: event)
            return
        }

        _ = sendKeyEvent(surface: surface, event: event, action: GHOSTTY_ACTION_RELEASE)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else {
            super.flagsChanged(with: event)
            return
        }

        let action = modifierAction(for: event)
        _ = sendKeyEvent(surface: surface, event: event, action: action, text: nil)
    }

    override func mouseDown(with event: NSEvent) {
        claimKeyboardFocusIfPossible()
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    override func mouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    override func rightMouseDown(with event: NSEvent) {
        claimKeyboardFocusIfPossible()
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func otherMouseDown(with event: NSEvent) {
        claimKeyboardFocusIfPossible()
        sendMouseButton(
            event,
            state: GHOSTTY_MOUSE_PRESS,
            button: ghosttyMouseButton(for: event.buttonNumber)
        )
    }

    override func otherMouseUp(with event: NSEvent) {
        sendMouseButton(
            event,
            state: GHOSTTY_MOUSE_RELEASE,
            button: ghosttyMouseButton(for: event.buttonNumber)
        )
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

    private func createSurfaceIfNeeded() {
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

    private func shutdown() {
        let surface = surfaceBox.prepareForShutdown()
        GhosttyAppBridge.shared.unregister(surfaceBox)
        let sessionID = self.session.id.uuidString
        let runtimeSummary = GhosttyRuntimeIdentity.summary
        GhosttyRuntimeIdentity.logger.notice(
            "ghostty_surface_shutdown session=\(sessionID, privacy: .public) \(runtimeSummary, privacy: .public)"
        )
        GhosttyAppBridge.shared.destroySurface(surface)
    }

    private func handleFocusRequest(_ requestID: Int) {
        guard requestID > lastHandledFocusRequestID else { return }
        guard claimKeyboardFocusIfPossible() else { return }
        lastHandledFocusRequestID = requestID
    }

    private func applyPendingFocusRequest() {
        handleFocusRequest(session.focusRequestID)
    }

    private func applyPendingStageCommand() {
        guard !hasAppliedInitialStageCommand,
              let stagedCommand = session.stagedCommand,
              !stagedCommand.isEmpty,
              let surface
        else {
            return
        }
        guard claimKeyboardFocusIfPossible() else { return }

        stageCommand(stagedCommand, on: surface)
        hasAppliedInitialStageCommand = true
        session.stagedCommand = nil
    }

    @discardableResult
    private func claimKeyboardFocusIfPossible() -> Bool {
        guard let window else { return false }
        if window.firstResponder === self {
            return true
        }

        window.makeFirstResponder(self)
        return window.firstResponder === self
    }

    private func syncSurfaceMetrics() {
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

    private func stageCommand(_ command: String, on surface: ghostty_surface_t) {
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

        _ = sendKeyEvent(surface: surface, event: keyDown, action: GHOSTTY_ACTION_PRESS)
        _ = sendKeyEvent(surface: surface, event: keyUp, action: GHOSTTY_ACTION_RELEASE)
    }

    private func sendMouseButton(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e
    ) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, state, button, ghosttyMods(from: event.modifierFlags))
    }

    private func sendMousePosition(_ event: NSEvent) {
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

    override func resetCursorRects() {
        if toolTip != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        } else {
            addCursorRect(bounds, cursor: .iBeam)
        }
    }

    private var surface: ghostty_surface_t? {
        surfaceBox.surface
    }
}
// swiftlint:enable type_body_length

private func sendKeyEvent(
    surface: ghostty_surface_t,
    event: NSEvent,
    action: ghostty_input_action_e,
    text: String? = nil
) -> Bool {
    var keyEvent = ghostty_input_key_s()
    keyEvent.action = action
    keyEvent.keycode = UInt32(event.keyCode)
    keyEvent.mods = ghosttyMods(from: event.modifierFlags)
    keyEvent.consumed_mods = GHOSTTY_MODS_NONE
    keyEvent.unshifted_codepoint = event.charactersIgnoringModifiers?.unicodeScalars.first.map(\.value) ?? 0
    keyEvent.composing = false

    return (text ?? event.characters)?.withCString { characters in
        keyEvent.text = characters
        return ghostty_surface_key(surface, keyEvent)
    } ?? {
        keyEvent.text = nil
        return ghostty_surface_key(surface, keyEvent)
    }()
}

private func modifierAction(for event: NSEvent) -> ghostty_input_action_e {
    let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    switch event.keyCode {
    case 0x39:
        return rawFlags.contains(.capsLock) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    case 0x38, 0x3C:
        return rawFlags.contains(.shift) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    case 0x3B, 0x3E:
        return rawFlags.contains(.control) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    case 0x3A, 0x3D:
        return rawFlags.contains(.option) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    case 0x37, 0x36:
        return rawFlags.contains(.command) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    default:
        return GHOSTTY_ACTION_RELEASE
    }
}

private func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods = GHOSTTY_MODS_NONE.rawValue

    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

    let rawFlags = flags.rawValue
    if rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

    return ghostty_input_mods_e(mods)
}

private func ghosttyMouseButton(for buttonNumber: Int) -> ghostty_input_mouse_button_e {
    switch buttonNumber {
    case 0: return GHOSTTY_MOUSE_LEFT
    case 1: return GHOSTTY_MOUSE_RIGHT
    case 2: return GHOSTTY_MOUSE_MIDDLE
    case 3: return GHOSTTY_MOUSE_EIGHT
    case 4: return GHOSTTY_MOUSE_NINE
    case 5: return GHOSTTY_MOUSE_SIX
    case 6: return GHOSTTY_MOUSE_SEVEN
    case 7: return GHOSTTY_MOUSE_FOUR
    case 8: return GHOSTTY_MOUSE_FIVE
    case 9: return GHOSTTY_MOUSE_TEN
    case 10: return GHOSTTY_MOUSE_ELEVEN
    default: return GHOSTTY_MOUSE_UNKNOWN
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#else

public struct GhosttyTerminalView: View {
    public let session: GhosttyTerminalSession

    public init(session: GhosttyTerminalSession) {
        self.session = session
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
