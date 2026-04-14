import Foundation

#if canImport(GhosttyKit) && os(macOS)
import AppKit
import CoreText
import GhosttyKit

// Upstream parity reference:
// .deps/ghostty-src/macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift
extension GhosttySurfaceHostView {
    func installLocalEventMonitor() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyUp, .leftMouseDown]
        ) { [weak self] event in
            self?.localEventHandler(event)
        }
    }

    func localEventHandler(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyUp:
            localEventKeyUp(event)
        case .leftMouseDown:
            localEventLeftMouseDown(event)
        default:
            event
        }
    }

    func localEventLeftMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window,
              let eventWindow = event.window,
              window == eventWindow
        else {
            return event
        }

        let location = convert(event.locationInWindow, from: nil)
        guard window.contentView?.hitTest(location) == self else {
            return event
        }

        let outcome = focusTransferState.handleLeftMouseDown(
            isFirstResponder: window.firstResponder === self,
            applicationIsActive: NSApp.isActive,
            windowIsKey: window.isKeyWindow
        )

        switch outcome {
        case .passthrough:
            return event
        case .focusAndConsumeClick:
            window.makeFirstResponder(self)
            return nil
        case .focusAndPassthrough:
            window.makeFirstResponder(self)
            return event
        }
    }

    func localEventKeyUp(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.command) else { return event }
        guard focused else { return event }
        handleKeyUp(event)
        return nil
    }

    func handleKeyDown(_ event: NSEvent) {
        guard let surface else { return }
        let translationEvent = translatedKeyDownEvent(event, surface: surface)
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let markedTextBefore = markedText.length > 0
        let keyboardIDBefore = !markedTextBefore ? GhosttyKeyboardLayout.id : nil

        lastPerformKeyEvent = nil

        interpretKeyEvents([translationEvent])

        if !markedTextBefore, keyboardIDBefore != GhosttyKeyboardLayout.id {
            return
        }

        syncPreedit(clearIfNeeded: markedTextBefore)
        dispatchKeyAction(
            action,
            event: event,
            translationEvent: translationEvent,
            markedTextBefore: markedTextBefore
        )
    }

    func handleKeyUp(_ event: NSEvent) {
        _ = sendKeyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    func handleFlagsChanged(_ event: NSEvent) {
        _ = sendKeyAction(ghosttyModifierAction(for: event), event: event)
    }

    func handlePerformKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard focused else { return false }

        if keyIsBinding(event) {
            handleKeyDown(event)
            return true
        }

        guard let equivalent = performKeyEquivalentText(for: event) else {
            return false
        }

        guard let finalEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: equivalent,
            charactersIgnoringModifiers: equivalent,
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) else {
            return false
        }

        handleKeyDown(finalEvent)
        return true
    }

    func translatedKeyDownEvent(
        _ event: NSEvent,
        surface: ghostty_surface_t
    ) -> NSEvent {
        let translationModsGhostty = ghosttyEventModifierFlags(
            from: ghostty_surface_key_translation_mods(
                surface,
                ghosttyMods(from: event.modifierFlags)
            )
        )
        let translationMods = translatedModifierFlags(
            event.modifierFlags,
            translatedByGhostty: translationModsGhostty
        )

        guard translationMods != event.modifierFlags else {
            return event
        }

        return NSEvent.keyEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: translationMods,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: event.characters(byApplyingModifiers: translationMods) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) ?? event
    }

    func translatedModifierFlags(
        _ original: NSEvent.ModifierFlags,
        translatedByGhostty: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        var translationMods = original
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translatedByGhostty.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }
        return translationMods
    }

    func dispatchKeyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent,
        markedTextBefore: Bool
    ) {
        if let list = keyTextAccumulator, !list.isEmpty {
            for text in list {
                _ = sendKeyAction(
                    action,
                    event: event,
                    translationEvent: translationEvent,
                    text: text
                )
            }
            return
        }

        _ = sendKeyAction(
            action,
            event: event,
            translationEvent: translationEvent,
            text: translationEvent.devysGhosttyCharacters,
            composing: markedText.length > 0 || markedTextBefore
        )
    }

    func performKeyEquivalentText(for event: NSEvent) -> String? {
        switch event.charactersIgnoringModifiers {
        case "\r":
            return event.modifierFlags.contains(.control) ? "\r" : nil
        case "/":
            guard event.modifierFlags.contains(.control),
                  event.modifierFlags.isDisjoint(with: [.shift, .command, .option]) else {
                return nil
            }
            return "_"
        default:
            guard event.timestamp != 0 else { return nil }

            if !event.modifierFlags.contains(.command) &&
                !event.modifierFlags.contains(.control) {
                lastPerformKeyEvent = nil
                return nil
            }

            if let lastPerformKeyEvent {
                self.lastPerformKeyEvent = nil
                if lastPerformKeyEvent == event.timestamp {
                    return event.characters ?? ""
                }
            }

            lastPerformKeyEvent = event.timestamp
            return nil
        }
    }

    func handleDoCommand(by selector: Selector) {
        if let lastPerformKeyEvent,
           let current = NSApp.currentEvent,
           lastPerformKeyEvent == current.timestamp {
            NSApp.sendEvent(current)
            return
        }

        guard let surface else { return }

        switch selector {
        case #selector(moveToBeginningOfDocument(_:)):
            let action = "scroll_to_top"
            action.withCString { pointer in
                _ = ghostty_surface_binding_action(surface, pointer, UInt(action.utf8.count))
            }
        case #selector(moveToEndOfDocument(_:)):
            let action = "scroll_to_bottom"
            action.withCString { pointer in
                _ = ghostty_surface_binding_action(surface, pointer, UInt(action.utf8.count))
            }
        default:
            break
        }
    }

    func handleMouseDown(_ event: NSEvent) {
        claimKeyboardFocusIfPossible()
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    func handleMouseUp(_ event: NSEvent) {
        if focusTransferState.consumeSuppressedLeftMouseUp() {
            return
        }

        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    func handleRightMouseDown(_ event: NSEvent) {
        claimKeyboardFocusIfPossible()
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT)
    }

    func handleRightMouseUp(_ event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)
    }

    func handleOtherMouseDown(_ event: NSEvent) {
        claimKeyboardFocusIfPossible()
        sendMouseButton(
            event,
            state: GHOSTTY_MOUSE_PRESS,
            button: ghosttyMouseButton(for: event.buttonNumber)
        )
    }

    func handleOtherMouseUp(_ event: NSEvent) {
        sendMouseButton(
            event,
            state: GHOSTTY_MOUSE_RELEASE,
            button: ghosttyMouseButton(for: event.buttonNumber)
        )
    }

    @discardableResult
    func sendKeyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }

        var keyEvent = event.devysGhosttyKeyEvent(action, translationMods: translationEvent?.modifierFlags)
        keyEvent.composing = composing

        if let text, !text.isEmpty,
           let codepoint = text.utf8.first, codepoint >= 0x20 {
            return text.withCString { pointer in
                keyEvent.text = pointer
                return ghostty_surface_key(surface, keyEvent)
            }
        }

        return ghostty_surface_key(surface, keyEvent)
    }

    func keyIsBinding(_ event: NSEvent) -> Bool {
        guard let surface else { return false }

        var flags = ghostty_binding_flags_e(0)
        var keyEvent = event.devysGhosttyKeyEvent(GHOSTTY_ACTION_PRESS)

        return (event.characters ?? "").withCString { pointer in
            keyEvent.text = pointer
            return ghostty_surface_key_is_binding(surface, keyEvent, &flags)
        }
    }

    func currentCellSize() -> CGSize {
        guard let surface else { return .zero }
        let size = ghostty_surface_size(surface)
        return CGSize(
            width: CGFloat(size.cell_width_px),
            height: CGFloat(size.cell_height_px)
        )
    }
}

