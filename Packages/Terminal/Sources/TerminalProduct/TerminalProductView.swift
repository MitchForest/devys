import Foundation
import SwiftUI
import TerminalComposer
import TerminalHost
import TerminalVT
import UI

#if os(macOS)
import AppKit
#endif

public enum TerminalProductComposerPresentation: Sendable {
    case docked
    case edgeDrawer
}

public struct TerminalProductView: View {
    @StateObject private var model: TerminalProductModel
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var isComposerTransientlyVisible = false
    @State private var isComposerHovering = false
    @State private var composerHideTask: Task<Void, Never>?
    private let commandSink: TerminalProductCommandSink?
    private let composerPresentation: TerminalProductComposerPresentation
    private let externalComposerVisibility: Binding<Bool>?
    private let onCloseRiskChange: @MainActor (TerminalProductCloseRisk?) -> Void

    public init(
        commandSink: TerminalProductCommandSink? = nil,
        workingDirectory: URL? = nil,
        composerPresentation: TerminalProductComposerPresentation = .docked,
        isComposerVisible: Binding<Bool>? = nil,
        onWorkingDirectoryChange: @escaping @MainActor (URL) -> Void = { _ in },
        onCloseRiskChange: @escaping @MainActor (TerminalProductCloseRisk?) -> Void = { _ in }
    ) {
        _model = StateObject(
            wrappedValue: TerminalProductModel(
                workingDirectory: workingDirectory,
                onWorkingDirectoryChange: onWorkingDirectoryChange
            )
        )
        self.commandSink = commandSink
        self.composerPresentation = composerPresentation
        self.externalComposerVisibility = isComposerVisible
        self.onCloseRiskChange = onCloseRiskChange
    }

    public var body: some View {
        let theme = DevysThemeRegistry.theme(for: .system, systemColorScheme: systemColorScheme)

        ZStack {
            terminalContent
            composerEdgeOverlay
        }
        .environment(\.theme, theme)
        .background(
            TerminalWindowChrome(
                title: model.windowTitle,
                agentStatus: model.windowAgentStatus,
                theme: theme
            ) { isFocused in
                model.setWindowFocused(isFocused)
            }
        )
        .onChange(of: systemColorScheme) { _, _ in
            model.applyTheme(theme)
        }
        .onChange(of: model.closeRisk, initial: true) { _, closeRisk in
            onCloseRiskChange(closeRisk)
        }
        .task {
            model.applyTheme(theme)
            model.focusTerminal()
        }
        .onAppear {
            commandSink?.install(
                focusComposer: {
                    revealComposer(focus: true)
                },
                pasteIntoComposer: {
                    revealComposer(focus: true)
                    model.pasteIntoComposer()
                },
                captureSelectionIntoComposer: {
                    revealComposer(focus: true)
                    model.captureSelectionIntoComposer()
                }
            )
        }
        .onDisappear {
            composerHideTask?.cancel()
            commandSink?.clear()
            model.terminate()
        }
        .onExitCommand {
            if shouldShowTransientComposer {
                hideComposer()
            } else {
                model.focusTerminal()
            }
        }
    }

    private var terminalContent: some View {
        VStack(spacing: 0) {
            terminalView
            if composerPresentation == .docked {
                composerDock
            }
        }
    }

