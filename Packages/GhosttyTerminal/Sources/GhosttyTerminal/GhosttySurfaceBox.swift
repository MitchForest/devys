import Foundation

#if canImport(GhosttyKit) && os(macOS)
import GhosttyKit

final class GhosttySurfaceBox: @unchecked Sendable {
    weak var hostView: GhosttySurfaceHostView?

    private var rawSurface: ghostty_surface_t?
    private var isActive = false

    var opaqueUserdata: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    @MainActor
    func bind(hostView: GhosttySurfaceHostView) {
        self.hostView = hostView
    }

    @MainActor
    func attachSurface(_ surface: ghostty_surface_t) {
        rawSurface = surface
        isActive = true
    }

    @MainActor
    var surface: ghostty_surface_t? {
        guard isActive else { return nil }
        return rawSurface
    }

    @MainActor
    func prepareForShutdown() -> ghostty_surface_t? {
        isActive = false
        hostView = nil

        let surface = rawSurface
        rawSurface = nil
        return surface
    }

    @MainActor
    func handleRuntimeAction(_ action: ghostty_action_s) -> Bool {
        guard isActive, let hostView else { return false }

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            updateTabTitle(action.action.set_title.title, hostView: hostView)
            return true

        case GHOSTTY_ACTION_SET_TAB_TITLE:
            updateTabTitle(action.action.set_tab_title.title, hostView: hostView)
            return true

        case GHOSTTY_ACTION_PWD:
            if let pwd = action.action.pwd.pwd {
                hostView.updateCurrentDirectory(String(cString: pwd))
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            hostView.session.bellCount += 1
            return true

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            hostView.session.isRunning = false
            return true

        case GHOSTTY_ACTION_RENDERER_HEALTH:
            hostView.rendererHealthy = action.action.renderer_health == GHOSTTY_RENDERER_HEALTH_HEALTHY
            return true

        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
            hostView.updateHoveredURL(mouseOverLinkString(action.action.mouse_over_link))
            return true

        case GHOSTTY_ACTION_OPEN_CONFIG:
            return true

        case GHOSTTY_ACTION_READONLY:
            hostView.isReadonly = action.action.readonly == GHOSTTY_READONLY_ON
            return true

        default:
            return false
        }
    }

    @MainActor
    func readClipboard(
        location: ghostty_clipboard_e,
        stateBits: UInt
    ) -> Bool {
        guard isActive,
              let hostView,
              let surface
        else {
            return false
        }

        return hostView.readClipboard(
            surface: surface,
            location: location,
            state: pointerFromBits(stateBits)
        )
    }

    @MainActor
    func confirmReadClipboard(
        text: String?,
        stateBits: UInt,
        request: ghostty_clipboard_request_e
    ) {
        guard isActive,
              let hostView,
              let surface
        else {
            return
        }

        hostView.confirmReadClipboard(
            surface: surface,
            text: text,
            state: pointerFromBits(stateBits),
            request: request
        )
    }

    @MainActor
    func writeClipboard(
        location: ghostty_clipboard_e,
        string: String?,
        confirm: Bool
    ) {
        guard isActive, let hostView else { return }
        hostView.writeClipboard(
            location: location,
            string: string,
            confirm: confirm
        )
    }

    @MainActor
    func handleCloseRequested(processAlive: Bool) {
        guard isActive, let hostView else { return }
        hostView.handleCloseRequested(processAlive: processAlive)
    }

    @MainActor
    private func updateTabTitle(
        _ title: UnsafePointer<CChar>?,
        hostView: GhosttySurfaceHostView
    ) {
        guard let title else { return }

        let normalized = String(cString: title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        hostView.session.tabTitle = normalized
    }
}

private func mouseOverLinkString(
    _ value: ghostty_action_mouse_over_link_s
) -> String? {
    guard let url = value.url, value.len > 0 else { return nil }

    let bytes = [UInt8](
        UnsafeBufferPointer(
            start: UnsafeRawPointer(url).assumingMemoryBound(to: UInt8.self),
            count: value.len
        )
    )
    return String(bytes: bytes, encoding: .utf8)
}

private func pointerFromBits(
    _ bits: UInt
) -> UnsafeMutableRawPointer? {
    UnsafeMutableRawPointer(bitPattern: bits)
}

#endif
