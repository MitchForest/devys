import Foundation
public import TerminalCore
public import TerminalVT

private let metadataSnapshotCadenceNanoseconds: UInt64 = 500_000_000

struct TerminalMetadataObservation: Sendable {
    var title: String
    var workingDirectory: String?
    var activity: TerminalActivity
}

@MainActor
extension TerminalSurfaceRuntime {
    public func update(callbacks: TerminalSurfaceCallbacks) {
        self.callbacks = callbacks
    }

    public func updateLatestSnapshot(_ snapshot: TerminalSnapshot) {
        latestSnapshot = snapshot
    }

    public func terminate() {
        isTerminated = true
        startupTask?.cancel()
        startupTask = nil
        outputTask?.cancel()
        outputTask = nil
        viewportTask?.cancel()
        viewportTask = nil
        metadataTask?.cancel()
        metadataTask = nil
        scrollTask?.cancel()
        scrollTask = nil
        pendingMetadataObservation = nil
        resizeCoordinator = TerminalSurfaceResizeCoordinator()
        pendingScrollDelta = 0
        latestScrollEvent = nil

        guard let handle else {
            callbacks.statusChanged(.exited)
            return
        }

        self.handle = nil
        callbacks.statusChanged(.exited)
        Task(priority: .userInitiated) { [pty] in
            await pty.terminate(handle)
        }
    }