    @ViewBuilder
    private var composerEdgeOverlay: some View {
        if composerPresentation == .edgeDrawer {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                if shouldShowTransientComposer {
                    composerCapsule
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onHover { isHovering in
                            isComposerHovering = isHovering
                            if isHovering {
                                revealComposer(focus: false)
                            } else {
                                scheduleComposerHide()
                            }
                        }
                }

                composerHoverStrip
            }
            .animation(Animations.micro, value: shouldShowTransientComposer)
        }
    }

    private var shouldShowTransientComposer: Bool {
        composerPresentation == .edgeDrawer
            && composerIsVisible
    }

    private var composerHoverStrip: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 12)
            .contentShape(Rectangle())
            .onHover { isHovering in
                isComposerHovering = isHovering
                if isHovering {
                    revealComposer(focus: false)
                } else {
                    scheduleComposerHide()
                }
            }
    }

    /// A single capsule above the terminal. The composer view supplies its own
    /// rounded outline and focus ring, so the wrapper only adds outer spacing.
    private var composerCapsule: some View {
        composerDock
    }

    private var composerDock: some View {
        TerminalComposerView(
            model: model.composer,
            serializationStyle: model.composerSerializationStyle,
            smartPasteSettings: TerminalComposerSmartPasteSettings(),
            dictationKey: .function,
            onSubmit: { submission in
                model.submitComposerSubmission(submission)
            },
            onTerminalFocusRequest: {
                model.focusTerminal()
            }
        )
    }

    private var terminalView: some View {
        TerminalView(
            surfaceState: model.surfaceState,
            frameProjection: model.frameProjection,
            appearance: model.appearance,
            fontSize: 13,
            focusRequestID: model.focusRequestID,
            onTap: {
                focusTerminalAndHideTransientComposer()
            },
            onSelectionBegin: { row, col in
                model.beginSelection(row: row, col: col)
            },
            onSelectionMove: { row, col in
                model.updateSelection(row: row, col: col)
            },
            onSelectionEnd: {
                model.finishSelection()
            },
            onSelectWord: { row, col in
                model.selectWord(row: row, col: col)
            },
            onClearSelection: {
                model.clearSelection()
            },
            onScroll: { lines in
                model.scrollViewport(lines: lines)
            },
            onViewportSizeChange: { _, cols, rows, cellWidthPx, cellHeightPx in
                model.updateViewport(
                    cols: cols,
                    rows: rows,
                    cellWidthPx: cellWidthPx,
                    cellHeightPx: cellHeightPx
                )
            },
            onSendText: { text in
                model.sendText(text)
            },
            onSendSpecialKey: { key in
                model.sendSpecialKey(key)
            },
            onSendControlCharacter: { character in
                model.sendControlCharacter(character)
            },
            onSendAltText: { text in
                model.sendAltText(text)
            },
            onPasteText: { text in
                model.pasteText(text)
            },
            selectionTextProvider: {
                model.selectionText()
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func revealComposer(focus: Bool) {
        guard composerPresentation == .edgeDrawer else { return }
        composerHideTask?.cancel()
        withAnimation(Animations.micro) {
            setComposerVisible(true)
        }
        if focus {
            model.focusComposer()
        }
    }

    private func hideComposer() {
        guard composerPresentation == .edgeDrawer else { return }
        composerHideTask?.cancel()
        withAnimation(Animations.micro) {
            setComposerVisible(false)
        }
        model.focusTerminal()
    }

    private func scheduleComposerHide() {
        guard composerPresentation == .edgeDrawer else { return }
        composerHideTask?.cancel()
        composerHideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !isComposerHovering, !model.composer.isFocused else { return }
            withAnimation(Animations.micro) {
                setComposerVisible(false)
            }
        }
    }

    private func focusTerminalAndHideTransientComposer() {
        model.focusTerminal()
        guard composerPresentation == .edgeDrawer else { return }
        withAnimation(Animations.micro) {
            setComposerVisible(false)
        }
    }

    private var composerIsVisible: Bool {
        externalComposerVisibility?.wrappedValue ?? isComposerTransientlyVisible
    }

    private func setComposerVisible(_ isVisible: Bool) {
        if let externalComposerVisibility {
            externalComposerVisibility.wrappedValue = isVisible
        } else {
            isComposerTransientlyVisible = isVisible
        }
    }
}

struct TerminalProductPlaceholderView: View {
    init() {}

    var body: some View {
        TerminalProductView()
    }
}

@MainActor
final class TerminalProductModel: ObservableObject {
    @Published var surfaceState = TerminalSurfaceState(cols: 1, rows: 1)
    @Published var frameProjection = TerminalFrameProjection.empty()
    @Published var appearance = TerminalProductModel.defaultTerminalAppearance
    @Published var focusRequestID = 0
    @Published var windowTitle = TerminalProductModel.defaultWindowTitle()
    @Published var agentContext = TerminalAgentContext()
    @Published var closeRisk: TerminalProductCloseRisk?

    let composer = TerminalComposerModel()
    let terminalTargetID = TerminalTargetID()
    let agentRegistry: TerminalAgentRegistry
    let foregroundProbeInterval: Duration
    let workingDirectory: URL
    private let onWorkingDirectoryChange: @MainActor (URL) -> Void
    let host = TerminalHostClient()
    private let projectionBuilder = TerminalProjectionBuilder()
    private var runtime: TerminalVTRuntime?
    var handle: TerminalSessionHandle?
    var currentTerminalTitle: String?
    var currentForegroundProcess: TerminalForegroundProcess?
    private var currentWorkingDirectoryBasename: String
    private var currentWorkingDirectoryURL: URL
    private var attachTask: Task<Void, Never>?
    private var viewportTask: Task<Void, Never>?
    private var pendingViewport: TerminalViewport?
    var foregroundProbeTask: Task<Void, Never>?
    var lastAgentOutputAt: Date?
    let agentWorkingQuietInterval: TimeInterval = 1.5
    private var selectionAnchor: TerminalSelectionPoint?
    private var lastViewport = TerminalViewport(cols: 1, rows: 1, cellWidthPx: 1, cellHeightPx: 1)
    var isTerminalWindowFocused = true
    var hasTerminalExited = false

    var currentSessionHandle: TerminalSessionHandle? { handle }

    var composerSerializationStyle: TerminalComposerSerializationStyle {
        agentContext.serializationStyle
    }

    var windowAgentStatus: TerminalWindowAgentStatus? {
        agentContext.windowStatus
    }

    deinit {
        attachTask?.cancel()
        viewportTask?.cancel()
        foregroundProbeTask?.cancel()
    }

    init(
        agentRegistry: TerminalAgentRegistry = .default,
        foregroundProbeInterval: Duration = .milliseconds(500),
        workingDirectory: URL? = nil,
        onWorkingDirectoryChange: @escaping @MainActor (URL) -> Void = { _ in }
    ) {
        self.agentRegistry = agentRegistry
        self.foregroundProbeInterval = foregroundProbeInterval
        self.workingDirectory = (workingDirectory ?? Self.defaultWorkingDirectoryURL()).standardizedFileURL
        self.onWorkingDirectoryChange = onWorkingDirectoryChange
        currentWorkingDirectoryBasename = Self.workingDirectoryBasename(
            for: self.workingDirectory
        )
        currentWorkingDirectoryURL = self.workingDirectory
        windowTitle = currentWorkingDirectoryBasename
        composer.registerTarget(
            id: terminalTargetID,
            metadata: TerminalComposerTargetMetadata(
                cwdBasename: currentWorkingDirectoryBasename
            ),
            isActive: true
        )
        composer.setVisibleTargetIDs([terminalTargetID])
        onWorkingDirectoryChange(self.workingDirectory)
    }

    func focusTerminal() {
        activateTerminalTarget()
        defocusComposerForTerminal()
        focusRequestID += 1
    }

    func focusComposer() {
        guard !hasTerminalExited else { return }
        activateTerminalTarget()
        _ = composer.commandL()
    }

    private func defocusComposerForTerminal() {
        guard composer.isFocused else { return }
        if composer.escape() != .terminal {
            _ = composer.escape()
        }
    }

    func pasteIntoComposer() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            composer.attachFileURLs(urls)
            return
        }
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            composer.addChip(.screenshot())
            return
        }
        if let text = pasteboard.string(forType: .string) {
            _ = composer.ingestPaste(
                text,
                settings: TerminalComposerSmartPasteSettings()
            )
        }
        #endif
    }

    func captureSelectionIntoComposer() {
        guard let text = selectionText(),
              composer.captureSelection(text) != nil
        else { return }
        clearSelection()
    }

    func updateViewport(
        cols: Int,
        rows: Int,
        cellWidthPx: Int,
        cellHeightPx: Int
    ) {
        let viewport = TerminalViewport(
            cols: max(1, cols),
            rows: max(1, rows),
            cellWidthPx: max(1, cellWidthPx),
            cellHeightPx: max(1, cellHeightPx)
        )
        guard viewport != lastViewport || handle == nil else { return }
        lastViewport = viewport
        pendingViewport = viewport
        scheduleViewportProcessingIfNeeded()
    }

    private func scheduleViewportProcessingIfNeeded() {
        guard viewportTask == nil else { return }

        viewportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.processPendingViewport()
        }
    }

    private func processPendingViewport() async {
        while !Task.isCancelled {
            guard let viewport = pendingViewport else {
                viewportTask = nil
                return
            }
            pendingViewport = nil

            if runtime != nil {
                try? await Task.sleep(nanoseconds: 25_000_000)
                guard !Task.isCancelled else { return }
                if pendingViewport != nil {
                    continue
                }
            }

            do {
                if runtime == nil {
                    try await start(viewport: viewport)
                } else {
                    try await resize(viewport: viewport)
                }
            } catch {
                // The standalone app intentionally keeps startup failure visible in the terminal
                // state rather than introducing another product surface during Phase 2.
                let message = "devys-terminal: \(error.localizedDescription)\r\n"
                await applyOutput(Data(message.utf8))
            }
        }
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        send(Data(text.utf8))
    }

    func submitComposerSubmission(_ submission: TerminalComposerSubmission) {
        guard submission.targetID == terminalTargetID else { return }
        Task {
            guard let runtime else { return }
            var data = Data(submission.text.utf8)
            data.append(await runtime.specialKeyData(for: .enter, appCursorMode: surfaceState.appCursorMode))
            await sendToHost(data)
        }
    }

    func sendSpecialKey(_ key: TerminalSpecialKey) {
        Task {
            guard let runtime else { return }
            let data = await runtime.specialKeyData(for: key, appCursorMode: surfaceState.appCursorMode)
            send(data)
        }
    }

    func sendControlCharacter(_ character: Character) {
        Task {
            guard let runtime,
                  let data = await runtime.controlCharacter(for: character)
            else { return }
            send(data)
        }
    }

    func sendAltText(_ text: String) {
        guard !text.isEmpty else { return }
        var data = Data([0x1B])
        data.append(contentsOf: text.utf8)
        send(data)
    }

    func pasteText(_ text: String) {
        guard !text.isEmpty else { return }
        Task {
            guard let runtime else { return }
            send(await runtime.pasteData(for: text))
        }
    }

    func scrollViewport(lines: Int) {
        guard lines != 0 else { return }
        Task {
            guard let runtime else { return }
            apply(update: await runtime.scrollViewport(by: lines))
        }
    }

    func beginSelection(row: Int, col: Int) {
        let point = TerminalSelectionPoint(row: row, col: col)
        selectionAnchor = point
        applySelection(TerminalSelectionRange(start: point, end: point))
    }

    func updateSelection(row: Int, col: Int) {
        guard let selectionAnchor else { return }
        applySelection(
            TerminalSelectionRange(
                start: selectionAnchor,
                end: TerminalSelectionPoint(row: row, col: col)
            )
        )
    }

    func finishSelection() {}

    func clearSelection() {
        selectionAnchor = nil
        applySelection(nil)
    }

    func selectWord(row: Int, col: Int) {
        guard let selection = frameProjection.wordSelection(atRow: row, col: col) else { return }
        selectionAnchor = selection.start
        applySelection(selection)
    }

    func selectionText() -> String? {
        frameProjection.text(in: surfaceState.selectionRange)
    }

    func terminate() {
        attachTask?.cancel()
        stopForegroundProbe()
        guard let handle else { return }
        Task {
            await host.terminate(handle)
        }
    }

    func updateAppearance(_ newAppearance: TerminalAppearance) {
        guard appearance != newAppearance else { return }
        appearance = newAppearance
        guard let runtime else { return }
        Task {
            let update = await runtime.updateAppearance(newAppearance)
            await MainActor.run {
                self.apply(update: update)
            }
        }
    }

    private func start(viewport: TerminalViewport) async throws {
        updateTerminalTitle(title: "", workingDirectory: nil)

        let handle = try await host.create(
            profile: .userShell(),
            cwd: workingDirectory,
            env: [:],
            size: TerminalHostSize(cols: viewport.cols, rows: viewport.rows)
        )
        let events = try await host.attach(handle)
        let runtime: TerminalVTRuntime
        do {
            runtime = try TerminalVTRuntime(
                cols: viewport.cols,
                rows: viewport.rows,
                appearance: appearance
            )
        } catch {
            await host.terminate(handle)
            throw error
        }
        self.runtime = runtime
        self.handle = handle
        hasTerminalExited = false
        composer.setVisibleTargetIDs([terminalTargetID])
        composer.activateTarget(terminalTargetID)
        attachTask = Task {
            await consume(events: events)
        }
        startForegroundProbe()
        apply(update: await runtime.resize(
            cols: viewport.cols,
            rows: viewport.rows,
            cellWidthPx: viewport.cellWidthPx,
            cellHeightPx: viewport.cellHeightPx
        ))
    }

    private func resize(viewport: TerminalViewport) async throws {
        guard let runtime else { return }
        if let handle {
            try await host.resize(handle, cols: viewport.cols, rows: viewport.rows)
        }
        apply(update: await runtime.resize(
            cols: viewport.cols,
            rows: viewport.rows,
            cellWidthPx: viewport.cellWidthPx,
            cellHeightPx: viewport.cellHeightPx
        ))
    }

    private func consume(events: AsyncStream<TerminalHostEvent>) async {
        for await event in events {
            switch event {
            case .output(let data):
                await applyOutput(data)
            case .exited:
                markTerminalExited()
                return
            }
        }
    }

    private func applyOutput(_ data: Data) async {
        guard let runtime else { return }
        noteAgentOutput()
        let result = await runtime.write(data)
        apply(update: result.surfaceUpdate)
        updateTerminalTitle(title: result.title, workingDirectory: result.workingDirectory)
        for outboundWrite in result.outboundWrites {
            send(outboundWrite)
        }
    }

    private func send(_ data: Data) {
        guard handle != nil else { return }
        Task {
            await sendToHost(data)
        }
    }

    private func sendToHost(_ data: Data) async {
        guard let handle else { return }
        try? await host.send(data, to: handle)
    }

    func apply(update: TerminalSurfaceUpdate) {
        surfaceState = update.surfaceState
        frameProjection = projectionBuilder.merge(current: frameProjection, update: update.frameProjection)
    }

    private func applySelection(_ selectionRange: TerminalSelectionRange?) {
        surfaceState = surfaceState.withSelection(selectionRange)
        frameProjection = projectionBuilder.applySelection(selectionRange, to: frameProjection)
    }

    func updateTerminalTitle(title: String, workingDirectory: String?) {
        currentTerminalTitle = Self.normalizedTerminalTitle(title)

        let cwdURL = Self.normalizedWorkingDirectoryURL(workingDirectory)
        let cwdName = cwdURL.flatMap { url -> String? in
            let last = url.lastPathComponent
            return last.isEmpty ? nil : last
        }
        if let cwdName, cwdName != currentWorkingDirectoryBasename {
            currentWorkingDirectoryBasename = cwdName
        }
        if let cwdURL, cwdURL != currentWorkingDirectoryURL {
            currentWorkingDirectoryURL = cwdURL
            onWorkingDirectoryChange(cwdURL)
        }
        refreshWindowTitle()
        composer.updateMetadata(
            for: terminalTargetID,
            metadata: TerminalComposerTargetMetadata(cwdBasename: currentWorkingDirectoryBasename)
        )
    }

    func refreshWindowTitle() {
        windowTitle = Self.displayWindowTitle(
            agentName: agentContext.match?.displayName,
            terminalTitle: currentTerminalTitle,
            foregroundProcessName: currentForegroundProcess?.executableName,
            cwdBasename: currentWorkingDirectoryBasename
        )
    }

    static func displayWindowTitle(
        agentName: String?,
        terminalTitle: String?,
        foregroundProcessName: String?,
        cwdBasename: String
    ) -> String {
        let cwd = cwdBasename.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = cwd.isEmpty ? defaultWorkingDirectoryBasename() : cwd

        if let agentName = normalizedTitlePart(agentName) {
            return "\(agentName) - \(folder)"
        }

        if let terminalTitle,
           let title = normalizedTerminalTitle(terminalTitle) {
            return titleContainsFolder(title, folder: folder) ? title : "\(title) - \(folder)"
        }

        if let foregroundProcessName = normalizedForegroundProcessName(foregroundProcessName) {
            return "\(foregroundProcessName) - \(folder)"
        }

        return folder
    }

    static func normalizedTerminalTitle(_ title: String?) -> String? {
        guard let title = normalizedTitlePart(title) else { return nil }
        let normalized = title.lowercased()
        let genericTitles: Set<String> = [
            "terminal",
            "xterm",
            "xterm-ghostty",
        ]
        return genericTitles.contains(normalized) ? nil : title
    }

    private static func normalizedTitlePart(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func titleContainsFolder(_ title: String, folder: String) -> Bool {
        title.range(of: folder, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

}
