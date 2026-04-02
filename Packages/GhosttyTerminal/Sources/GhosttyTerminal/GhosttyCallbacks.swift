import Foundation

#if canImport(GhosttyKit) && os(macOS)
import GhosttyKit

func makeGhosttyRuntimeConfig(
    for appBridge: GhosttyAppBridge
) -> ghostty_runtime_config_s {
    ghostty_runtime_config_s(
        userdata: appBridge.runtimeUserdata,
        supports_selection_clipboard: false,
        wakeup_cb: ghosttyWakeupCallback,
        action_cb: ghosttyActionCallback,
        read_clipboard_cb: ghosttyReadClipboardCallback,
        confirm_read_clipboard_cb: ghosttyConfirmReadClipboardCallback,
        write_clipboard_cb: ghosttyWriteClipboardCallback,
        close_surface_cb: ghosttyCloseSurfaceCallback
    )
}

private func ghosttyWakeupCallback(_ userdata: UnsafeMutableRawPointer?) {
    appBridgeFromUserdata(userdata)?.scheduleTickFromWakeup()
}

private func ghosttyActionCallback(
    _ app: ghostty_app_t?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    if let surfaceBox = surfaceBox(from: target) {
        return executeMainThreadSync {
            surfaceBox.handleRuntimeAction(action)
        }
    }

    guard let appBridge = appBridgeFromApp(app) else { return false }
    return appBridge.handleGlobalAction(action)
}

private func ghosttyReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) -> Bool {
    guard let surfaceBox = surfaceBoxFromUserdata(userdata) else { return false }
    let stateBits = pointerBits(state)
    return executeMainThreadSync {
        surfaceBox.readClipboard(location: location, stateBits: stateBits)
    }
}

private func ghosttyConfirmReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ text: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
    guard let surfaceBox = surfaceBoxFromUserdata(userdata) else { return }
    let copiedText = text.map { String(cString: $0) }
    let stateBits = pointerBits(state)
    executeMainThreadSync {
        surfaceBox.confirmReadClipboard(
            text: copiedText,
            stateBits: stateBits,
            request: request
        )
    }
}

private func ghosttyWriteClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ length: Int,
    _ confirm: Bool
) {
    guard let surfaceBox = surfaceBoxFromUserdata(userdata) else { return }
    let copiedContent = copiedClipboardContent(content: content, length: length)
    executeMainThreadSync {
        surfaceBox.writeClipboard(
            location: location,
            string: copiedContent,
            confirm: confirm
        )
    }
}

private func ghosttyCloseSurfaceCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ processAlive: Bool
) {
    guard let surfaceBox = surfaceBoxFromUserdata(userdata) else { return }
    executeMainThreadSync {
        surfaceBox.handleCloseRequested(processAlive: processAlive)
    }
}

private func appBridgeFromUserdata(
    _ userdata: UnsafeMutableRawPointer?
) -> GhosttyAppBridge? {
    guard let userdata else { return nil }
    return Unmanaged<GhosttyAppBridge>.fromOpaque(userdata).takeUnretainedValue()
}

private func appBridgeFromApp(
    _ app: ghostty_app_t?
) -> GhosttyAppBridge? {
    guard let app else { return nil }
    return appBridgeFromUserdata(ghostty_app_userdata(app))
}

private func surfaceBoxFromUserdata(
    _ userdata: UnsafeMutableRawPointer?
) -> GhosttySurfaceBox? {
    guard let userdata else { return nil }
    return Unmanaged<GhosttySurfaceBox>.fromOpaque(userdata).takeUnretainedValue()
}

private func surfaceBox(
    from target: ghostty_target_s
) -> GhosttySurfaceBox? {
    guard target.tag == GHOSTTY_TARGET_SURFACE,
          let surface = target.target.surface
    else {
        return nil
    }

    return surfaceBoxFromUserdata(ghostty_surface_userdata(surface))
}

private func executeMainThreadSync<Result: Sendable>(
    _ body: @escaping @MainActor () -> Result
) -> Result {
    if Thread.isMainThread {
        return MainActor.assumeIsolated(body)
    }

    return DispatchQueue.main.sync {
        MainActor.assumeIsolated(body)
    }
}

private func pointerBits(
    _ pointer: UnsafeMutableRawPointer?
) -> UInt {
    UInt(bitPattern: pointer)
}

private func copiedClipboardContent(
    content: UnsafePointer<ghostty_clipboard_content_s>?,
    length: Int
) -> String? {
    guard let content, length > 0 else { return nil }
    return String(cString: content[0].data)
}

#endif