    public func startIfNeeded() {
        guard !isTerminated else { return }
        guard startupTask == nil else { return }
        guard handle == nil, vt == nil else { return }
        guard resizeCoordinator.hasMeasuredViewport else { return }
        let initialViewportSize = resizeCoordinator.latestViewportSize
        let appearance = currentAppearance
        callbacks.statusChanged(.starting)
        startupTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            await self?.performStart(
                initialViewportSize: initialViewportSize,
                appearance: appearance
            )
        }
    }

    private func performStart(
        initialViewportSize: TerminalViewportSize,
        appearance: TerminalAppearance
    ) async {
        defer {
            startupTask = nil
        }
        guard !Task.isCancelled, !isTerminated else { return }
        do {
            let runtime = try TerminalVTRuntime(
                cols: initialViewportSize.cols,
                rows: initialViewportSize.rows,
                appearance: appearance
            )
            let handle = try await pty.create(descriptor: launchDescriptor, size: initialViewportSize)
            let events = try await pty.attach(handle)
            guard !Task.isCancelled, !isTerminated else {
                await pty.terminate(handle)
                return
            }
            self.vt = runtime
            self.handle = handle
            resizeCoordinator.markInitialPTYSizeApplied(initialViewportSize)
            callbacks.statusChanged(.running)
            outputTask = Task(priority: .userInitiated) { [weak self] in
                await self?.consume(events: events, runtime: runtime, handle: handle)
            }
            scheduleViewportProcessingIfNeeded()
        } catch {
            guard !Task.isCancelled, !isTerminated else { return }
            callbacks.statusChanged(.failed)
        }
    }

    public func requestFocus() {
        focusGeneration &+= 1
    }

    public func updateAppearance(_ appearance: TerminalAppearance) {
        guard currentAppearance != appearance else { return }
        currentAppearance = appearance
        guard let vt else { return }
        Task(priority: .userInitiated) { [weak self] in
            let update = await vt.updateAppearance(appearance)
            await MainActor.run {
                self?.apply(update: update)
            }
        }
    }

    public func sendInput(_ command: TerminalSurfaceInputCommand) {
        guard let vt else { return }
        Task(priority: .userInitiated) { [weak self] in
            let data: Data
            switch command {
            case .key(let event):
                data = await vt.inputData(for: event)
            case .paste(let text):
                guard !text.isEmpty else { return }
                data = await vt.pasteData(for: text)
            case .submitText(let text):
                guard !text.isEmpty else { return }
                let pastedText = await vt.pasteData(for: text)
                let enter = await vt.inputData(for: GhosttyTerminalKeyEvent(key: .enter))
                data = pastedText + enter
            }
            await self?.sendAsync(data)
        }
    }

    public func scroll(_ event: TerminalSurfaceScrollEvent) {
        guard event.lines != 0 else { return }
        pendingScrollDelta += event.lines
        latestScrollEvent = event
        scheduleScrollProcessingIfNeeded()
    }

    private func scheduleScrollProcessingIfNeeded() {
        guard scrollTask == nil else { return }
        MetalSurfaceDiagnostics.recordScrollTaskStarted(surface: "terminal")
        scrollTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            await self.processPendingScroll()
        }
    }

    private func processPendingScroll() async {
        while !Task.isCancelled {
            guard pendingScrollDelta != 0 else {
                scrollTask = nil
                return
            }

            do {
                try await Task.sleep(nanoseconds: TerminalSurfaceTiming.scrollProcessingCoalescingNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let delta = pendingScrollDelta
            pendingScrollDelta = 0
            await apply(scrollDelta: delta, event: latestScrollEvent)
        }
    }

    private func apply(scrollDelta delta: Int, event: TerminalSurfaceScrollEvent?) async {
        guard delta != 0, let vt else { return }
        if surfaceUpdate.surfaceState.altScreenMode,
           surfaceUpdate.surfaceState.mouseAlternateScrollMode,
           surfaceUpdate.surfaceState.mouseTrackingActive == false {
            await sendArrowScroll(delta, runtime: vt)
            MetalSurfaceDiagnostics.recordScrollRoutedToPTY(surface: "terminal")
            MetalSurfaceDiagnostics.recordScrollApplication(delta, surface: "terminal")
            return
        }

        if surfaceUpdate.surfaceState.mouseTrackingActive {
            await sendMouseWheelScroll(delta, event: event, runtime: vt)
            MetalSurfaceDiagnostics.recordScrollRoutedToPTY(surface: "terminal")
            MetalSurfaceDiagnostics.recordScrollApplication(delta, surface: "terminal")
            return
        }

        let update = await vt.scrollViewport(by: delta)
        apply(update: update)
        MetalSurfaceDiagnostics.recordScrollRoutedToViewport(surface: "terminal")
        MetalSurfaceDiagnostics.recordScrollApplication(delta, surface: "terminal")
    }

    private func sendArrowScroll(_ delta: Int, runtime: TerminalVTRuntime) async {
        let key: GhosttyTerminalKey = delta > 0 ? .arrowUp : .arrowDown
        for _ in 0..<abs(delta) {
            let data = await runtime.inputData(for: GhosttyTerminalKeyEvent(key: key))
            await sendAsync(data)
        }
    }

    private func sendMouseWheelScroll(
        _ delta: Int,
        event: TerminalSurfaceScrollEvent?,
        runtime: TerminalVTRuntime
    ) async {
        guard let event else { return }
        let direction: GhosttyTerminalMouseWheelDirection = delta > 0 ? .down : .up
        for _ in 0..<abs(delta) {
            let data = await runtime.mouseWheelData(for: event.mouseWheelEvent(direction: direction))
            guard !data.isEmpty else { continue }
            await sendAsync(data)
        }
    }

    public func selectionBegin(row: Int, col: Int) {
        let range = TerminalSelectionRange(
            start: TerminalSelectionPoint(row: row, col: col),
            end: TerminalSelectionPoint(row: row, col: col)
        )
        renderSession.applySelection(range)
        callbacks.selectionChanged(renderSession.selectionText())
    }

    public func selectionMove(row: Int, col: Int) {
        guard let current = renderSession.selectionRange else {
            selectionBegin(row: row, col: col)
            return
        }
        let range = TerminalSelectionRange(
            start: current.start,
            end: TerminalSelectionPoint(row: row, col: col)
        )
        renderSession.applySelection(range)
        callbacks.selectionChanged(renderSession.selectionText())
    }

    public func selectionEnd() {
        callbacks.selectionChanged(renderSession.selectionText())
    }

    public func selectWord(row: Int, col: Int) {
        let range = renderSession.wordSelection(atRow: row, col: col)
        renderSession.applySelection(range)
        callbacks.selectionChanged(renderSession.selectionText())
    }

    public func clearSelection() {
        renderSession.applySelection(nil)
        callbacks.selectionChanged(nil)
    }

    public func selectionText() -> String? {
        renderSession.selectionText()
    }

    public func latestTextRange(matching query: TerminalTextQuery) async -> TerminalTextRangeLookupResult {
        guard query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .unavailable(.emptyQuery)
        }
        guard surfaceUpdate.surfaceState.altScreenMode == false else {
            return .unavailable(.alternateScreen)
        }
        guard let vt else {
            return .unavailable(.runtimeNotReady)
        }
        let lines = await vt.screenLines()
        return TerminalTextRangeMatcher.latestRange(
            matching: query,
            in: lines,
            snapshotRevision: renderSession.renderRevision
        )
    }

    public func projectTextRanges(_ ranges: [TerminalTextRange]) -> TerminalTextRangeProjectionSnapshot {
        TerminalTextRangeProjectionResolver.snapshot(
            for: ranges,
            surfaceState: surfaceUpdate.surfaceState,
            snapshotRevision: renderSession.renderRevision,
            pixelSize: latestSurfacePixelSize,
            contentPadding: TerminalSurfaceDefaults.contentPadding
        )
    }

    public func showSearch() {
        guard searchState.isPresented == false else { return }
        searchState.isPresented = true
    }

    public func updateSearchQuery(_ query: String) {
        searchGeneration &+= 1
        searchState.isPresented = true
        searchState.query = query
        recomputeSearch()
    }

    public func selectNextSearchMatch() {
        guard !searchMatches.isEmpty else { return }
        let current = searchState.activeMatchIndex ?? -1
        searchState.activeMatchIndex = (current + 1) % searchMatches.count
        scrollActiveSearchMatchToVisible()
    }

    public func selectPreviousSearchMatch() {
        guard !searchMatches.isEmpty else { return }
        let current = searchState.activeMatchIndex ?? 0
        searchState.activeMatchIndex = (current - 1 + searchMatches.count) % searchMatches.count
        scrollActiveSearchMatchToVisible()
    }

    public func closeSearch() {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        searchMatches = []
        searchTotalRows = nil
        searchState = TerminalSearchState()
        renderSession.applySearch(ranges: [], activeRange: nil)
    }

    public func setSurfaceSize(_ pixelSize: TerminalSurfacePixelSize) {
        latestSurfacePixelSize = pixelSize
        let transaction = TerminalSurfaceResizeTransaction(pixelSize: pixelSize)
        guard resizeCoordinator.observe(transaction) else { return }
        startIfNeeded()
        scheduleViewportProcessingIfNeeded()
    }

    private func scheduleViewportProcessingIfNeeded() {
        guard viewportTask == nil else { return }
        viewportTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            await self.processPendingViewport()
        }
    }

    private func processPendingViewport() async {
        while !Task.isCancelled {
            guard vt != nil, handle != nil else {
                viewportTask = nil
                return
            }
            guard let transaction = resizeCoordinator.takePendingTransaction() else {
                viewportTask = nil
                return
            }

            do {
                try await Task.sleep(nanoseconds: resizeProcessingDelay(for: transaction))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            if resizeCoordinator.hasPendingTransaction {
                continue
            }

            let application = resizeCoordinator.application(for: transaction)
            guard application.shouldResizeVT || application.shouldResizePTY else { continue }
            await apply(resizeApplication: application)
        }
    }

    private func resizeProcessingDelay(for _: TerminalSurfaceResizeTransaction) -> UInt64 {
        TerminalSurfaceTiming.viewportResizeCoalescingNanoseconds
    }

    private func apply(resizeApplication application: TerminalSurfaceResizeApplication) async {
        guard let vt, let handle else { return }
        if application.shouldResizeVT {
            let transaction = application.transaction
            let update = await vt.resize(
                cols: transaction.size.cols,
                rows: transaction.size.rows,
                cellWidthPx: transaction.cellWidthPx,
                cellHeightPx: transaction.cellHeightPx
            )
            apply(update: update)
        }

        var ptyResizeSucceeded = false
        if application.shouldResizePTY {
            do {
                try await pty.resize(handle, size: application.transaction.size)
                ptyResizeSucceeded = true
            } catch {
                ptyResizeSucceeded = false
            }
        }

        resizeCoordinator.markApplied(application, ptyResizeSucceeded: ptyResizeSucceeded)
        if application.shouldResizeVT || ptyResizeSucceeded {
            MetalSurfaceDiagnostics.recordViewportApplied(surface: "terminal")
        }
    }

    private func sendAsync(_ data: Data) async {
        guard let handle else { return }
        do {
            try await pty.send(data, to: handle)
        } catch {
            callbacks.statusChanged(.failed)
        }
    }

    private func consume(
        events: AsyncStream<TerminalPTYEvent>,
        runtime: TerminalVTRuntime,
        handle: TerminalSessionHandle
    ) async {
        for await event in events {
            switch event {
            case .output(let data):
                let result = await runtime.write(data)
                for outboundWrite in result.outboundWrites {
                    do {
                        try await pty.send(outboundWrite, to: handle)
                    } catch {
                        await MainActor.run {
                            self.callbacks.statusChanged(.failed)
                        }
                    }
                }
                await MainActor.run {
                    self.apply(update: result.surfaceUpdate)
                }
                scheduleMetadataSnapshot(
                    TerminalMetadataObservation(
                        title: result.title,
                        workingDirectory: result.workingDirectory,
                        activity: result.bellCountDelta > 0 ? .bell : .output
                    ),
                    handle: handle
                )
                if result.bellCountDelta > 0 {
                    callbacks.bell()
                }
            case .exited(let exit):
                callbacks.statusChanged(.exited)
                let processSnapshot = exitProcessSnapshot(await pty.processSnapshot(handle))
                let snapshot = TerminalSnapshot(
                    terminalID: terminalID,
                    shellProcessID: processSnapshot.shellProcessID,
                    foregroundProcess: processSnapshot.foregroundProcess,
                    processTree: processSnapshot.processTree,
                    listeningPorts: processSnapshot.listeningPorts,
                    exit: exit,
                    activity: .idle
                )
                updateLatestSnapshot(snapshot)
                callbacks.snapshotChanged(snapshot)
                callbacks.exited(exit)
            }
        }
    }

    private func scheduleMetadataSnapshot(
        _ observation: TerminalMetadataObservation,
        handle: TerminalSessionHandle
    ) {
        pendingMetadataObservation = observation
        guard metadataTask == nil else { return }
        metadataTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: metadataSnapshotCadenceNanoseconds)
                } catch {
                    self.metadataTask = nil
                    return
                }
                guard let observation = self.pendingMetadataObservation else {
                    self.metadataTask = nil
                    return
                }
                self.pendingMetadataObservation = nil
                await self.publishMetadataSnapshot(observation, handle: handle)
            }
        }
    }

    private func publishMetadataSnapshot(
        _ observation: TerminalMetadataObservation,
        handle: TerminalSessionHandle
    ) async {
        let probedWorkingDirectory = await pty.currentWorkingDirectory(handle)?.path
        let currentDirectory = observation.workingDirectory ?? probedWorkingDirectory
        let processSnapshot = await pty.processSnapshot(handle)
        let snapshot = TerminalSnapshot(
            terminalID: terminalID,
            currentDirectoryPath: currentDirectory,
            title: observation.title,
            shellProcessID: processSnapshot.shellProcessID,
            foregroundProcess: processSnapshot.foregroundProcess,
            processTree: processSnapshot.processTree,
            listeningPorts: processSnapshot.listeningPorts,
            activity: observation.activity
        )
        guard shouldPublishMetadataSnapshot(snapshot) else { return }
        callbacks.titleChanged(observation.title)
        callbacks.currentDirectoryChanged(currentDirectory)
        updateLatestSnapshot(snapshot)
        callbacks.snapshotChanged(snapshot)
    }

    private func shouldPublishMetadataSnapshot(_ snapshot: TerminalSnapshot) -> Bool {
        guard let latestSnapshot else { return true }
        return latestSnapshot.currentDirectoryPath != snapshot.currentDirectoryPath
            || latestSnapshot.title != snapshot.title
            || latestSnapshot.shellProcessID != snapshot.shellProcessID
            || latestSnapshot.foregroundProcess != snapshot.foregroundProcess
            || latestSnapshot.processTree != snapshot.processTree
            || latestSnapshot.listeningPorts != snapshot.listeningPorts
            || latestSnapshot.exit != snapshot.exit
            || latestSnapshot.activity != snapshot.activity
    }

    private func apply(update: TerminalSurfaceUpdate) {
        surfaceUpdate = update
        renderSession.apply(update: update)
        if searchState.query.isEmpty == false {
            recomputeSearch()
        }
    }

    private func exitProcessSnapshot(_ processSnapshot: TerminalProcessSnapshot) -> TerminalProcessSnapshot {
        guard processSnapshot.shellProcessID == nil,
              processSnapshot.foregroundProcess == nil,
              processSnapshot.processTree.isEmpty,
              processSnapshot.listeningPorts.isEmpty,
              let latestSnapshot else {
            return processSnapshot
        }
        return TerminalProcessSnapshot(
            shellProcessID: latestSnapshot.shellProcessID,
            foregroundProcess: latestSnapshot.foregroundProcess,
            processTree: latestSnapshot.processTree,
            listeningPorts: latestSnapshot.listeningPorts
        )
    }
}

