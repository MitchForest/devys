import AppKit
import Browser
import Diff
import Editor
import Foundation
import Git

@MainActor
final class DevysWindowHost {
    private var terminalWindows: Set<TerminalWindowController> = []
    private var fileWindows: Set<FileWindowController> = []
    private var diffWindows: Set<DiffWindowController> = []
    private var readerWindows: Set<ReaderWindowController> = []
    private var browserWindows: Set<BrowserWindowController> = []
    private let editorSessionCache = EditorSessionCache()
    private let browserSessionCache = BrowserSessionCache()

    var onManagedWindowClosed: (() -> Void)?
    var onManagedWindowSelected: ((UUID) -> Void)?
    var onManagedWindowStateChanged: (() -> Void)?
    var closeDecision: (CloseSubject) -> CloseDecision = { _ in .deny }
    var commandSink = AppWindowCommandSink()

    var fallbackWindow: NSWindow? {
        terminalWindows.first?.window
    }

    var keyTerminalWindowController: TerminalWindowController? {
        (NSApp.keyWindow?.windowController as? TerminalWindowController)
            ?? terminalWindows.first { $0.window?.isKeyWindow == true }
            ?? terminalWindows.first
    }

    var hasAsyncCloseInProgress: Bool {
        fileWindows.contains(where: \.isCompletingClose)
            || readerWindows.contains(where: \.isCompletingClose)
    }

    func removeAll() {
        terminalWindows.removeAll()
        fileWindows.removeAll()
        diffWindows.removeAll()
        readerWindows.removeAll()
        browserWindows.removeAll()
        editorSessionCache.removeAll()
        browserSessionCache.removeAll()
    }

    func terminalWindowController(id: UUID) -> TerminalWindowController? {
        terminalWindows.first { $0.id == id }
    }

    func terminalController(for window: NSWindow) -> TerminalWindowController? {
        if let controller = window.windowController as? TerminalWindowController {
            return controller
        }
        return window.tabGroup?.windows.compactMap {
            $0.windowController as? TerminalWindowController
        }.first
    }

    func projectRoot(for controller: NSWindowController?) -> URL? {
        if let terminalController = controller as? TerminalWindowController {
            return terminalController.projectRootURL
        }
        if let fileController = controller as? FileWindowController {
            return fileController.projectRootURL
        }
        if let readerController = controller as? ReaderWindowController {
            return readerController.projectRootURL
        }
        if let diffController = controller as? DiffWindowController {
            return diffController.projectRootURL
        }
        if let browserController = controller as? BrowserWindowController {
            return browserController.projectRootURL
        }
        return nil
    }

    func windowGroupID(for controller: NSWindowController?) -> UUID? {
        if let terminalController = controller as? TerminalWindowController {
            return terminalController.windowGroupID
        }
        if let fileController = controller as? FileWindowController {
            return fileController.windowGroupID
        }
        if let readerController = controller as? ReaderWindowController {
            return readerController.windowGroupID
        }
        if let diffController = controller as? DiffWindowController {
            return diffController.windowGroupID
        }
        if let browserController = controller as? BrowserWindowController {
            return browserController.windowGroupID
        }
        return nil
    }

    func managedWindowsForTermination() -> [NSWindow] {
        Array(terminalWindows).compactMap(\.window)
            + Array(fileWindows).compactMap(\.window)
            + Array(diffWindows).compactMap(\.window)
            + Array(readerWindows).compactMap(\.window)
            + Array(browserWindows).compactMap(\.window)
    }

