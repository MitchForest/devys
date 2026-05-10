import AppKit
import Browser
import ComposableArchitecture
import Diff
import Editor
import Git
import Observation
import SwiftUI
import TerminalProduct
import UI
import UniformTypeIdentifiers

@MainActor
struct AppWindowCommandSink {
    var openFileInCurrentWindowGroup: (URL, URL?) -> Void = { _, _ in }
    var openFileInNewWindow: (URL, URL?) -> Void = { _, _ in }
    var openSourceFileInCurrentWindowGroup: (URL, URL?) -> Void = { _, _ in }
    var openSourceFileInNewWindow: (URL, URL?) -> Void = { _, _ in }
    var openDiffInCurrentWindowGroup: (GitFileChange, URL?) -> Void = { _, _ in }
    var openDiffInNewWindow: (GitFileChange, URL?) -> Void = { _, _ in }
    var bindDroppedProjectRoot: (URL) -> Void = { _ in }
    var terminalWorkingDirectoryDidChange: (UUID, URL) -> Void = { _, _ in }
    var revealInFinder: (URL) -> Void = { _ in }
    var copyPath: (String) -> Void = { _ in }
}

@MainActor
final class DevysAppDelegate: NSObject, NSApplicationDelegate {
    private let windowHost = DevysWindowHost()
    private var cwdResolutionTasks: [UUID: Task<Void, Never>] = [:]
    private let alertClient = AlertClient.liveValue
    private let recentProjects = RecentProjectsStore()
    private let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }
    private weak var pendingTerminationApplication: NSApplication?
    private var isConfirmingApplicationTermination = false

    override init() {
        super.init()
        windowHost.commandSink = AppWindowCommandSink(
            openFileInCurrentWindowGroup: { [weak self] fileURL, projectRootURL in
                self?.openFileInCurrentWindowGroup(fileURL, projectRootURL: projectRootURL)
            },
            openFileInNewWindow: { [weak self] fileURL, projectRootURL in
                self?.openFileInNewWindow(fileURL, projectRootURL: projectRootURL)
            },
            openSourceFileInCurrentWindowGroup: { [weak self] fileURL, projectRootURL in
                self?.openSourceFileInCurrentWindowGroup(fileURL, projectRootURL: projectRootURL)
            },
            openSourceFileInNewWindow: { [weak self] fileURL, projectRootURL in
                self?.openSourceFileInNewWindow(fileURL, projectRootURL: projectRootURL)
            },
            openDiffInCurrentWindowGroup: { [weak self] change, projectRootURL in
                self?.openDiffInCurrentWindowGroup(change, projectRootURL: projectRootURL)
            },
            openDiffInNewWindow: { [weak self] change, projectRootURL in
                self?.openDiffInNewWindow(change, projectRootURL: projectRootURL)
            },
            bindDroppedProjectRoot: { [weak self] url in
                self?.bindDroppedProjectRoot(url)
            },
            terminalWorkingDirectoryDidChange: { [weak self] windowID, workingDirectory in
                self?.terminalWorkingDirectoryDidChange(windowID: windowID, workingDirectory: workingDirectory)
            },
            revealInFinder: { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            copyPath: { path in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        )
        windowHost.onManagedWindowClosed = { [weak self] in
            self?.store.send(.nativeWindowClosed)
        }
        windowHost.onManagedWindowSelected = { [weak self] windowGroupID in
            self?.store.send(.nativeWindowSelected(windowGroupID))
        }
        windowHost.onManagedWindowStateChanged = { [weak self] in
            self?.completePendingTerminationIfPossible()
        }
        windowHost.closeDecision = { [weak self] subject in
            self?.closeDecision(for: subject) ?? .deny
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        store.send(.applicationDidFinishLaunching)
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.mainMenu = DevysMenuBuilder(delegate: self).makeMainMenu()
        openNewWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        _ = sender
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isConfirmingApplicationTermination else { return .terminateNow }

        pendingTerminationApplication = sender
        requestManagedWindowsCloseForTermination()
        completePendingTerminationIfPossible()
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        windowHost.removeAll()
        cwdResolutionTasks.values.forEach { $0.cancel() }
        cwdResolutionTasks.removeAll()
    }

    @objc func openNewWindow() {
        let windowGroupID = UUID()
        store.send(.openNewWindow(id: windowGroupID))
        let controller = windowHost.makeTerminalWindowController(
            tabbingMode: .disallowed,
            windowGroupID: windowGroupID,
            projectRootURL: nil
        )
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            controller.window?.tabbingMode = .preferred
        }
    }

    @objc func openNewTab() {
        guard let currentWindow = NSApp.keyWindow ?? windowHost.fallbackWindow else {
            openNewWindow()
            return
        }

        let inheritedProjectRoot = projectRootForOpening(in: currentWindow, explicitProjectRootURL: nil)
        let windowGroupID = windowGroupIDForOpening(in: currentWindow) ?? UUID()
        store.send(.openNewTab(.terminal, projectRootURL: inheritedProjectRoot, windowGroupID: windowGroupID))
        let controller = windowHost.makeTerminalWindowController(
            tabbingMode: .preferred,
            windowGroupID: windowGroupID,
            projectRootURL: inheritedProjectRoot
        )
        guard let newWindow = controller.window else { return }
        currentWindow.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }

    private func projectRootForOpening(in currentWindow: NSWindow, explicitProjectRootURL: URL?) -> URL? {
        explicitProjectRootURL?.standardizedFileURL
            ?? windowHost.projectRoot(for: currentWindow.windowController)
            ?? store.state.selectedProjectRootURL
    }

    private func windowGroupIDForOpening(in currentWindow: NSWindow) -> UUID? {
        windowHost.windowGroupID(for: currentWindow.windowController)
            ?? store.state.selectedWindowGroupID
    }

    @objc func openProject() {
        guard let url = chooseProjectRoot() else { return }
        bindProjectRootToKeyWindowGroup(url)
    }

    @objc func openProjectInNewWindow() {
        guard let url = chooseProjectRoot() else { return }
        openProjectWindowGroup(rootURL: url)
    }

    @objc func openRecentProject(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        openProjectWindowGroup(rootURL: URL(fileURLWithPath: path))
    }

    @objc func openBrowserLocation() {
        let alert = NSAlert()
        alert.messageText = "Open Browser Tab"
        alert.informativeText = "Enter a URL, localhost port, or local file path."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: "http://localhost:3000")
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn,
              let url = BrowserTabRouting.normalizedUserURL(field.stringValue) else {
            return
        }

        openBrowserURLInCurrentWindowGroup(url, projectRootURL: windowHost.projectRoot(for: NSApp.keyWindow?.windowController))
    }

    @objc func openDefaultLocalhostBrowser() {
        guard let url = BrowserTabRouting.localhostURL(port: 3000) else { return }
        openBrowserURLInCurrentWindowGroup(url, projectRootURL: windowHost.projectRoot(for: NSApp.keyWindow?.windowController))
    }

    func openFileInCurrentWindowGroup(_ fileURL: URL, projectRootURL: URL?) {
        guard let currentWindow = NSApp.keyWindow ?? windowHost.fallbackWindow else {
            openFileInNewWindow(fileURL, projectRootURL: projectRootURL)
            return
        }

        let inheritedProjectRoot = projectRootForOpening(in: currentWindow, explicitProjectRootURL: projectRootURL)
        let windowGroupID = windowGroupIDForOpening(in: currentWindow) ?? UUID()

        let newWindow: NSWindow?
        let tabKind: WindowTabKind
        if BrowserTabRouting.isBrowserPreviewFile(fileURL) {
            tabKind = .browser(fileURL.standardizedFileURL)
            let readAccessURL = BrowserTabRouting.readAccessURL(
                for: fileURL,
                projectRootURL: inheritedProjectRoot
            )
            newWindow = windowHost.makeBrowserWindowController(
                tabbingMode: .preferred,
                windowGroupID: windowGroupID,
                projectRootURL: inheritedProjectRoot,
                url: fileURL.standardizedFileURL,
                fileReadAccessURL: readAccessURL
            ).window
        } else if MarkdownReaderRouting.isReadable(fileURL) {
            tabKind = .reader(fileURL.standardizedFileURL)
            newWindow = windowHost.makeReaderWindowController(
                tabbingMode: .preferred,
                windowGroupID: windowGroupID,
                projectRootURL: inheritedProjectRoot,
                fileURL: fileURL
            ).window
        } else {
            tabKind = .file(fileURL.standardizedFileURL)
            newWindow = windowHost.makeFileWindowController(
                tabbingMode: .preferred,
                windowGroupID: windowGroupID,
                projectRootURL: inheritedProjectRoot,
                fileURL: fileURL
            ).window
        }
        guard let newWindow else { return }
        store.send(.openNewTab(tabKind, projectRootURL: inheritedProjectRoot, windowGroupID: windowGroupID))
        currentWindow.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }

    func openFileInNewWindow(_ fileURL: URL, projectRootURL: URL?) {
        let windowGroupID = UUID()
        let controller: NSWindowController
        let tabKind: WindowTabKind
        if BrowserTabRouting.isBrowserPreviewFile(fileURL) {
            tabKind = .browser(fileURL.standardizedFileURL)
            let standardizedProjectRootURL = projectRootURL?.standardizedFileURL
            let readAccessURL = BrowserTabRouting.readAccessURL(
                for: fileURL,
                projectRootURL: standardizedProjectRootURL
            )
            controller = windowHost.makeBrowserWindowController(
                tabbingMode: .disallowed,
                windowGroupID: windowGroupID,
                projectRootURL: standardizedProjectRootURL,
                url: fileURL.standardizedFileURL,
                fileReadAccessURL: readAccessURL
            )
        } else if MarkdownReaderRouting.isReadable(fileURL) {
            tabKind = .reader(fileURL.standardizedFileURL)
            controller = windowHost.makeReaderWindowController(
                tabbingMode: .disallowed,
                windowGroupID: windowGroupID,
                projectRootURL: projectRootURL?.standardizedFileURL,
                fileURL: fileURL
            )
        } else {
            tabKind = .file(fileURL.standardizedFileURL)
            controller = windowHost.makeFileWindowController(
                tabbingMode: .disallowed,
                windowGroupID: windowGroupID,
                projectRootURL: projectRootURL?.standardizedFileURL,
                fileURL: fileURL
            )
        }
        store.send(.openNewWindow(id: windowGroupID, tabKind: tabKind, projectRootURL: projectRootURL))
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            controller.window?.tabbingMode = .preferred
        }
    }

    func openSourceFileInCurrentWindowGroup(_ fileURL: URL, projectRootURL: URL?) {
        guard let currentWindow = NSApp.keyWindow ?? windowHost.fallbackWindow else {
            openSourceFileInNewWindow(fileURL, projectRootURL: projectRootURL)
            return
        }

        let inheritedProjectRoot = projectRootForOpening(in: currentWindow, explicitProjectRootURL: projectRootURL)
        let windowGroupID = windowGroupIDForOpening(in: currentWindow) ?? UUID()
        store.send(.openNewTab(.file(fileURL.standardizedFileURL), projectRootURL: inheritedProjectRoot, windowGroupID: windowGroupID))
        let controller = windowHost.makeFileWindowController(
            tabbingMode: .preferred,
            windowGroupID: windowGroupID,
            projectRootURL: inheritedProjectRoot,
            fileURL: fileURL
        )
        guard let newWindow = controller.window else { return }
        currentWindow.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }

    func openSourceFileInNewWindow(_ fileURL: URL, projectRootURL: URL?) {
        let windowGroupID = UUID()
        store.send(.openNewWindow(id: windowGroupID, tabKind: .file(fileURL.standardizedFileURL), projectRootURL: projectRootURL))
        let controller = windowHost.makeFileWindowController(
            tabbingMode: .disallowed,
            windowGroupID: windowGroupID,
            projectRootURL: projectRootURL?.standardizedFileURL,
            fileURL: fileURL
        )
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            controller.window?.tabbingMode = .preferred
        }
    }

    func openBrowserURLInCurrentWindowGroup(_ url: URL, projectRootURL: URL?) {
        guard let currentWindow = NSApp.keyWindow ?? windowHost.fallbackWindow else {
            openBrowserURLInNewWindow(url, projectRootURL: projectRootURL)
            return
        }

        let inheritedProjectRoot = projectRootForOpening(in: currentWindow, explicitProjectRootURL: projectRootURL)
        let windowGroupID = windowGroupIDForOpening(in: currentWindow) ?? UUID()
        let fileReadAccessURL = url.isFileURL
            ? BrowserTabRouting.readAccessURL(for: url, projectRootURL: inheritedProjectRoot)
            : nil
        store.send(.openNewTab(.browser(url), projectRootURL: inheritedProjectRoot, windowGroupID: windowGroupID))
        let controller = windowHost.makeBrowserWindowController(
            tabbingMode: .preferred,
            windowGroupID: windowGroupID,
            projectRootURL: inheritedProjectRoot,
            url: url,
            fileReadAccessURL: fileReadAccessURL
        )
        guard let newWindow = controller.window else { return }
        currentWindow.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }

    func openBrowserURLInNewWindow(_ url: URL, projectRootURL: URL?) {
        let standardizedProjectRootURL = projectRootURL?.standardizedFileURL
        let fileReadAccessURL = url.isFileURL
            ? BrowserTabRouting.readAccessURL(for: url, projectRootURL: standardizedProjectRootURL)
            : nil
        let windowGroupID = UUID()
        store.send(.openNewWindow(id: windowGroupID, tabKind: .browser(url), projectRootURL: standardizedProjectRootURL))
        let controller = windowHost.makeBrowserWindowController(
            tabbingMode: .disallowed,
            windowGroupID: windowGroupID,
            projectRootURL: standardizedProjectRootURL,
            url: url,
            fileReadAccessURL: fileReadAccessURL
        )
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            controller.window?.tabbingMode = .preferred
        }
    }

    fileprivate func openDiffInCurrentWindowGroup(_ change: GitFileChange, projectRootURL: URL?) {
        guard let currentWindow = NSApp.keyWindow ?? windowHost.fallbackWindow else {
            openDiffInNewWindow(change, projectRootURL: projectRootURL)
            return
        }

        let inheritedProjectRoot = projectRootForOpening(in: currentWindow, explicitProjectRootURL: projectRootURL)
        let windowGroupID = windowGroupIDForOpening(in: currentWindow) ?? UUID()
        store.send(.openNewTab(.diff(change.path), projectRootURL: inheritedProjectRoot, windowGroupID: windowGroupID))
        let controller = windowHost.makeDiffWindowController(
            tabbingMode: .preferred,
            windowGroupID: windowGroupID,
            projectRootURL: inheritedProjectRoot,
            change: change
        )
        guard let newWindow = controller.window else { return }
        currentWindow.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }

    fileprivate func openDiffInNewWindow(_ change: GitFileChange, projectRootURL: URL?) {
        let windowGroupID = UUID()
        store.send(.openNewWindow(id: windowGroupID, tabKind: .diff(change.path), projectRootURL: projectRootURL))
        let controller = windowHost.makeDiffWindowController(
            tabbingMode: .disallowed,
            windowGroupID: windowGroupID,
            projectRootURL: projectRootURL?.standardizedFileURL,
            change: change
        )
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            controller.window?.tabbingMode = .preferred
        }
    }

    fileprivate func bindDroppedProjectRoot(_ url: URL) {
        bindProjectRootToKeyWindowGroup(url)
    }

    fileprivate func openProjectWindowGroupFromCandidate(rootURL: URL) {
        openProjectWindowGroup(rootURL: rootURL)
    }

    fileprivate func dismissProjectRootCandidate(_ url: URL, for windowID: UUID) {
        windowHost.terminalWindowController(id: windowID)?
            .dismissProjectRootCandidate(url)
    }

    fileprivate func bindProjectRootCandidate(_ url: URL, for windowID: UUID) {
        guard let controller = windowHost.terminalWindowController(id: windowID) else {
            openProjectWindowGroup(rootURL: url)
            return
        }
        bindProjectRoot(url.standardizedFileURL, toWindowGroupFor: controller)
    }

    fileprivate func terminalWorkingDirectoryDidChange(
        windowID: UUID,
        workingDirectory: URL
    ) {
        guard let controller = windowHost.terminalWindowController(id: windowID) else {
            return
        }
        controller.currentWorkingDirectoryURL = workingDirectory.standardizedFileURL
        cwdResolutionTasks[windowID]?.cancel()
        cwdResolutionTasks[windowID] = Task { [weak self, weak controller] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  let self,
                  let controller else {
                return
            }

            let candidate = await DevysProjectRootResolver.resolveCandidateProjectRoot(
                from: workingDirectory.standardizedFileURL
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.applyProjectRootCandidate(candidate, from: controller)
            }
        }
    }

    @objc func bindProjectToTerminalDirectory() {
        guard let controller = windowHost.keyTerminalWindowController,
              let cwd = controller.currentWorkingDirectoryURL else {
            return
        }
        cwdResolutionTasks[controller.id]?.cancel()
        Task { [weak self, weak controller] in
            guard let root = await DevysProjectRootResolver.resolveCandidateProjectRoot(from: cwd),
                  let self,
                  let controller else {
                return
            }
            await MainActor.run {
                self.bindProjectRoot(root, toWindowGroupFor: controller)
            }
        }
    }

    @objc func switchProjectToTerminalDirectory() {
        bindProjectToTerminalDirectory()
    }

    @objc func openTerminalDirectoryInNewWindow() {
        guard let controller = windowHost.keyTerminalWindowController,
              let cwd = controller.currentWorkingDirectoryURL else {
            return
        }
        Task { [weak self] in
            guard let root = await DevysProjectRootResolver.resolveCandidateProjectRoot(from: cwd),
                  let self else {
                return
            }
            await MainActor.run {
                self.openProjectWindowGroup(rootURL: root)
            }
        }
    }

    @objc func clearProjectBinding() {
        guard let controller = windowHost.keyTerminalWindowController else { return }
        bindProjectRoot(nil, toWindowGroupFor: controller)
    }

    @objc func focusComposer() {
        windowHost.keyTerminalWindowController?.focusComposer()
    }

    @objc func pasteIntoComposer() {
        windowHost.keyTerminalWindowController?.pasteIntoComposer()
    }

    @objc func captureSelectionIntoComposer() {
        windowHost.keyTerminalWindowController?.captureSelectionIntoComposer()
    }

    @objc func showKeyboardShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Devys Terminal Keyboard Shortcuts"
        alert.informativeText = """
        Command-N: New Window
        Command-T: New Tab
        Command-W: Close Tab or Window
        Command-L: Focus Composer
        Command-Shift-]: Next Tab
        Command-Shift-[: Previous Tab
        Command-Shift-T: Move Tab to New Window
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func chooseProjectRoot() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project folder"
        panel.prompt = "Open"

        guard panel.runModal() == .OK else { return nil }
        return panel.url?.standardizedFileURL
    }

    private func bindProjectRootToKeyWindowGroup(_ url: URL) {
        guard let keyWindow = NSApp.keyWindow,
              let controller = windowHost.terminalController(for: keyWindow) else {
            openProjectWindowGroup(rootURL: url.standardizedFileURL)
            return
        }

        bindProjectRoot(url.standardizedFileURL, toWindowGroupFor: controller)
    }

    private func bindProjectRoot(
        _ url: URL?,
        toWindowGroupFor controller: TerminalWindowController
    ) {
        let standardizedURL = url?.standardizedFileURL
        if let standardizedURL {
            recentProjects.record(standardizedURL)
        }
        refreshMainMenu()
        store.send(.bindProjectRoot(standardizedURL, windowGroupID: controller.windowGroupID))

        guard let keyWindow = controller.window,
              let windows = keyWindow.tabGroup?.windows,
              !windows.isEmpty else {
            if let standardizedURL {
                openProjectWindowGroup(rootURL: standardizedURL)
            }
            return
        }

        for window in windows {
            (window.windowController as? TerminalWindowController)?
                .setProjectRootURL(standardizedURL)
            (window.windowController as? FileWindowController)?
                .setProjectRootURL(standardizedURL)
            (window.windowController as? ReaderWindowController)?
                .setProjectRootURL(standardizedURL)
            (window.windowController as? DiffWindowController)?
                .setProjectRootURL(standardizedURL)
            (window.windowController as? BrowserWindowController)?
                .setProjectRootURL(standardizedURL)
        }
    }

    private func applyProjectRootCandidate(
        _ candidate: URL?,
        from controller: TerminalWindowController
    ) {
        guard let candidate = candidate?.standardizedFileURL else {
            controller.setPendingProjectRootCandidate(nil)
            return
        }

        if controller.projectRootURL == nil {
            bindProjectRoot(candidate, toWindowGroupFor: controller)
            return
        }

        guard controller.projectRootURL != candidate else {
            controller.setPendingProjectRootCandidate(nil)
            return
        }

        guard !controller.isCandidateDismissed(candidate) else { return }
        controller.setPendingProjectRootCandidate(candidate)
    }

    private func openProjectWindowGroup(rootURL: URL) {
        let standardizedURL = rootURL.standardizedFileURL
        recentProjects.record(standardizedURL)
        refreshMainMenu()
        let windowGroupID = UUID()
        store.send(.openNewWindow(id: windowGroupID, projectRootURL: standardizedURL))
        let controller = windowHost.makeTerminalWindowController(
            tabbingMode: .disallowed,
            windowGroupID: windowGroupID,
            projectRootURL: standardizedURL
        )
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            controller.window?.tabbingMode = .preferred
        }
    }

    private func requestManagedWindowsCloseForTermination() {
        let windows = windowHost.managedWindowsForTermination()
        for window in windows where window.isVisible {
            window.performClose(nil)
        }
    }

    private func closeDecision(for subject: CloseSubject) -> CloseDecision {
        store.send(.closePolicy(.register(subject)))

        switch subject.kind {
        case .plain:
            store.send(.closePolicy(.requestClose(subject.id)))

        case .dirtyDocument, .terminalCloseRisk:
            guard let request = subject.alertRequest else {
                store.send(.closePolicy(.closeAlertResponse(subject.id, .cancel)))
                break
            }
            let response: AlertResponse
            switch subject.kind {
            case .dirtyDocument:
                response = alertClient.chooseNow(request)
            case .terminalCloseRisk:
                response = alertClient.confirmNow(request) ? .confirm : .cancel
            case .plain:
                response = .confirm
            }
            store.send(.closePolicy(.closeAlertResponse(subject.id, response)))
        }

        return store.state.closePolicy.decisions[subject.id] ?? .deny
    }

    private func completePendingTerminationIfPossible() {
        guard let application = pendingTerminationApplication else { return }

        let visibleWindows = windowHost.managedWindowsForTermination().filter(\.isVisible)
        guard !visibleWindows.isEmpty else {
            pendingTerminationApplication = nil
            isConfirmingApplicationTermination = true
            application.reply(toApplicationShouldTerminate: true)
            return
        }

        guard !windowHost.hasAsyncCloseInProgress else {
            return
        }

        pendingTerminationApplication = nil
        application.reply(toApplicationShouldTerminate: false)
    }

    private func refreshMainMenu() {
        NSApp.mainMenu = DevysMenuBuilder(delegate: self).makeMainMenu()
    }

}

@main
enum DevysAppMain {
    @MainActor private static var appDelegate: DevysAppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = DevysAppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
func configureDevysGlassWindow(_ window: NSWindow, toolbarIdentifier: String) {
    window.isOpaque = false
    window.backgroundColor = .clear
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unifiedCompact
    window.titlebarSeparatorStyle = .none
    window.collectionBehavior.insert(.fullScreenPrimary)

    let toolbar = NSToolbar(identifier: NSToolbar.Identifier(toolbarIdentifier))
    toolbar.displayMode = .iconOnly
    toolbar.showsBaselineSeparator = false
    window.toolbar = toolbar
}

@MainActor
func configureHostingViewForGlass(_ view: NSView) {
    view.wantsLayer = true
    view.layer?.isOpaque = false
    view.layer?.backgroundColor = NSColor.clear.cgColor
}

@MainActor
private final class TerminalCloseRiskSink {
    weak var controller: TerminalWindowController?

    func update(_ closeRisk: TerminalProductCloseRisk?) {
        controller?.setCloseRisk(closeRisk)
    }
}

@MainActor
private final class DevysDirtyDocumentCloseCoordinator {
    let id: UUID
    let fileURL: URL
    let session: EditorPreviewSession
    weak var window: NSWindow?
    var closeDecision: (CloseSubject) -> CloseDecision = { _ in .deny }
    var onCloseProgressChange: (() -> Void)?
    private var isCloseConfirmed = false
    private var isSavingForClose = false

    var isCompletingClose: Bool {
        isSavingForClose
    }

    init(id: UUID, fileURL: URL, session: EditorPreviewSession) {
        self.id = id
        self.fileURL = fileURL
        self.session = session
    }

    func updateDirtyState(_ isDirty: Bool) {
        window?.isDocumentEdited = isDirty
    }

    func windowShouldClose() -> Bool {
        guard !isCloseConfirmed else {
            return true
        }
        guard session.document?.isDirty == true else {
            return closeDecision(CloseSubject(id: id, kind: .plain)) == .allow
        }
        guard !isSavingForClose else { return false }

        switch closeDecision(CloseSubject(id: id, kind: .dirtyDocument(displayName: displayName))) {
        case .allow:
            isCloseConfirmed = true
            return true
        case .saveThenClose:
            saveThenClose()
            return false
        case .discardThenClose:
            isCloseConfirmed = true
            return true
        case .deny:
            return false
        }
    }

    private func saveThenClose() {
        guard let document = session.document else {
            isCloseConfirmed = true
            window?.performClose(nil)
            return
        }

        isSavingForClose = true
        onCloseProgressChange?()
        let saveURL = document.fileURL?.standardizedFileURL ?? fileURL
        let content = document.content
        Task { @MainActor in
            do {
                try await DocumentClient.liveValue.save(content, saveURL)
                document.fileURL = saveURL
                document.isDirty = false
                updateDirtyState(false)
                isSavingForClose = false
                isCloseConfirmed = true
                onCloseProgressChange?()
                window?.performClose(nil)
            } catch {
                isSavingForClose = false
                onCloseProgressChange?()
                showSaveFailedAlert(error)
            }
        }
    }

    private func showSaveFailedAlert(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Could not save \(displayName)"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private var displayName: String {
        let name = fileURL.lastPathComponent
        return name.isEmpty ? fileURL.path : name
    }
}

@MainActor
final class TerminalWindowController: NSWindowController, NSWindowDelegate {
    let id = UUID()
    let windowGroupID: UUID
    let commandSink = TerminalProductCommandSink()
    var onClose: (() -> Void)?
    var onSelect: (() -> Void)?
    var closeDecision: (CloseSubject) -> CloseDecision = { _ in .deny }
    private(set) var projectRootURL: URL?
    fileprivate var currentWorkingDirectoryURL: URL?
    private var store: StoreOf<TerminalTabFeature>
    private let drawerStore: StoreOf<ProjectDrawerFeature>
    private let appCommandSink: AppWindowCommandSink
    private let hostingController: NSHostingController<TerminalTabRootView>
    private let closeRiskSink = TerminalCloseRiskSink()
    private var closeRisk: TerminalProductCloseRisk?
    private var isCloseConfirmed = false

    init(
        tabbingMode: NSWindow.TabbingMode,
        windowGroupID: UUID,
        projectRootURL: URL?,
        appCommandSink: AppWindowCommandSink
    ) {
        self.windowGroupID = windowGroupID
        self.projectRootURL = projectRootURL?.standardizedFileURL
        self.appCommandSink = appCommandSink
        currentWorkingDirectoryURL = self.projectRootURL
        let store = Store(initialState: TerminalTabFeature.State(projectRootURL: self.projectRootURL)) {
            TerminalTabFeature()
        }
        self.store = store
        let drawerStore = Store(initialState: ProjectDrawerFeature.State(projectRootURL: self.projectRootURL)) {
            ProjectDrawerFeature()
        }
        self.drawerStore = drawerStore
        let rootView = Self.makeRootView(
            id: id,
            commandSink: commandSink,
            projectRootURL: self.projectRootURL,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink,
            closeRiskSink: closeRiskSink
        )
        let hostingController = NSHostingController(rootView: rootView)
        configureHostingViewForGlass(hostingController.view)
        self.hostingController = hostingController
        let window = NSWindow(contentViewController: hostingController)
        window.title = Self.windowTitle(projectRootURL: self.projectRootURL)
        window.setContentSize(NSSize(width: 960, height: 640))
        window.minSize = NSSize(width: 720, height: 420)
        window.tabbingMode = tabbingMode
        window.tabbingIdentifier = Self.tabbingIdentifier(projectRootURL: self.projectRootURL)
        configureDevysGlassWindow(window, toolbarIdentifier: "devys-terminal.toolbar")

        super.init(window: window)
        closeRiskSink.controller = self
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        _ = notification
        onSelect?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        _ = sender
        guard !isCloseConfirmed else {
            return true
        }
        guard let closeRisk else {
            return closeDecision(CloseSubject(id: id, kind: .plain)) == .allow
        }

        let decision = closeDecision(
            CloseSubject(
                id: id,
                kind: .terminalCloseRisk(
                    displayName: closeRisk.displayName,
                    detail: closeRiskInformativeText(for: closeRisk)
                )
            )
        )
        if decision == .allow {
            isCloseConfirmed = true
            return true
        }

        return false
    }

    func setCloseRisk(_ closeRisk: TerminalProductCloseRisk?) {
        self.closeRisk = closeRisk
        store.send(
            .closeRiskChanged(
                closeRisk.map {
                    TerminalTabCloseRisk(
                        displayName: $0.displayName,
                        detail: closeRiskInformativeText(for: $0)
                    )
                }
            )
        )
    }

    func setProjectRootURL(_ url: URL?) {
        let standardizedURL = url?.standardizedFileURL
        guard projectRootURL != standardizedURL else { return }
        projectRootURL = standardizedURL
        store.send(.projectRootChanged(standardizedURL))
        window?.tabbingIdentifier = Self.tabbingIdentifier(projectRootURL: standardizedURL)
        window?.title = Self.windowTitle(projectRootURL: standardizedURL)
        hostingController.rootView = Self.makeRootView(
            id: id,
            commandSink: commandSink,
            projectRootURL: standardizedURL,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink,
            closeRiskSink: closeRiskSink
        )
    }

    func setPendingProjectRootCandidate(_ url: URL?) {
        store.send(.pendingProjectRootCandidateChanged(url?.standardizedFileURL))
    }

    func dismissProjectRootCandidate(_ url: URL) {
        store.send(.dismissProjectRootCandidate(url))
    }

    func isCandidateDismissed(_ url: URL) -> Bool {
        store.state.dismissedProjectRootCandidatePaths.contains(url.standardizedFileURL.path)
    }

    func focusComposer() {
        store.send(.focusComposerRequested)
        commandSink.focusComposer()
        store.send(.composerIntentHandled)
    }

    func pasteIntoComposer() {
        store.send(.pasteIntoComposerRequested)
        commandSink.pasteIntoComposer()
        store.send(.composerIntentHandled)
    }

    func captureSelectionIntoComposer() {
        store.send(.captureSelectionIntoComposerRequested)
        commandSink.captureSelectionIntoComposer()
        store.send(.composerIntentHandled)
    }

    private static func makeRootView(
        id: UUID,
        commandSink: TerminalProductCommandSink,
        projectRootURL: URL?,
        store: StoreOf<TerminalTabFeature>,
        drawerStore: StoreOf<ProjectDrawerFeature>,
        appCommandSink: AppWindowCommandSink,
        closeRiskSink: TerminalCloseRiskSink
    ) -> TerminalTabRootView {
        TerminalTabRootView(
            windowID: id,
            commandSink: commandSink,
            projectRootURL: projectRootURL,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink,
            onCloseRiskChange: { closeRisk in
                closeRiskSink.update(closeRisk)
            }
        )
    }

    private func closeRiskInformativeText(for closeRisk: TerminalProductCloseRisk) -> String {
        switch closeRisk {
        case .knownAgent(let displayName, let process):
            return "\(displayName) is active in this terminal as process \(process.pid). Closing the tab will terminate that session."
        case .foregroundProcess(let process):
            return "\(process.executableName) is active in this terminal as process \(process.pid). Closing the tab will terminate it."
        }
    }

    fileprivate static func tabbingIdentifier(projectRootURL: URL?) -> String {
        guard let projectRootURL else { return "devys-terminal" }
        return "devys-terminal.project.\(projectRootURL.path)"
    }

    private static func windowTitle(projectRootURL: URL?) -> String {
        guard let projectRootURL else { return "Devys Terminal" }
        let name = projectRootURL.lastPathComponent
        return name.isEmpty ? "Devys Terminal" : name
    }
}

@MainActor
final class FileWindowController: NSWindowController, NSWindowDelegate {
    let id = UUID()
    let windowGroupID: UUID
    var onClose: (() -> Void)?
    var onSelect: (() -> Void)?
    var closeDecision: (CloseSubject) -> CloseDecision {
        get { closeCoordinator.closeDecision }
        set { closeCoordinator.closeDecision = newValue }
    }
    var onCloseProgressChange: (() -> Void)? {
        get { closeCoordinator.onCloseProgressChange }
        set { closeCoordinator.onCloseProgressChange = newValue }
    }
    var isCompletingClose: Bool {
        closeCoordinator.isCompletingClose
    }
    private(set) var projectRootURL: URL?
    private let fileURL: URL
    private let session: EditorPreviewSession
    private var store: StoreOf<FileTabFeature>
    private let drawerStore: StoreOf<ProjectDrawerFeature>
    private let appCommandSink: AppWindowCommandSink
    private let closeCoordinator: DevysDirtyDocumentCloseCoordinator
    private let hostingController: NSHostingController<FileTabRootView>

    init(
        tabbingMode: NSWindow.TabbingMode,
        windowGroupID: UUID,
        projectRootURL: URL?,
        fileURL: URL,
        editorSessionCache: EditorSessionCache,
        appCommandSink: AppWindowCommandSink
    ) {
        self.windowGroupID = windowGroupID
        self.projectRootURL = projectRootURL?.standardizedFileURL
        self.fileURL = fileURL.standardizedFileURL
        self.appCommandSink = appCommandSink
        let session = editorSessionCache.session(
            id: id,
            url: self.fileURL,
            previewRequest: DocumentPreviewRequest(maxBytes: 1_500_000)
        )
        self.session = session
        let store = Store(initialState: FileTabFeature.State(fileURL: self.fileURL, projectRootURL: self.projectRootURL)) {
            FileTabFeature()
        }
        self.store = store
        let drawerStore = Store(initialState: ProjectDrawerFeature.State(projectRootURL: self.projectRootURL)) {
            ProjectDrawerFeature()
        }
        self.drawerStore = drawerStore
        let closeCoordinator = DevysDirtyDocumentCloseCoordinator(id: id, fileURL: self.fileURL, session: session)
        self.closeCoordinator = closeCoordinator
        let rootView = FileTabRootView(
            fileURL: self.fileURL,
            projectRootURL: self.projectRootURL,
            session: session,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink,
            onDirtyStateChange: { isDirty in
                closeCoordinator.updateDirtyState(isDirty)
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        configureHostingViewForGlass(hostingController.view)
        self.hostingController = hostingController
        let window = NSWindow(contentViewController: hostingController)
        window.title = Self.windowTitle(fileURL: self.fileURL)
        window.setContentSize(NSSize(width: 900, height: 640))
        window.minSize = NSSize(width: 640, height: 420)
        window.tabbingMode = tabbingMode
        window.tabbingIdentifier = TerminalWindowController.tabbingIdentifier(projectRootURL: self.projectRootURL)
        configureDevysGlassWindow(window, toolbarIdentifier: "devys-terminal.file.toolbar")

        super.init(window: window)
        closeCoordinator.window = window
        closeCoordinator.updateDirtyState(session.document?.isDirty == true)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        _ = notification
        onSelect?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        _ = sender
        return closeCoordinator.windowShouldClose()
    }

    func setProjectRootURL(_ url: URL?) {
        let standardizedURL = url?.standardizedFileURL
        guard projectRootURL != standardizedURL else { return }
        projectRootURL = standardizedURL
        window?.tabbingIdentifier = TerminalWindowController.tabbingIdentifier(projectRootURL: standardizedURL)
        let store = Store(initialState: FileTabFeature.State(fileURL: fileURL, projectRootURL: standardizedURL)) {
            FileTabFeature()
        }
        self.store = store
        hostingController.rootView = FileTabRootView(
            fileURL: fileURL,
            projectRootURL: standardizedURL,
            session: session,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink,
            onDirtyStateChange: { [closeCoordinator] isDirty in
                closeCoordinator.updateDirtyState(isDirty)
            }
        )
    }

    private static func windowTitle(fileURL: URL) -> String {
        let name = fileURL.lastPathComponent
        return name.isEmpty ? fileURL.path : name
    }
}

@MainActor
final class ReaderWindowController: NSWindowController, NSWindowDelegate {
    let id = UUID()
    let windowGroupID: UUID
    var onClose: (() -> Void)?
    var onSelect: (() -> Void)?
    var closeDecision: (CloseSubject) -> CloseDecision {
        get { closeCoordinator.closeDecision }
        set { closeCoordinator.closeDecision = newValue }
    }
    var onCloseProgressChange: (() -> Void)? {
        get { closeCoordinator.onCloseProgressChange }
        set { closeCoordinator.onCloseProgressChange = newValue }
    }
    var isCompletingClose: Bool {
        closeCoordinator.isCompletingClose
    }
    private(set) var projectRootURL: URL?
    private let fileURL: URL
    private let session: EditorPreviewSession
    private var store: StoreOf<ReaderTabFeature>
    private let drawerStore: StoreOf<ProjectDrawerFeature>
    private let appCommandSink: AppWindowCommandSink
    private let closeCoordinator: DevysDirtyDocumentCloseCoordinator
    private let hostingController: NSHostingController<ReaderTabRootView>

    init(
        tabbingMode: NSWindow.TabbingMode,
        windowGroupID: UUID,
        projectRootURL: URL?,
        fileURL: URL,
        editorSessionCache: EditorSessionCache,
        appCommandSink: AppWindowCommandSink
    ) {
        self.windowGroupID = windowGroupID
        self.projectRootURL = projectRootURL?.standardizedFileURL
        self.fileURL = fileURL.standardizedFileURL
        self.appCommandSink = appCommandSink
        let session = editorSessionCache.session(
            id: id,
            url: self.fileURL,
            previewRequest: DocumentPreviewRequest(maxBytes: 1_500_000)
        )
        self.session = session
        let store = Store(initialState: ReaderTabFeature.State(fileURL: self.fileURL, projectRootURL: self.projectRootURL)) {
            ReaderTabFeature()
        }
        self.store = store
        let drawerStore = Store(initialState: ProjectDrawerFeature.State(projectRootURL: self.projectRootURL)) {
            ProjectDrawerFeature()
        }
        self.drawerStore = drawerStore
        let closeCoordinator = DevysDirtyDocumentCloseCoordinator(id: id, fileURL: self.fileURL, session: session)
        self.closeCoordinator = closeCoordinator
        let rootView = ReaderTabRootView(
            fileURL: self.fileURL,
            projectRootURL: self.projectRootURL,
            session: session,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink,
            onDirtyStateChange: { isDirty in
                closeCoordinator.updateDirtyState(isDirty)
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        configureHostingViewForGlass(hostingController.view)
        self.hostingController = hostingController
        let window = NSWindow(contentViewController: hostingController)
        window.title = Self.windowTitle(fileURL: self.fileURL)
        window.setContentSize(NSSize(width: 900, height: 720))
        window.minSize = NSSize(width: 640, height: 480)
        window.tabbingMode = tabbingMode
        window.tabbingIdentifier = TerminalWindowController.tabbingIdentifier(projectRootURL: self.projectRootURL)
        configureDevysGlassWindow(window, toolbarIdentifier: "devys-terminal.reader.toolbar")

        super.init(window: window)
        closeCoordinator.window = window
        closeCoordinator.updateDirtyState(session.document?.isDirty == true)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        _ = notification
        onSelect?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        _ = sender
        return closeCoordinator.windowShouldClose()
    }

    func setProjectRootURL(_ url: URL?) {
        let standardizedURL = url?.standardizedFileURL
        guard projectRootURL != standardizedURL else { return }
        projectRootURL = standardizedURL
        window?.tabbingIdentifier = TerminalWindowController.tabbingIdentifier(projectRootURL: standardizedURL)
        let store = Store(initialState: ReaderTabFeature.State(fileURL: fileURL, projectRootURL: standardizedURL)) {
            ReaderTabFeature()
        }
        self.store = store
        hostingController.rootView = ReaderTabRootView(
            fileURL: fileURL,
            projectRootURL: standardizedURL,
            session: session,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink,
            onDirtyStateChange: { [closeCoordinator] isDirty in
                closeCoordinator.updateDirtyState(isDirty)
            }
        )
    }

    private static func windowTitle(fileURL: URL) -> String {
        let name = fileURL.lastPathComponent
        return name.isEmpty ? fileURL.path : name
    }
}

@MainActor
final class DiffWindowController: NSWindowController, NSWindowDelegate {
    let id = UUID()
    let windowGroupID: UUID
    var onClose: (() -> Void)?
    var onSelect: (() -> Void)?
    var closeDecision: (CloseSubject) -> CloseDecision = { _ in .deny }
    private(set) var projectRootURL: URL?
    private let change: GitFileChange
    private var store: StoreOf<DiffTabFeature>
    private let drawerStore: StoreOf<ProjectDrawerFeature>
    private let appCommandSink: AppWindowCommandSink
    private let hostingController: NSHostingController<DiffTabRootView>

    init(
        tabbingMode: NSWindow.TabbingMode,
        windowGroupID: UUID,
        projectRootURL: URL?,
        change: GitFileChange,
        appCommandSink: AppWindowCommandSink
    ) {
        self.windowGroupID = windowGroupID
        self.projectRootURL = projectRootURL?.standardizedFileURL
        self.change = change
        self.appCommandSink = appCommandSink
        let store = Store(initialState: DiffTabFeature.State(change: change, projectRootURL: self.projectRootURL)) {
            DiffTabFeature()
        }
        self.store = store
        let drawerStore = Store(initialState: ProjectDrawerFeature.State(projectRootURL: self.projectRootURL)) {
            ProjectDrawerFeature()
        }
        self.drawerStore = drawerStore
        let rootView = DiffTabRootView(
            projectRootURL: self.projectRootURL,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink
        )
        let hostingController = NSHostingController(rootView: rootView)
        configureHostingViewForGlass(hostingController.view)
        self.hostingController = hostingController
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Diff: \(change.filename)"
        window.setContentSize(NSSize(width: 980, height: 700))
        window.minSize = NSSize(width: 720, height: 460)
        window.tabbingMode = tabbingMode
        window.tabbingIdentifier = TerminalWindowController.tabbingIdentifier(projectRootURL: self.projectRootURL)
        configureDevysGlassWindow(window, toolbarIdentifier: "devys-terminal.diff.toolbar")

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        _ = notification
        onSelect?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        _ = sender
        return closeDecision(CloseSubject(id: id, kind: .plain)) == .allow
    }

    func setProjectRootURL(_ url: URL?) {
        let standardizedURL = url?.standardizedFileURL
        guard projectRootURL != standardizedURL else { return }
        projectRootURL = standardizedURL
        window?.tabbingIdentifier = TerminalWindowController.tabbingIdentifier(projectRootURL: standardizedURL)
        let store = Store(initialState: DiffTabFeature.State(change: change, projectRootURL: standardizedURL)) {
            DiffTabFeature()
        }
        self.store = store
        hostingController.rootView = DiffTabRootView(
            projectRootURL: standardizedURL,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink
        )
    }
}

@MainActor
private final class BrowserWindowTitleTarget {
    weak var window: NSWindow?
}

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let id = UUID()
    let windowGroupID: UUID
    var onClose: (() -> Void)?
    var onSelect: (() -> Void)?
    var closeDecision: (CloseSubject) -> CloseDecision = { _ in .deny }
    private(set) var projectRootURL: URL?
    private let url: URL
    private var store: StoreOf<BrowserTabFeature>
    private let drawerStore: StoreOf<ProjectDrawerFeature>
    private let appCommandSink: AppWindowCommandSink
    private let session: BrowserSession
    private let titleTarget = BrowserWindowTitleTarget()
    private let hostingController: NSHostingController<BrowserTabRootView>

    init(
        tabbingMode: NSWindow.TabbingMode,
        windowGroupID: UUID,
        projectRootURL: URL?,
        url: URL,
        fileReadAccessURL: URL?,
        browserSessionCache: BrowserSessionCache,
        appCommandSink: AppWindowCommandSink
    ) {
        self.windowGroupID = windowGroupID
        self.projectRootURL = projectRootURL?.standardizedFileURL
        self.appCommandSink = appCommandSink
        let standardizedURL = url.standardizedForBrowserTab
        self.url = standardizedURL
        let store = Store(
            initialState: BrowserTabFeature.State(
                url: standardizedURL,
                projectRootURL: self.projectRootURL,
                fileReadAccessURL: fileReadAccessURL
            )
        ) {
            BrowserTabFeature()
        }
        self.store = store
        let drawerStore = Store(initialState: ProjectDrawerFeature.State(projectRootURL: self.projectRootURL)) {
            ProjectDrawerFeature()
        }
        self.drawerStore = drawerStore
        session = browserSessionCache.session(id: id, url: standardizedURL, fileReadAccessURL: fileReadAccessURL)
        let rootView = BrowserTabRootView(
            session: session,
            projectRootURL: self.projectRootURL,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink,
            onTitleChange: { [weak titleTarget] title in
                titleTarget?.window?.title = title
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        configureHostingViewForGlass(hostingController.view)
        self.hostingController = hostingController
        let window = NSWindow(contentViewController: hostingController)
        window.title = store.displayTitle
        titleTarget.window = window
        window.setContentSize(NSSize(width: 980, height: 700))
        window.minSize = NSSize(width: 720, height: 460)
        window.tabbingMode = tabbingMode
        window.tabbingIdentifier = TerminalWindowController.tabbingIdentifier(projectRootURL: self.projectRootURL)
        configureDevysGlassWindow(window, toolbarIdentifier: "devys-terminal.browser.toolbar")

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        _ = notification
        onSelect?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        _ = sender
        return closeDecision(CloseSubject(id: id, kind: .plain)) == .allow
    }

    func setProjectRootURL(_ url: URL?) {
        let standardizedURL = url?.standardizedFileURL
        guard projectRootURL != standardizedURL else { return }
        projectRootURL = standardizedURL
        window?.tabbingIdentifier = TerminalWindowController.tabbingIdentifier(projectRootURL: standardizedURL)
        let fileReadAccessURL = self.url.isFileURL
            ? BrowserTabRouting.readAccessURL(for: self.url, projectRootURL: standardizedURL)
            : nil
        let store = Store(
            initialState: BrowserTabFeature.State(
                url: self.url,
                projectRootURL: standardizedURL,
                fileReadAccessURL: fileReadAccessURL
            )
        ) {
            BrowserTabFeature()
        }
        self.store = store
        hostingController.rootView = BrowserTabRootView(
            session: session,
            projectRootURL: standardizedURL,
            store: store,
            drawerStore: drawerStore,
            appCommandSink: appCommandSink,
            onTitleChange: { [weak self] title in
                self?.window?.title = title
            }
        )
    }
}

private struct TerminalTabRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isProjectDropTargeted = false
    let windowID: UUID
    let commandSink: TerminalProductCommandSink
    let projectRootURL: URL?
    let store: StoreOf<TerminalTabFeature>
    let drawerStore: StoreOf<ProjectDrawerFeature>
    let appCommandSink: AppWindowCommandSink
    let onCloseRiskChange: @MainActor @Sendable (TerminalProductCloseRisk?) -> Void

    var body: some View {
        let theme = DevysThemeRegistry.theme(for: .system, systemColorScheme: colorScheme)

        ZStack {
            WindowVibrancyBackground()
                .ignoresSafeArea()
            theme.base.opacity(0.36)
                .ignoresSafeArea()

            ProjectDrawerRootView(projectRootURL: projectRootURL, store: drawerStore, appCommandSink: appCommandSink) {
                terminalProduct
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.theme, theme)
            .onDrop(
                of: [UTType.fileURL.identifier],
                isTargeted: $isProjectDropTargeted,
                perform: handleProjectDrop
            )
    }

    @ViewBuilder
    private var terminalProduct: some View {
        TerminalProductView(
            commandSink: commandSink,
            workingDirectory: projectRootURL,
            composerPresentation: .edgeDrawer,
            isComposerVisible: Binding(
                get: { store.isComposerPresented },
                set: { store.send(.composerPresentationChanged($0)) }
            ),
            onWorkingDirectoryChange: handleWorkingDirectoryChange,
            onCloseRiskChange: onCloseRiskChange
        )
            .frame(minWidth: 720, minHeight: 420)
    }

    private func handleWorkingDirectoryChange(_ url: URL) {
        store.send(.workingDirectoryChanged(url.standardizedFileURL))
        appCommandSink.terminalWorkingDirectoryDidChange(windowID, url.standardizedFileURL)
    }

    private func handleProjectDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = Self.droppedURL(from: item),
                      Self.isDirectory(url) else {
                    return
                }
                Task { @MainActor in
                    appCommandSink.bindDroppedProjectRoot(url.standardizedFileURL)
                }
            }
            return true
        }
        return false
    }

    nonisolated private static func droppedURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

@MainActor
struct ProjectDrawerRootView<Content: View>: View {
    let projectRootURL: URL?
    var gitRefreshKey: String?
    let store: StoreOf<ProjectDrawerFeature>
    let appCommandSink: AppWindowCommandSink
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false
    @State private var hideTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    init(
        projectRootURL: URL?,
        store: StoreOf<ProjectDrawerFeature>,
        gitRefreshKey: String? = nil,
        appCommandSink: AppWindowCommandSink,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.projectRootURL = projectRootURL
        self.gitRefreshKey = gitRefreshKey
        self.appCommandSink = appCommandSink
        self.store = store
        self.content = content
    }

    var body: some View {
        rootContent
            .onExitCommand { hide() }
            .onDisappear { hideTask?.cancel() }
            .task(id: "\(projectRootURL?.standardizedFileURL.path ?? "unbound"):\(gitRefreshKey ?? "initial")") {
                store.send(.task(projectRootURL: projectRootURL))
                refreshGitStatus()
            }
            .task(id: requestKey) {
                await refreshFileBrowser()
            }
    }

    private var pinnedDrawerWidth: CGFloat { 300 }
    private var transientDrawerWidth: CGFloat { 320 }

    @ViewBuilder
    private var rootContent: some View {
        Group {
            if store.isPinned {
                HStack(spacing: 0) {
                    drawer
                        .frame(width: pinnedDrawerWidth)
                    content()
                }
                .animation(Animations.micro, value: store.isPinned)
            } else {
                ZStack(alignment: .leading) {
                    content()

                    if store.isTransientlyVisible {
                        drawer
                            .frame(width: transientDrawerWidth)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .onHover { hovering in
                                isHovering = hovering
                                if hovering { reveal() } else { scheduleHide() }
                            }
                    }

                    edgeHoverStrip
                }
                .animation(Animations.micro, value: store.isTransientlyVisible)
            }
        }
        .background(keyboardShortcuts)
    }

    private var edgeHoverStrip: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.clear)
                .frame(width: 12)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                    if hovering { reveal() } else { scheduleHide() }
                }
            Spacer(minLength: 0)
        }
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: Spacing.relaxed) {
            header
            body(in: projectRootURL)
            Spacer(minLength: 0)
        }
        .padding(Spacing.relaxed)
        .vibrantSurface(.overlay)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project navigator")
    }

    private var header: some View {
        HStack(spacing: Spacing.normal) {
            Text(projectName)
                .font(Typography.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("⌘P")
                .font(Typography.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func body(in projectRootURL: URL?) -> some View {
        if projectRootURL != nil {
            GeometryReader { proxy in
                let sectionMaxHeight = max(120, proxy.size.height / 2)

                VStack(alignment: .leading, spacing: Spacing.relaxed) {
                    changesSection(maxHeight: sectionMaxHeight)
                    filesSection()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: Spacing.normal) {
                Text("No project open")
                    .font(Typography.body.weight(.semibold))
                Text("Open a folder to enable files and changes.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func changesSection(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.normal) {
            sectionHeader(
                title: "Changes",
                count: store.gitChanges.isEmpty ? nil : store.gitChanges.count,
                trailing: { store.gitIsLoading ? AnyView(ProgressView().controlSize(.small)) : AnyView(EmptyView()) },
                isExpanded: Binding(
                    get: { store.changesExpanded },
                    set: { store.send(.setChangesExpanded($0)) }
                ),
                onToggle: {}
            )

            if store.changesExpanded {
                if let gitErrorMessage = store.gitErrorMessage {
                    Text(gitErrorMessage)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !store.gitIsRepositoryAvailable {
                    EmptyView()
                } else if store.gitChanges.isEmpty {
                    EmptyView()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Spacing.borderWidth) {
                            gitChangeGroup(title: "Staged Changes", changes: stagedChanges)
                            gitChangeGroup(title: "Changes", changes: unstagedChanges)
                            gitChangeGroup(title: "Untracked", changes: untrackedChanges)
                        }
                        .padding(.vertical, Spacing.tight)
                    }
                    .frame(height: cappedListHeight(
                        rowCount: store.gitChanges.count,
                        maxHeight: maxHeight - sectionHeaderAndSpacingHeight
                    ))
                }
            }
        }
    }

    @ViewBuilder
    private func filesSection() -> some View {
        VStack(alignment: .leading, spacing: Spacing.normal) {
            sectionHeader(
                title: "Files",
                count: nil,
                trailing: { AnyView(EmptyView()) },
                isExpanded: Binding(
                    get: { store.filesExpanded },
                    set: { store.send(.setFilesExpanded($0)) }
                ),
                onToggle: {}
            )

            if store.filesExpanded {
                searchField
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.borderWidth) {
                        ForEach(drawerFileRows) { row in
                            projectFileRow(row)
                        }
                    }
                    .padding(.vertical, Spacing.tight)
                }
                .overlay {
                    if store.filesIsLoading && store.fileRows.isEmpty {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(
                    minHeight: store.filesIsLoading && store.fileRows.isEmpty ? 80 : 0,
                    maxHeight: .infinity
                )
            }
        }
        .frame(maxHeight: store.filesExpanded ? .infinity : nil, alignment: .top)
    }

    private var drawerRowHeight: CGFloat { DensityLayout(.comfortable).sidebarRowHeight }
    private var sectionHeaderAndSpacingHeight: CGFloat { Spacing.iconXl + Spacing.normal }

    private func cappedListHeight(
        rowCount: Int,
        maxHeight: CGFloat,
        minimumWhenLoading: CGFloat = 0
    ) -> CGFloat {
        guard rowCount > 0 else {
            return min(max(minimumWhenLoading, 0), max(maxHeight, 0))
        }

        let contentHeight = CGFloat(rowCount) * drawerRowHeight + (Spacing.tight * 2)
        return min(max(contentHeight, minimumWhenLoading), max(maxHeight, 0))
    }

    private var searchField: some View {
        HStack(spacing: Spacing.normal) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "Filter files",
                text: Binding(
                    get: { store.searchQuery },
                    set: { store.send(.searchQueryChanged($0)) }
                )
            )
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {
                    if let firstFile = drawerFileRows.first(where: { !$0.isDirectory }) {
                        openFile(firstFile.url)
                        store.send(.clearSearch)
                        searchFocused = false
                    }
                }
            if !store.searchQuery.isEmpty {
                Button {
                    store.send(.clearSearch)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .font(Typography.caption)
        .padding(.horizontal, Spacing.normal)
        .padding(.vertical, Spacing.normal)
        .background(searchFieldBackground, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
    }

    @Environment(\.theme) private var theme

    private var searchFieldBackground: Color {
        searchFocused ? theme.cardHover : theme.card
    }

    private func sectionHeader(
        title: String,
        count: Int?,
        trailing: () -> AnyView,
        isExpanded: Binding<Bool>,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
            onToggle()
        } label: {
            HStack(spacing: Spacing.normal) {
                Image(systemName: "chevron.right")
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                Text(title)
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let count {
                    Text("\(count)")
                        .font(Typography.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                trailing()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title) section")
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
    }

    private var keyboardShortcuts: some View {
        ZStack {
            Button {
                togglePin()
            } label: {
                EmptyView()
            }
            .keyboardShortcut("0", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            Button {
                focusSearch()
            } label: {
                EmptyView()
            }
            .keyboardShortcut("p", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func gitChangeGroup(title: String, changes: [GitFileChange]) -> some View {
        if !changes.isEmpty {
            HStack(spacing: Spacing.normal) {
                Text(title)
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text("\(changes.count)")
                    .font(Typography.micro.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.normal)
            .padding(.top, Spacing.tight)
            .padding(.bottom, Spacing.borderWidth * 2)

            ForEach(changes) { change in
                gitChangeRow(change)
            }
        }
    }

    private func gitChangeRow(_ change: GitFileChange) -> some View {
        DiffRow(
            fileName: change.path,
            gitStatus: uiGitStatus(for: change),
            isStaged: change.isStaged,
            onTap: { openDiff(change) },
            onDoubleTap: { openDiffInNewWindow(change) }
        )
        .contextMenu {
            Button("Open Diff in Tab") { openDiff(change) }
            Button("Open Diff in New Window") { openDiffInNewWindow(change) }
            if canStage(change) {
                Button("Stage") {
                    performGitFileAction(.stage, change: change)
                }
            }
            if change.isStaged {
                Button("Unstage") {
                    performGitFileAction(.unstage, change: change)
                }
            }
            if canDiscard(change) {
                Button("Discard Changes", role: .destructive) {
                    performGitFileAction(.discard, change: change)
                }
            }
            Divider()
            Button("Copy Path") {
                appCommandSink.copyPath(change.path)
            }
        }
        .accessibilityLabel("\(change.filename), \(change.status.rawValue)")
        .accessibilityHint("Open diff in a native tab")
    }

    private func projectFileRow(_ row: DevysProjectFileRow) -> some View {
        DevysProjectFileRowView(
            row: row,
            directoryIcon: directoryIcon(for: row.url),
            onTap: {
                if row.isDirectory {
                    toggleDirectory(row.url)
                } else {
                    openFile(row.url)
                }
            },
            onDoubleTap: row.isDirectory ? nil : { openFileInNewWindow(row.url) },
            onOpenInTab: { openFile(row.url) },
            onOpenInNewWindow: { openFileInNewWindow(row.url) },
            onOpenSourceInTab: { openSourceFile(row.url) },
            onOpenSourceInNewWindow: { openSourceFileInNewWindow(row.url) },
            onRevealInFinder: { appCommandSink.revealInFinder(row.url) },
            onCopyPath: { appCommandSink.copyPath(row.url.path) }
        )
    }

    private var drawerFileRows: [DevysProjectFileRow] {
        store.fileRows.map { row in
            DevysProjectFileRow(url: row.url, isDirectory: row.isDirectory, depth: row.depth)
        }
    }

    // MARK: - State helpers

    private var projectName: String {
        guard let projectRootURL else { return "Project" }
        let name = projectRootURL.lastPathComponent
        return name.isEmpty ? projectRootURL.path : name
    }

    private var requestKey: DevysProjectFileBrowserRequestKey {
        DevysProjectFileBrowserRequestKey(
            rootPath: projectRootURL?.standardizedFileURL.path,
            query: store.trimmedSearchQuery,
            expandedDirectoryPaths: store.expandedDirectoryPaths.sorted()
        )
    }

    private func togglePin() {
        store.send(.togglePin)
    }

    private func focusSearch() {
        if !store.isPinned { reveal() }
        if !store.filesExpanded {
            store.send(.setFilesExpanded(true))
        }
        searchFocused = true
    }

    private func reveal() {
        guard !store.isPinned else { return }
        hideTask?.cancel()
        withAnimation(Animations.micro) {
            store.send(.reveal)
        }
    }

    private func hide() {
        guard !store.isPinned else { return }
        hideTask?.cancel()
        withAnimation(Animations.micro) {
            store.send(.hide)
        }
    }

    private func scheduleHide() {
        guard !store.isPinned else { return }
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !isHovering else { return }
            withAnimation(Animations.micro) {
                store.send(.hide)
            }
        }
    }

    private func toggleDirectory(_ url: URL) {
        store.send(.toggleDirectory(url))
    }

    private func directoryIcon(for url: URL) -> String {
        store.expandedDirectoryPaths.contains(url.standardizedFileURL.path)
            ? "folder.fill"
            : "folder"
    }

    private func openFile(_ url: URL) {
        appCommandSink.openFileInCurrentWindowGroup(url, projectRootURL)
    }

    private func openFileInNewWindow(_ url: URL) {
        appCommandSink.openFileInNewWindow(url, projectRootURL)
    }

    private func openSourceFile(_ url: URL) {
        appCommandSink.openSourceFileInCurrentWindowGroup(url, projectRootURL)
    }

    private func openSourceFileInNewWindow(_ url: URL) {
        appCommandSink.openSourceFileInNewWindow(url, projectRootURL)
    }

    private var stagedChanges: [GitFileChange] {
        store.gitChanges.filter(\.isStaged)
    }

    private var unstagedChanges: [GitFileChange] {
        store.gitChanges.filter { !$0.isStaged && $0.status != .untracked }
    }

    private var untrackedChanges: [GitFileChange] {
        store.gitChanges.filter { !$0.isStaged && $0.status == .untracked }
    }

    private func openDiff(_ change: GitFileChange) {
        appCommandSink.openDiffInCurrentWindowGroup(change, projectRootURL)
    }

    private func openDiffInNewWindow(_ change: GitFileChange) {
        appCommandSink.openDiffInNewWindow(change, projectRootURL)
    }

    private func refreshGitStatus() {
        store.send(.gitRefreshRequested)
    }

    private func refreshFileBrowser() async {
        guard let projectRootURL else {
            store.send(.fileRowsLoaded([]))
            return
        }
        store.send(.fileRowsLoadingChanged(true))
        let rows = await ProjectFilesClient.liveValue.loadRows(
            ProjectFilesRequest(
                rootURL: projectRootURL.standardizedFileURL,
                expandedDirectoryPaths: store.expandedDirectoryPaths,
                query: store.trimmedSearchQuery
            )
        )
        store.send(.fileRowsLoaded(rows))
    }

    private func performGitFileAction(_ action: DevysGitFileAction, change: GitFileChange) {
        switch action {
        case .stage:
            store.send(.gitStageFileRequested(change))
        case .unstage:
            store.send(.gitUnstageFileRequested(change))
        case .discard:
            store.send(.gitDiscardFileRequested(change))
        }
    }

    private func canStage(_ change: GitFileChange) -> Bool {
        !change.isStaged && change.status != .ignored && change.status != .unmerged
    }

    private func canDiscard(_ change: GitFileChange) -> Bool {
        !change.isStaged && change.status != .ignored && change.status != .unmerged
    }

    private func uiGitStatus(for change: GitFileChange) -> GitFileStatus {
        if change.isStaged { return .staged }

        switch change.status {
        case .added, .untracked:
            return .new
        case .modified, .copied:
            return .modified
        case .deleted:
            return .deleted
        case .renamed:
            return .renamed
        case .ignored:
            return .ignored
        case .unmerged:
            return .conflict
        }
    }

}

private enum DevysGitFileAction: Sendable, Equatable {
    case stage
    case unstage
    case discard
}

private struct DevysProjectFileBrowserRequestKey: Hashable {
    let rootPath: String?
    let query: String
    let expandedDirectoryPaths: [String]
}

private struct DevysProjectFileRow: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool
    let depth: Int

    var id: String { url.path }

    var title: String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}

private struct DevysProjectFileRowView: View {
    let row: DevysProjectFileRow
    let directoryIcon: String
    let onTap: () -> Void
    let onDoubleTap: (() -> Void)?
    let onOpenInTab: () -> Void
    let onOpenInNewWindow: () -> Void
    let onOpenSourceInTab: () -> Void
    let onOpenSourceInNewWindow: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.normal) {
            Color.clear
                .frame(width: CGFloat(row.depth) * Spacing.relaxed)
            Image(systemName: row.isDirectory ? directoryIcon : "doc.text")
                .font(.system(size: Spacing.iconMd, weight: .medium))
                .foregroundStyle(row.isDirectory ? .primary : .secondary)
                .frame(width: Spacing.iconLg)
            Text(row.title)
                .font(Typography.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.normal)
        .padding(.vertical, Spacing.tight + Spacing.borderWidth)
        .background(
            isHovered ? theme.text.opacity(0.05) : .clear,
            in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .onTapGesture(count: 2) {
            (onDoubleTap ?? onTap)()
        }
        .onTapGesture(count: 1) {
            onTap()
        }
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
        .contextMenu {
            if !row.isDirectory {
                Button("Open in Tab") { onOpenInTab() }
                Button("Open in New Window") { onOpenInNewWindow() }
                if BrowserTabRouting.isBrowserPreviewFile(row.url) {
                    Button("Open Source in Tab") { onOpenSourceInTab() }
                    Button("Open Source in New Window") { onOpenSourceInNewWindow() }
                }
                Button("Reveal in Finder") {
                    onRevealInFinder()
                }
            }
            Button("Copy Path") {
                onCopyPath()
            }
        }
        .accessibilityLabel(row.title)
        .accessibilityHint(row.isDirectory ? "Expand or collapse folder" : "Open file in a native tab")
    }
}

private struct FileTabRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    let fileURL: URL
    let projectRootURL: URL?
    let session: EditorPreviewSession
    let store: StoreOf<FileTabFeature>
    let drawerStore: StoreOf<ProjectDrawerFeature>
    let appCommandSink: AppWindowCommandSink
    let onDirtyStateChange: (Bool) -> Void

    init(
        fileURL: URL,
        projectRootURL: URL?,
        session: EditorPreviewSession,
        store: StoreOf<FileTabFeature>,
        drawerStore: StoreOf<ProjectDrawerFeature>,
        appCommandSink: AppWindowCommandSink,
        onDirtyStateChange: @escaping (Bool) -> Void
    ) {
        self.fileURL = fileURL
        self.projectRootURL = projectRootURL
        self.session = session
        self.store = store
        self.drawerStore = drawerStore
        self.appCommandSink = appCommandSink
        self.onDirtyStateChange = onDirtyStateChange
    }

    var body: some View {
        let theme = DevysThemeRegistry.theme(for: .system, systemColorScheme: colorScheme)

        ZStack {
            WindowVibrancyBackground()
                .ignoresSafeArea()
            theme.base.opacity(0.36)
                .ignoresSafeArea()
            ProjectDrawerRootView(projectRootURL: projectRootURL, store: drawerStore, appCommandSink: appCommandSink) {
                VStack(spacing: 0) {
                    fileHeader
                    Divider()
                    fileBody
                }
            }
        }
        .environment(\.theme, theme)
        .task(id: fileURL) {
            store.send(.task)
            session.open(fileURL)
        }
        .onChange(of: session.document?.isDirty == true, initial: true) { _, isDirty in
            store.send(.dirtyStateChanged(isDirty))
            onDirtyStateChange(isDirty)
        }
        .onChange(of: session.document != nil, initial: true) { _, isLoaded in
            guard isLoaded else { return }
            store.send(.editorLoaded)
        }
    }

    private var fileHeader: some View {
        HStack(spacing: Spacing.normal) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.fileURL.lastPathComponent.isEmpty ? store.fileURL.path : store.fileURL.lastPathComponent)
                    .font(Typography.body.weight(.semibold))
                    .lineLimit(1)
                Text(store.relativePath)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if store.isDirty {
                HStack(spacing: Spacing.tight) {
                    StatusDot(.waiting, size: 7)
                    Text("Unsaved")
                        .font(Typography.caption)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Unsaved changes")
            }
            Button {
                store.send(.revealInFinderRequested)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reveal in Finder")
        }
        .padding(.horizontal, Spacing.relaxed)
        .padding(.vertical, Spacing.comfortable)
    }

    @ViewBuilder
    private var fileBody: some View {
        if let document = session.document {
            let codeViewDesign = CodeViewDesign.resolved(for: colorScheme)
            EditorView(
                document: document,
                isEditable: true,
                usesGlassBackground: codeViewDesign.surfaceDesign.usesGlassBackground
            )
                .padding(Spacing.comfortable)
        } else {
            switch store.phase {
            case .failed(let message):
                ContentUnavailableView("Cannot Open File", systemImage: "exclamationmark.triangle", description: Text(message))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .preview(let preview) where preview.isBinary:
                ContentUnavailableView("Binary File", systemImage: "doc", description: Text(store.relativePath))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .preview(let preview) where preview.isTooLarge:
                ContentUnavailableView("File Too Large", systemImage: "doc.text.magnifyingglass", description: Text(tooLargeMessage(for: preview)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .idle, .loading, .preview, .loaded:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func tooLargeMessage(for preview: LoadedDocumentPreview) -> String {
        guard let fileSize = preview.revision.fileSize else {
            return "\(store.relativePath) exceeds the preview limit."
        }
        let fileSizeLabel = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        let limitLabel = ByteCountFormatter.string(fromByteCount: Int64(preview.maxBytes), countStyle: .file)
        return "\(fileSizeLabel) exceeds \(limitLabel)."
    }
}

private func makePortProvider(for projectRootURL: URL?) -> BrowserPortProvider? {
    guard let projectRootURL else { return nil }
    let standardized = projectRootURL.standardizedFileURL
    return {
        let detected = (try? await LocalPortsClient.liveValue.detect(standardized)) ?? []
        return detected.map { BrowserDetectedPort(port: $0.port, processName: $0.processName) }
    }
}

private struct BrowserTabRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    let session: BrowserSession
    let projectRootURL: URL?
    let store: StoreOf<BrowserTabFeature>
    let drawerStore: StoreOf<ProjectDrawerFeature>
    let appCommandSink: AppWindowCommandSink
    let onTitleChange: (String) -> Void

    var body: some View {
        let theme = DevysThemeRegistry.theme(for: .system, systemColorScheme: colorScheme)

        ZStack {
            WindowVibrancyBackground()
                .ignoresSafeArea()
            theme.base.opacity(0.36)
                .ignoresSafeArea()
            ProjectDrawerRootView(projectRootURL: projectRootURL, store: drawerStore, appCommandSink: appCommandSink) {
                BrowserContentView(
                    session: session,
                    portProvider: makePortProvider(for: projectRootURL),
                    localhostActions: appLocalhostActions
                )
            }
        }
        .environment(\.theme, theme)
        .onAppear {
            publishMetadata()
        }
        .onChange(of: session.url, initial: true) { _, _ in
            publishMetadata()
        }
        .onChange(of: session.tabTitle, initial: true) { _, _ in
            publishMetadata()
        }
        .onChange(of: store.displayTitle, initial: true) { _, title in
            onTitleChange(title)
            store.send(.titlePublished)
        }
    }

    private func publishMetadata() {
        store.send(
            .metadataChanged(
                BrowserTabMetadata(
                    url: session.url,
                    title: session.tabTitle
                )
            )
        )
    }
}

private let appLocalhostActions: [BrowserLocalhostAction] = [
    BrowserLocalhostAction(port: 3000, label: "Next.js / CRA / Express"),
    BrowserLocalhostAction(port: 4000, label: "Phoenix"),
    BrowserLocalhostAction(port: 4200, label: "Angular"),
    BrowserLocalhostAction(port: 4321, label: "Astro"),
    BrowserLocalhostAction(port: 5000, label: "Flask"),
    BrowserLocalhostAction(port: 5173, label: "Vite / SvelteKit"),
    BrowserLocalhostAction(port: 8000, label: "Django"),
    BrowserLocalhostAction(port: 8080, label: "Vue / Webpack")
]

private struct DiffTabRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    let projectRootURL: URL?
    let store: StoreOf<DiffTabFeature>
    let drawerStore: StoreOf<ProjectDrawerFeature>
    let appCommandSink: AppWindowCommandSink

    init(
        projectRootURL: URL?,
        store: StoreOf<DiffTabFeature>,
        drawerStore: StoreOf<ProjectDrawerFeature>,
        appCommandSink: AppWindowCommandSink
    ) {
        self.projectRootURL = projectRootURL
        self.store = store
        self.drawerStore = drawerStore
        self.appCommandSink = appCommandSink
    }

    var body: some View {
        let theme = DevysThemeRegistry.theme(for: .system, systemColorScheme: colorScheme)

        ZStack {
            WindowVibrancyBackground()
                .ignoresSafeArea()
            theme.base.opacity(0.36)
                .ignoresSafeArea()
            ProjectDrawerRootView(
                projectRootURL: projectRootURL,
                store: drawerStore,
                gitRefreshKey: String(store.gitRefreshCount),
                appCommandSink: appCommandSink
            ) {
                VStack(spacing: 0) {
                    diffHeader
                    Divider()
                    diffBody
                }
            }
        }
        .environment(\.theme, theme)
        .task(id: store.change.id) {
            store.send(.task)
        }
    }

    private var diffHeader: some View {
        HStack(spacing: Spacing.relaxed) {
            HStack(spacing: Spacing.relaxed) {
                Image(systemName: store.change.status.appIconName)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.change.filename)
                        .font(Typography.body.weight(.semibold))
                        .lineLimit(1)
                    Text(store.statusMessage)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if store.isGitActionRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                store.send(.fileActionRequested(store.change.isStaged ? .unstage : .stage))
            }
            .contextMenu {
                if store.change.isStaged {
                    Button("Unstage File") {
                        store.send(.fileActionRequested(.unstage))
                    }
                } else {
                    Button("Stage File") {
                        store.send(.fileActionRequested(.stage))
                    }
                    if store.canDiscardActiveChange {
                        Button("Discard Changes", role: .destructive) {
                            store.send(.fileActionRequested(.discard))
                        }
                    }
                }
                Divider()
                Button("Copy Path") {
                    store.send(.copyPathRequested)
                }
            }
            .help(store.change.isStaged
                  ? "Double-click to unstage. Right-click for more."
                  : "Double-click to stage. Right-click for more.")

            GlassSegmentedControl(
                selection: Binding(
                    get: { store.mode },
                    set: { store.send(.modeChanged($0)) }
                ),
                options: [
                    .init(value: .unified, label: "Unified", symbol: "rectangle"),
                    .init(value: .split,   label: "Split",   symbol: "rectangle.split.2x1")
                ]
            )
            .frame(width: 200)
        }
        .padding(.horizontal, Spacing.relaxed)
        .padding(.vertical, Spacing.comfortable)
    }

    @ViewBuilder
    private var diffBody: some View {
        DiffDocumentView(
            filePath: store.change.path,
            snapshot: store.diffSnapshot,
            mode: store.mode,
            isLoading: store.isLoading,
            errorMessage: store.errorMessage,
            isStaged: store.change.isStaged,
            statusMessage: nil,
            onAcceptHunk: { index in
                store.send(.hunkActionRequested(.stage, hunkIndex: index))
            },
            onRejectHunk: { index in
                store.send(.hunkActionRequested(store.change.isStaged ? .unstage : .discard, hunkIndex: index))
            }
        )
    }

}

private enum DevysProjectRootResolver {
    private static let markerNames: Set<String> = [
        ".git",
        "Package.swift",
        "package.json",
        "pnpm-workspace.yaml",
        "Cargo.toml",
        "go.mod",
        "pyproject.toml",
        "deno.json",
        "bun.lockb",
    ]

    private static let markerExtensions: Set<String> = [
        "xcodeproj",
        "xcworkspace",
    ]

    static func resolveCandidateProjectRoot(from workingDirectory: URL) async -> URL? {
        let cwd = workingDirectory.standardizedFileURL
        if let gitRoot = await gitRepositoryRoot(from: cwd) {
            return gitRoot
        }
        return markerProjectRoot(from: cwd)
    }

    private static func gitRepositoryRoot(from workingDirectory: URL) async -> URL? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "rev-parse", "--show-toplevel"]
            process.currentDirectoryURL = workingDirectory

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return nil
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let output, !output.isEmpty else { return nil }
            return URL(fileURLWithPath: output).standardizedFileURL
        }.value
    }

    private static func markerProjectRoot(from workingDirectory: URL) -> URL? {
        var current: URL? = workingDirectory.standardizedFileURL
        let fileManager = FileManager.default

        while let directory = current {
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                current = parent(of: directory)
                continue
            }

            if children.contains(where: { isProjectMarker($0) }) {
                return directory
            }

            current = parent(of: directory)
        }

        return nil
    }

    private static func parent(of directory: URL) -> URL? {
        let parent = directory.deletingLastPathComponent().standardizedFileURL
        return parent == directory ? nil : parent
    }

    private static func isProjectMarker(_ url: URL) -> Bool {
        markerNames.contains(url.lastPathComponent)
            || markerExtensions.contains(url.pathExtension)
    }
}

private final class RecentProjectsStore {
    private let defaults: UserDefaults
    private let key = "com.devys.terminal.recent-project-roots"
    private let limit = 12

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var recentProjectURLs: [URL] {
        defaults.stringArray(forKey: key)?
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? []
    }

    func record(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = defaults.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > limit {
            paths = Array(paths.prefix(limit))
        }
        defaults.set(paths, forKey: key)
    }
}

@MainActor
private struct DevysMenuBuilder {
    weak var delegate: DevysAppDelegate?

    func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "Main Menu")
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(terminalMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())
        return mainMenu
    }

    private func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Devys Terminal", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Devys Terminal")
        menu.addItem(
            NSMenuItem(
                title: "About Devys Terminal",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Hide Devys Terminal", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Devys Terminal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.submenu = menu
        return item
    }

    private func fileMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "File")
        menu.addItem(menuItem("New Window", action: #selector(DevysAppDelegate.openNewWindow), key: "n", target: delegate))
        menu.addItem(menuItem("New Tab", action: #selector(DevysAppDelegate.openNewTab), key: "t", target: delegate))
        menu.addItem(menuItem("Open Browser Tab...", action: #selector(DevysAppDelegate.openBrowserLocation), key: "b", target: delegate))
        menu.addItem(menuItem("Open localhost:3000", action: #selector(DevysAppDelegate.openDefaultLocalhostBrowser), key: "", target: delegate))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Project...", action: #selector(DevysAppDelegate.openProject), key: "o", target: delegate))
        menu.addItem(
            menuItem(
                "Open Project in New Window...",
                action: #selector(DevysAppDelegate.openProjectInNewWindow),
                key: "O",
                target: delegate
            )
        )
        menu.addItem(openRecentMenuItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Save", action: #selector(MetalEditorView.saveDocument(_:)), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Save As...", action: #selector(MetalEditorView.saveDocumentAs(_:)), keyEquivalent: "S"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        item.submenu = menu
        return item
    }

    private func openRecentMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Open Recent")
        let recentProjects = RecentProjectsStore().recentProjectURLs

        if recentProjects.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Projects", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for url in recentProjects {
                let menuItem = menuItem(
                    url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                    action: #selector(DevysAppDelegate.openRecentProject(_:)),
                    key: "",
                    target: delegate
                )
                menuItem.representedObject = url.path
                menu.addItem(menuItem)
            }
        }

        item.submenu = menu
        return item
    }

    private func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Edit")
        menu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        item.submenu = menu
        return item
    }

    private func terminalMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Terminal", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Terminal")
        menu.addItem(menuItem("Focus Composer", action: #selector(DevysAppDelegate.focusComposer), key: "l", target: delegate))
        menu.addItem(menuItem("Paste Into Composer", action: #selector(DevysAppDelegate.pasteIntoComposer), key: "", target: delegate))
        menu.addItem(
            menuItem(
                "Capture Selection Into Composer",
                action: #selector(DevysAppDelegate.captureSelectionIntoComposer),
                key: "\r",
                modifiers: [.command, .shift],
                target: delegate
            )
        )
        menu.addItem(.separator())
        menu.addItem(menuItem("Bind Project to Terminal Directory", action: #selector(DevysAppDelegate.bindProjectToTerminalDirectory), key: "", target: delegate))
        menu.addItem(menuItem("Switch Project to Terminal Directory", action: #selector(DevysAppDelegate.switchProjectToTerminalDirectory), key: "", target: delegate))
        menu.addItem(menuItem("Open Terminal Directory in New Window", action: #selector(DevysAppDelegate.openTerminalDirectoryInNewWindow), key: "", target: delegate))
        menu.addItem(menuItem("Clear Project Binding", action: #selector(DevysAppDelegate.clearProjectBinding), key: "", target: delegate))
        item.submenu = menu
        return item
    }

    private func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Window")
        menu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Previous Tab", action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "{"))
        menu.addItem(NSMenuItem(title: "Show Next Tab", action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "}"))
        menu.addItem(NSMenuItem(title: "Move Tab to New Window", action: #selector(NSWindow.moveTabToNewWindow(_:)), keyEquivalent: "T"))
        menu.addItem(NSMenuItem(title: "Merge All Windows", action: #selector(NSWindow.mergeAllWindows(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }

    private func helpMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Help")
        menu.addItem(
            menuItem(
                "Devys Terminal Keyboard Shortcuts",
                action: #selector(DevysAppDelegate.showKeyboardShortcuts),
                key: "",
                target: delegate
            )
        )
        item.submenu = menu
        return item
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject?
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