private extension TerminalSurfaceRuntime {
    func recomputeSearch() {
        let query = searchState.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchMatches = []
            searchTotalRows = nil
            searchState.matchCount = 0
            searchState.activeMatchIndex = nil
            renderSession.applySearch(ranges: [], activeRange: nil)
            return
        }

        guard let vt else {
            applySearchMatches(
                renderSession.frameProjection.searchMatches(matching: query),
                totalRows: renderSession.surfaceState.rows
            )
            return
        }

        let generation = searchGeneration
        searchTask?.cancel()
        searchTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            let lines = await vt.screenLines()
            guard let self,
                  !Task.isCancelled,
                  generation == self.searchGeneration,
                  self.searchState.query.trimmingCharacters(in: .whitespacesAndNewlines) == query
            else {
                return
            }
            self.applySearchMatches(
                lines.searchMatches(matching: query),
                totalRows: lines.count
            )
        }
    }

    func applySearchMatches(
        _ matches: [TerminalSearchMatch],
        totalRows: Int
    ) {
        searchMatches = matches
        searchTotalRows = totalRows
        searchState.matchCount = matches.count
        if matches.isEmpty {
            searchState.activeMatchIndex = nil
        } else if let active = searchState.activeMatchIndex,
                  matches.indices.contains(active) {
            searchState.activeMatchIndex = active
        } else {
            searchState.activeMatchIndex = 0
        }
        scrollActiveSearchMatchToVisible()
    }

    func scrollActiveSearchMatchToVisible() {
        guard let activeIndex = searchState.activeMatchIndex,
              searchMatches.indices.contains(activeIndex)
        else {
            applyVisibleSearchRanges()
            return
        }
        guard let vt,
              let totalRows = searchTotalRows
        else {
            applyVisibleSearchRanges()
            return
        }

        let match = searchMatches[activeIndex]
        let surfaceState = surfaceUpdate.surfaceState
        let visibleTopRow = visibleTopRow(totalRows: totalRows, surfaceState: surfaceState)
        if match.selectionRange(visibleTopRow: visibleTopRow, visibleRowCount: surfaceState.rows) != nil {
            applyVisibleSearchRanges()
            return
        }

        let desiredOffset = min(
            max(0, totalRows - surfaceState.rows - match.row),
            surfaceState.scrollbackRows
        )
        let delta = surfaceState.viewportOffset - desiredOffset
        guard delta != 0 else {
            applyVisibleSearchRanges()
            return
        }

        Task(priority: .userInitiated) { @MainActor [weak self] in
            let update = await vt.scrollViewport(by: delta)
            guard let self else { return }
            self.apply(update: update)
            self.applyVisibleSearchRanges()
        }
    }

    func applyVisibleSearchRanges() {
        guard let totalRows = searchTotalRows else {
            let ranges = searchMatches.map {
                TerminalSelectionRange(
                    start: TerminalSelectionPoint(row: $0.row, col: $0.startCol),
                    end: TerminalSelectionPoint(row: $0.row, col: $0.endCol)
                )
            }
            let activeRange = searchState.activeMatchIndex.flatMap { index in
                ranges.indices.contains(index) ? ranges[index] : nil
            }
            renderSession.applySearch(ranges: ranges, activeRange: activeRange)
            return
        }

        let surfaceState = surfaceUpdate.surfaceState
        let topRow = visibleTopRow(totalRows: totalRows, surfaceState: surfaceState)
        let activeMatch = searchState.activeMatchIndex.flatMap { index in
            searchMatches.indices.contains(index) ? searchMatches[index] : nil
        }
        let ranges = searchMatches.compactMap {
            $0.selectionRange(visibleTopRow: topRow, visibleRowCount: surfaceState.rows)
        }
        let activeRange = activeMatch?.selectionRange(
            visibleTopRow: topRow,
            visibleRowCount: surfaceState.rows
        )
        renderSession.applySearch(ranges: ranges, activeRange: activeRange)
    }

    func visibleTopRow(
        totalRows: Int,
        surfaceState: TerminalSurfaceState
    ) -> Int {
        max(0, totalRows - surfaceState.rows - surfaceState.viewportOffset)
    }
}