    func makeTerminalWindowController(
        tabbingMode: NSWindow.TabbingMode,
        windowGroupID: UUID,
        projectRootURL: URL?
    ) -> TerminalWindowController {
        let controller = TerminalWindowController(
            tabbingMode: tabbingMode,
            windowGroupID: windowGroupID,
            projectRootURL: projectRootURL,
            appCommandSink: commandSink
        )
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            terminalWindows.remove(controller)
            onManagedWindowClosed?()
            onManagedWindowStateChanged?()
        }
        controller.onSelect = { [weak self, weak controller] in
            guard let controller else { return }
            self?.onManagedWindowSelected?(controller.windowGroupID)
        }
        controller.closeDecision = { [weak self] subject in
            self?.closeDecision(subject) ?? .deny
        }
        terminalWindows.insert(controller)
        return controller
    }

    func makeFileWindowController(
        tabbingMode: NSWindow.TabbingMode,
        windowGroupID: UUID,
        projectRootURL: URL?,
        fileURL: URL
    ) -> FileWindowController {
        let controller = FileWindowController(
            tabbingMode: tabbingMode,
            windowGroupID: windowGroupID,
            projectRootURL: projectRootURL,
            fileURL: fileURL,
            editorSessionCache: editorSessionCache,
            appCommandSink: commandSink
        )
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            fileWindows.remove(controller)
            editorSessionCache.removeSession(id: controller.id)
            onManagedWindowClosed?()
            onManagedWindowStateChanged?()
        }
        controller.onSelect = { [weak self, weak controller] in
            guard let controller else { return }
            self?.onManagedWindowSelected?(controller.windowGroupID)
        }
        controller.closeDecision = { [weak self] subject in
            self?.closeDecision(subject) ?? .deny
        }
        controller.onCloseProgressChange = { [weak self] in
            self?.onManagedWindowStateChanged?()
        }
        fileWindows.insert(controller)
        return controller
    }

    func makeReaderWindowController(
        tabbingMode: NSWindow.TabbingMode,
        windowGroupID: UUID,
        projectRootURL: URL?,
        fileURL: URL
    ) -> ReaderWindowController {
        let controller = ReaderWindowController(
            tabbingMode: tabbingMode,
            windowGroupID: windowGroupID,
            projectRootURL: projectRootURL,
            fileURL: fileURL,
            editorSessionCache: editorSessionCache,
            appCommandSink: commandSink
        )
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            readerWindows.remove(controller)
            editorSessionCache.removeSession(id: controller.id)
            onManagedWindowClosed?()
            onManagedWindowStateChanged?()
        }
        controller.onSelect = { [weak self, weak controller] in
            guard let controller else { return }
            self?.onManagedWindowSelected?(controller.windowGroupID)
        }
        controller.closeDecision = { [weak self] subject in
            self?.closeDecision(subject) ?? .deny
        }
        controller.onCloseProgressChange = { [weak self] in
            self?.onManagedWindowStateChanged?()
        }
        readerWindows.insert(controller)
        return controller
    }

    func makeDiffWindowController(
        tabbingMode: NSWindow.TabbingMode,
        windowGroupID: UUID,
        projectRootURL: URL?,
        change: GitFileChange
    ) -> DiffWindowController {
        let controller = DiffWindowController(
            tabbingMode: tabbingMode,
            windowGroupID: windowGroupID,
            projectRootURL: projectRootURL,
            change: change,
            appCommandSink: commandSink
        )
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            diffWindows.remove(controller)
            onManagedWindowClosed?()
            onManagedWindowStateChanged?()
        }
        controller.onSelect = { [weak self, weak controller] in
            guard let controller else { return }
            self?.onManagedWindowSelected?(controller.windowGroupID)
        }
        controller.closeDecision = { [weak self] subject in
            self?.closeDecision(subject) ?? .deny
        }
        diffWindows.insert(controller)
        return controller
    }

    func makeBrowserWindowController(
        tabbingMode: NSWindow.TabbingMode,
        windowGroupID: UUID,
        projectRootURL: URL?,
        url: URL,
        fileReadAccessURL: URL?
    ) -> BrowserWindowController {
        let controller = BrowserWindowController(
            tabbingMode: tabbingMode,
            windowGroupID: windowGroupID,
            projectRootURL: projectRootURL,
            url: url,
            fileReadAccessURL: fileReadAccessURL,
            browserSessionCache: browserSessionCache,
            appCommandSink: commandSink
        )
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            browserSessionCache.removeSession(id: controller.id)
            browserWindows.remove(controller)
            onManagedWindowClosed?()
            onManagedWindowStateChanged?()
        }
        controller.onSelect = { [weak self, weak controller] in
            guard let controller else { return }
            self?.onManagedWindowSelected?(controller.windowGroupID)
        }
        controller.closeDecision = { [weak self] subject in
            self?.closeDecision(subject) ?? .deny
        }
        browserWindows.insert(controller)
        return controller
    }
}
