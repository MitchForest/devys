import Foundation

#if os(macOS)
import AppKit
#endif

#if canImport(GhosttyKit) && os(macOS)
import GhosttyKit

final class GhosttyAppBridge: NSObject, @unchecked Sendable {
    static let shared = GhosttyAppBridge()

    private var app: ghostty_app_t?
    private var didInitialize = false
    private var currentAppearance = GhosttyTerminalAppearance.defaultDark
    private var liveSurfaceBoxes: [ObjectIdentifier: GhosttySurfaceBox] = [:]

    private override init() {
        configureGhosttyResourcesEnvironment()
        super.init()
        installApplicationFocusObservers()
        GhosttyRuntimeIdentity.logger.notice(
            "ghostty_app_bridge_init \(GhosttyRuntimeIdentity.summary, privacy: .public)"
        )
    }

    @MainActor
    func makeSurface(
        for hostView: GhosttySurfaceHostView,
        session: GhosttyTerminalSession,
        surfaceBox: GhosttySurfaceBox
    ) -> ghostty_surface_t? {
        assertMainThread()
        initializeIfNeeded()

        guard let app else { return nil }

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(hostView).toOpaque()
            )
        )
        surfaceConfig.userdata = surfaceBox.opaqueUserdata
        let backingScaleFactor =
            hostView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        surfaceConfig.scale_factor = Double(backingScaleFactor)
        surfaceConfig.wait_after_command = session.requestedCommand != nil
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        let surface = session.workingDirectory.map(\.path).withOptionalCString { workingDirectory in
            surfaceConfig.working_directory = workingDirectory
            return session.requestedCommand.withOptionalCString { command in
                surfaceConfig.command = command
                return ghostty_surface_new(app, &surfaceConfig)
            }
        }

        if surface == nil {
            GhosttyRuntimeIdentity.logger.error(
                "ghostty_surface_create_failed \(GhosttyRuntimeIdentity.summary, privacy: .public)"
            )
        } else if let surface {
            liveSurfaceBoxes[ObjectIdentifier(surfaceBox)] = surfaceBox
            ghostty_surface_set_color_scheme(surface, currentAppearance.colorScheme.ghosttyValue)
        }

        return surface
    }

    @MainActor
    func unregister(_ surfaceBox: GhosttySurfaceBox) {
        assertMainThread()
        liveSurfaceBoxes.removeValue(forKey: ObjectIdentifier(surfaceBox))
    }

    @MainActor
    func destroySurface(_ surface: ghostty_surface_t?) {
        assertMainThread()
        guard let surface else { return }
        ghostty_surface_free(surface)
    }

    @MainActor
    func applyAppearance(_ appearance: GhosttyTerminalAppearance) {
        assertMainThread()
        currentAppearance = appearance

        guard didInitialize, let app, let config = buildConfig(for: appearance) else { return }
        defer { ghostty_config_free(config) }

        ghostty_app_update_config(app, config)
        ghostty_app_set_color_scheme(app, appearance.colorScheme.ghosttyValue)

        for box in liveSurfaceBoxes.values {
            guard let surface = box.surface else { continue }
            ghostty_surface_set_color_scheme(surface, appearance.colorScheme.ghosttyValue)
            ghostty_surface_refresh(surface)
        }
    }

    func scheduleTickFromWakeup() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func handleGlobalAction(_ action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_OPEN_CONFIG:
            return true
        default:
            return false
        }
    }

    var runtimeUserdata: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    @MainActor
    private func initializeIfNeeded() {
        assertMainThread()
        guard !didInitialize else { return }

        didInitialize = true

        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            didInitialize = false
            GhosttyRuntimeIdentity.logger.error(
                "ghostty_init_failed \(GhosttyRuntimeIdentity.summary, privacy: .public)"
            )
            return
        }

        guard let config = buildConfig(for: currentAppearance) else {
            didInitialize = false
            return
        }
        defer { ghostty_config_free(config) }

        var runtimeConfig = makeGhosttyRuntimeConfig(for: self)

        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            didInitialize = false
            GhosttyRuntimeIdentity.logger.error(
                "ghostty_app_new_failed \(GhosttyRuntimeIdentity.summary, privacy: .public)"
            )
            return
        }

        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)
        ghostty_app_set_color_scheme(app, currentAppearance.colorScheme.ghosttyValue)
        GhosttyRuntimeIdentity.logger.notice(
            "ghostty_app_ready \(GhosttyRuntimeIdentity.summary, privacy: .public)"
        )
    }

    private func installApplicationFocusObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @MainActor
    private func setApplicationFocus(_ focused: Bool) {
        assertMainThread()
        guard let app else { return }
        ghostty_app_set_focus(app, focused)
    }

    @objc
    private func applicationDidBecomeActive() {
        MainActor.assumeIsolated {
            setApplicationFocus(true)
        }
    }

    @objc
    private func applicationDidResignActive() {
        MainActor.assumeIsolated {
            setApplicationFocus(false)
        }
    }

    @MainActor
    private func tick() {
        assertMainThread()
        guard let app else { return }
        ghostty_app_tick(app)
    }

    private func buildConfig(for appearance: GhosttyTerminalAppearance) -> ghostty_config_t? {
        let config = ghostty_config_new()
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)

        do {
            let configURL = try writeAppearanceConfig(appearance)
            configURL.path.withCString {
                ghostty_config_load_file(config, $0)
            }
        } catch {
            let errorDescription = error.localizedDescription
            let runtimeSummary = GhosttyRuntimeIdentity.summary
            GhosttyRuntimeIdentity.logger.error(
                "ghostty_theme_write_failed error=\(errorDescription, privacy: .public) \(runtimeSummary, privacy: .public)" // swiftlint:disable:this line_length
            )
        }

        ghostty_config_finalize(config)
        return config
    }
}

private let repoRootURL: URL = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}()

private let ghosttyThemeConfigURL: URL = {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("devys-ghostty-theme", isDirectory: true)
        .appendingPathComponent("terminal-theme.conf")
}()

private func configureGhosttyResourcesEnvironment() {
    let resourcesPath = GhosttyBootstrap.status.resourcesExist
        ? repoRootURL.appendingPathComponent(GhosttyBootstrap.resourcesRelativePath).path
        : nil

    guard let resourcesPath else { return }
    setenv("GHOSTTY_RESOURCES_DIR", resourcesPath, 1)
}

private func writeAppearanceConfig(
    _ appearance: GhosttyTerminalAppearance
) throws -> URL {
    let directoryURL = ghosttyThemeConfigURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: nil
    )
    try appearance.configText.write(
        to: ghosttyThemeConfigURL,
        atomically: true,
        encoding: .utf8
    )
    return ghosttyThemeConfigURL
}

private extension Optional where Wrapped == String {
    func withOptionalCString<Result>(
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        switch self {
        case .some(let value):
            return value.withCString(body)
        case .none:
            return body(nil)
        }
    }
}

private func assertMainThread() {
    dispatchPrecondition(condition: .onQueue(.main))
}

#endif