private extension TerminalFrameProjection {
    func searchMatches(matching query: String) -> [TerminalSearchMatch] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }

        var ranges: [TerminalSearchMatch] = []
        for row in rowsByIndex {
            let cells = row.cells.filter(\.isRenderable)
            let haystack = cells.map(\.normalizedGrapheme).joined().lowercased()
            ranges.append(contentsOf: terminalSearchMatches(
                row: row.index,
                haystack: haystack,
                needle: needle
            ) { offset in
                cells.indices.contains(offset) ? cells[offset].column : nil
            })
        }
        return ranges
    }
}

private extension Array where Element == GhosttyTerminalScreenLine {
    func searchMatches(matching query: String) -> [TerminalSearchMatch] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }

        var ranges: [TerminalSearchMatch] = []
        for line in self {
            let haystack = line.text.lowercased()
            ranges.append(contentsOf: terminalSearchMatches(
                row: line.row,
                haystack: haystack,
                needle: needle
            ) { $0 })
        }
        return ranges
    }
}

private func terminalSearchMatches(
    row: Int,
    haystack: String,
    needle: String,
    column: (Int) -> Int?
) -> [TerminalSearchMatch] {
    var ranges: [TerminalSearchMatch] = []
    var searchStart = haystack.startIndex

    while searchStart < haystack.endIndex,
          let match = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
        let startOffset = haystack.distance(from: haystack.startIndex, to: match.lowerBound)
        let endOffset = max(
            startOffset,
            haystack.distance(from: match.lowerBound, to: match.upperBound) + startOffset - 1
        )
        guard let startCol = column(startOffset),
              let endCol = column(endOffset)
        else {
            searchStart = match.upperBound
            continue
        }
        ranges.append(TerminalSearchMatch(
            row: row,
            startCol: startCol,
            endCol: endCol
        ))
        searchStart = match.upperBound
    }

    return ranges
}