@MainActor
extension GhosttySurfaceHostView: @preconcurrency NSTextInputClient {
    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange() }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        guard let surface else { return NSRange() }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return NSRange() }
        defer { ghostty_surface_free_text(surface, &text) }

        return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let value as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: value)
        case let value as String:
            markedText = NSMutableAttributedString(string: value)
        default:
            return
        }

        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        guard let surface else { return nil }
        guard range.length > 0 else { return nil }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }

        var attributes: [NSAttributedString.Key: Any] = [:]
        if let fontRaw = ghostty_surface_quicklook_font(surface) {
            let font = Unmanaged<CTFont>.fromOpaque(fontRaw)
            attributes[.font] = font.takeUnretainedValue()
            font.release()
        }

        return NSAttributedString(string: String(cString: text.text), attributes: attributes)
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else {
            return NSRect(x: frame.origin.x, y: frame.origin.y, width: 0, height: 0)
        }

        var x: Double = 0
        var y: Double = 0
        let cellSize = currentCellSize()
        var width = Double(cellSize.width)
        var height = Double(cellSize.height)

        if range.length > 0 && range != selectedRange() {
            var text = ghostty_text_s()
            if ghostty_surface_read_selection(surface, &text) {
                x = text.tl_px_x - 2
                y = text.tl_px_y + 2
                ghostty_surface_free_text(surface, &text)
            } else {
                ghostty_surface_ime_point(surface, &x, &y, &width, &height)
            }
        } else {
            ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        }

        if range.length == 0, width > 0 {
            width = 0
            x += Double(cellSize.width) * Double(range.location + range.length)
        }

        let viewRect = NSRect(
            x: x,
            y: frame.size.height - y,
            width: width,
            height: max(height, Double(cellSize.height))
        )

        let windowRect = convert(viewRect, to: nil)
        guard let window else { return windowRect }
        return window.convertToScreen(windowRect)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil else { return }
        guard let surface else { return }

        let chars: String
        switch string {
        case let value as NSAttributedString:
            chars = value.string
        case let value as String:
            chars = value
        default:
            return
        }

        unmarkText()

        if var accumulator = keyTextAccumulator {
            accumulator.append(chars)
            keyTextAccumulator = accumulator
            return
        }

        let length = chars.utf8CString.count
        guard length > 0 else { return }
        chars.withCString { pointer in
            ghostty_surface_text(surface, pointer, UInt(length - 1))
        }
    }

    func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }

        if markedText.length > 0 {
            let string = markedText.string
            let length = string.utf8CString.count
            guard length > 0 else { return }
            string.withCString { pointer in
                ghostty_surface_preedit(surface, pointer, UInt(length - 1))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }
}
#endif
