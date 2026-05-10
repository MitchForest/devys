// SyntaxController.swift
// Tree-sitter-backed document-owned syntax controller.

// periphery:ignore:all - syntax scheduling surfaces are exercised through runtime callbacks and package tests
import Foundation
import SwiftTreeSitter
import Text

// swiftlint:disable file_length
// swiftlint:disable type_body_length
private let fallbackHighlightForeground = "#d4d4d4"

private func normalizedHighlightLines(_ lines: [String]) -> [String] {
    lines.isEmpty ? [""] : lines
}

private func makeDocumentSnapshot(from lines: [String]) -> DocumentSnapshot {
    TextDocument(content: normalizedHighlightLines(lines).joined(separator: "\n")).snapshot()
}

private struct SyntaxBatchComputationResult: Sendable {
    let version: Int
    let range: Range<Int>
    let lines: [SyntaxHighlightedLine]
    let defaultForeground: String
}

private struct SyntaxWarmCacheEntry: Sendable {
    let snapshot: SyntaxSnapshot
    let defaultForeground: String
}

enum SyntaxWorkPriority: String, Sendable, Equatable {
    case visibleDirty
    case visibleUncovered
    case prefetch
    case dirtyBacklog
    case fillBacklog
}

struct SyntaxWorkItem: Sendable, Equatable {
    let priority: SyntaxWorkPriority
    let range: Range<Int>
}

private actor SyntaxControllerWorker {
    private let language: String
    private let themeName: String
    private let bundlePath: String
    private let maximumTokenizationLineLength: Int

    private var defaultForeground: String = fallbackHighlightForeground
    private var assetsLoaded = false
    private var treeSitterTheme: SyntaxTheme?
    private var treeSitterConfiguration: LanguageConfiguration?
    private var treeSitterRuntime: SyntaxDocumentRuntime?
    private var treeSitterSpanSnapshot: SyntaxSpanSnapshot?

    private var documentSnapshot: DocumentSnapshot
    private var version: Int = 0

    init(
        documentSnapshot: DocumentSnapshot,
        language: String,
        themeName: String,
        bundlePath: String,
        maximumTokenizationLineLength: Int
    ) {
        self.documentSnapshot = documentSnapshot
        self.language = language
        self.themeName = themeName
        self.bundlePath = bundlePath
        self.maximumTokenizationLineLength = max(0, maximumTokenizationLineLength)
    }

    func sync(
        documentSnapshot: DocumentSnapshot,
        update: SyntaxDocumentUpdate?,
        version: Int
    ) async {
        guard version != self.version else { return }

        self.documentSnapshot = documentSnapshot
        self.version = version

        await ensureAssetsLoaded()
        guard let configuration = treeSitterConfiguration,
              let theme = treeSitterTheme else {
            treeSitterRuntime = nil
            treeSitterSpanSnapshot = nil
            defaultForeground = fallbackHighlightForeground
            return
        }

        defaultForeground = theme.defaultForeground

        if treeSitterRuntime == nil {
            treeSitterRuntime = try? SyntaxDocumentRuntime(
                documentSnapshot: documentSnapshot,
                languageConfiguration: configuration
            )
            treeSitterSpanSnapshot = nil
            return
        }

        guard let treeSitterRuntime else { return }

        if let update {
            let parseResult = try? await treeSitterRuntime.reparse(
                oldSnapshot: update.oldSnapshot,
                newSnapshot: update.newSnapshot,
                transaction: update.transaction
            )
            if let parseResult {
                treeSitterSpanSnapshot = treeSitterSpanSnapshot?.removing(
                    lineRanges: parseResult.invalidation.lineRanges
                )
            } else {
                _ = try? await treeSitterRuntime.replaceDocument(with: documentSnapshot)
                treeSitterSpanSnapshot = nil
            }
            return
        }

        let state = await treeSitterRuntime.currentState()
        if state.documentVersion != documentSnapshot.version {
            _ = try? await treeSitterRuntime.replaceDocument(with: documentSnapshot)
            treeSitterSpanSnapshot = nil
        }
    }

    func highlight(
        range: Range<Int>,
        expectedVersion: Int
    ) async -> SyntaxBatchComputationResult? {
        guard expectedVersion == version else { return nil }

        if let delay = await SyntaxControllerTestSupport.configuredArtificialHighlightDelay() {
            try? await Task.sleep(nanoseconds: delay)
            guard expectedVersion == version else { return nil }
        }

        await ensureAssetsLoaded()

        let clamped = clamp(range)
        guard clamped.lowerBound < clamped.upperBound else {
            return batchResult(range: clamped, lines: [], defaultForeground: defaultForeground)
        }

        guard let configuration = treeSitterConfiguration,
              let theme = treeSitterTheme else {
            return plainBatchResult(range: clamped)
        }

        guard let treeSitterRuntime = ensureRuntime(configuration: configuration) else {
            return plainBatchResult(range: clamped)
        }

        let documentState = await treeSitterRuntime.currentState(
            resolving: clamped
        )
        let spanSnapshot = mergedSpanSnapshot(
            documentSnapshot: documentSnapshot,
            documentState: documentState,
            languageConfiguration: configuration,
            theme: theme,
            lineRange: clamped
        )
        let highlighted = treeSitterHighlightedLines(in: clamped, spanSnapshot: spanSnapshot)
        return batchResult(
            range: clamped,
            lines: highlighted,
            defaultForeground: theme.defaultForeground
        )
    }

    private func ensureRuntime(configuration: LanguageConfiguration) -> SyntaxDocumentRuntime? {
        if treeSitterRuntime == nil {
            treeSitterRuntime = try? SyntaxDocumentRuntime(
                documentSnapshot: documentSnapshot,
                languageConfiguration: configuration
            )
            treeSitterSpanSnapshot = nil
        }

        return treeSitterRuntime
    }

    private func mergedSpanSnapshot(
        documentSnapshot: DocumentSnapshot,
        documentState: SyntaxDocumentState,
        languageConfiguration: LanguageConfiguration,
        theme: SyntaxTheme,
        lineRange: Range<Int>
    ) -> SyntaxSpanSnapshot {
        let builtSnapshot = SyntaxSpanSnapshotBuilder.build(
            documentSnapshot: documentSnapshot,
            documentState: documentState,
            languageConfiguration: languageConfiguration,
            theme: theme,
            lineRange: lineRange
        )

        if let existingSnapshot = treeSitterSpanSnapshot {
            let mergedSnapshot = existingSnapshot.merging(
                revision: documentState.syntaxRevision,
                documentVersion: documentState.documentVersion,
                themeName: theme.name,
                lineCount: documentSnapshot.lineCount,
                lines: builtSnapshot.lines(in: lineRange)
            )
            treeSitterSpanSnapshot = mergedSnapshot
            return mergedSnapshot
        }

        treeSitterSpanSnapshot = builtSnapshot
        return builtSnapshot
    }

    private func plainBatchResult(range: Range<Int>) -> SyntaxBatchComputationResult {
        batchResult(
            range: range,
            lines: plainActualLines(in: range),
            defaultForeground: defaultForeground
        )
    }

    private func batchResult(
        range: Range<Int>,
        lines: [SyntaxHighlightedLine],
        defaultForeground: String
    ) -> SyntaxBatchComputationResult {
        SyntaxBatchComputationResult(
            version: version,
            range: range,
            lines: lines,
            defaultForeground: defaultForeground
        )
    }

    private func ensureAssetsLoaded() async {
        guard !assetsLoaded else { return }

        if let configuration = TreeSitterLanguageRegistry.configuration(
            forLanguageIdentifier: language
        ) {
            treeSitterConfiguration = configuration
            let bundle = Bundle(path: bundlePath) ?? .moduleBundle
            treeSitterTheme = try? SyntaxTheme.load(
                name: themeName,
                bundle: bundle
            )
            defaultForeground = treeSitterTheme?.defaultForeground ?? fallbackHighlightForeground
        }

        assetsLoaded = true
    }

    private func clamp(_ range: Range<Int>) -> Range<Int> {
        let start = max(0, min(range.lowerBound, documentSnapshot.lineCount))
        let end = max(start, min(range.upperBound, documentSnapshot.lineCount))
        return start..<end
    }

    private func normalizedTokens(
        for text: String,
        tokens: [SyntaxHighlightToken]
    ) -> [SyntaxHighlightToken] {
        let lineLength = text.utf16.count
        guard lineLength > 0 else { return [] }

        if tokens.isEmpty {
            return [
                SyntaxHighlightToken(
                    range: 0..<lineLength,
                    foregroundColor: defaultForeground
                )
            ]
        }

        var normalized: [SyntaxHighlightToken] = []
        normalized.reserveCapacity(tokens.count + 2)

        var cursor = 0
        for token in tokens.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            let lowerBound = max(0, min(token.range.lowerBound, lineLength))
            let upperBound = max(lowerBound, min(token.range.upperBound, lineLength))
            guard lowerBound < upperBound else { continue }

            if cursor < lowerBound {
                normalized.append(
                    SyntaxHighlightToken(
                        range: cursor..<lowerBound,
                        foregroundColor: defaultForeground
                    )
                )
            }

            if cursor < upperBound {
                normalized.append(
                    SyntaxHighlightToken(
                        range: max(cursor, lowerBound)..<upperBound,
                        foregroundColor: token.foregroundColor,
                        backgroundColor: token.backgroundColor,
                        fontStyle: token.fontStyle
                    )
                )
                cursor = upperBound
            }
        }

        if cursor < lineLength {
            normalized.append(
                SyntaxHighlightToken(
                    range: cursor..<lineLength,
                    foregroundColor: defaultForeground
                )
            )
        }

        return normalized
    }

    private func plainActualLines(in range: Range<Int>) -> [SyntaxHighlightedLine] {
        range.map { lineIndex in
            let text = documentSnapshot.line(lineIndex).text
            let tokens = text.utf16.isEmpty ? [] : [
                SyntaxHighlightToken(
                    range: 0..<text.utf16.count,
                    foregroundColor: defaultForeground
                )
            ]
            let status: HighlightStatus
            if maximumTokenizationLineLength > 0, text.utf16.count > maximumTokenizationLineLength {
                status = .intentionallyLimited
            } else {
                status = .actual
            }
            return SyntaxHighlightedLine(
                lineIndex: lineIndex,
                text: text,
                tokens: tokens,
                status: status
            )
        }
    }

    private func treeSitterHighlightedLines(
        in range: Range<Int>,
        spanSnapshot: SyntaxSpanSnapshot?
    ) -> [SyntaxHighlightedLine] {
        range.map { lineIndex in
            let text = documentSnapshot.line(lineIndex).text
            if maximumTokenizationLineLength > 0, text.utf16.count > maximumTokenizationLineLength {
                return SyntaxHighlightedLine(
                    lineIndex: lineIndex,
                    text: text,
                    tokens: text.utf16.isEmpty ? [] : [
                        SyntaxHighlightToken(
                            range: 0..<text.utf16.count,
                            foregroundColor: defaultForeground
                        )
                    ],
                    status: .intentionallyLimited
                )
            }

            let spans = spanSnapshot?.line(lineIndex).spans ?? []
            let tokens = normalizedTokens(
                for: text,
                tokens: spans.map { span in
                    SyntaxHighlightToken(
                        range: span.range,
                        foregroundColor: span.style.foreground,
                        backgroundColor: span.style.background,
                        fontStyle: span.style.fontStyle
                    )
                }
            )

            return SyntaxHighlightedLine(
                lineIndex: lineIndex,
                text: text,
                tokens: tokens,
                status: .actual
            )
        }
    }
}

@MainActor
public final class SyntaxController: SyntaxHandle {
    private struct WarmCacheKey: Hashable {
        let identity: SyntaxWarmCacheIdentity
        let language: String
        let themeName: String
        let maximumTokenizationLineLength: Int
    }

    private static let warmCacheLimit = 16
    private static var warmCache: [WarmCacheKey: SyntaxWarmCacheEntry] = [:]
    private static var warmCacheOrder: [WarmCacheKey] = []

    private let language: String
    private let themeName: String
    private let maximumTokenizationLineLength: Int
    private var defaultForeground: String
    private let worker: SyntaxControllerWorker
    private var warmCacheIdentity: SyntaxWarmCacheIdentity?

    private var documentSnapshot: DocumentSnapshot
    private var version: Int = 0
    private var nextSnapshotRevision: UInt64 = 1
    private var pendingBatchTask: Task<Void, Never>?
    private var pendingDocumentUpdate: SyntaxDocumentUpdate?
    private var pendingInvalidation = SyntaxInvalidationSet(lineRanges: [])
    private var visibleRange: SourceLineRange?

    private var snapshot: SyntaxSnapshot

    public init(
        documentSnapshot: DocumentSnapshot,
        language: String,
        themeName: String,
        bundle: Bundle? = nil,
        warmCacheIdentity: SyntaxWarmCacheIdentity? = nil,
        maximumTokenizationLineLength: Int = 0
    ) {
        self.documentSnapshot = documentSnapshot
        self.language = language
        self.themeName = themeName
        self.maximumTokenizationLineLength = max(0, maximumTokenizationLineLength)
        self.warmCacheIdentity = warmCacheIdentity

        let warmCacheKey = Self.makeWarmCacheKey(
            identity: warmCacheIdentity,
            language: language,
            themeName: themeName,
            maximumTokenizationLineLength: self.maximumTokenizationLineLength
        )
        let warmCacheEntry = warmCacheKey.flatMap { key in
            Self.entryForWarmCacheKey(key, lineCount: documentSnapshot.lineCount)
        }

        self.defaultForeground = warmCacheEntry?.defaultForeground ?? fallbackHighlightForeground

        let resolvedBundle = bundle ?? Bundle.moduleBundle
        self.worker = SyntaxControllerWorker(
            documentSnapshot: documentSnapshot,
            language: language,
            themeName: themeName,
            bundlePath: resolvedBundle.bundlePath,
            maximumTokenizationLineLength: self.maximumTokenizationLineLength
        )
        self.snapshot = warmCacheEntry?.snapshot ?? SyntaxSnapshot(
            revision: 0,
            lineCount: documentSnapshot.lineCount,
            visibleRange: nil,
            linesByIndex: [:]
        )
        self.nextSnapshotRevision = (warmCacheEntry?.snapshot.revision ?? 0) &+ 1
    }

    public convenience init(
        lines: [String],
        language: String,
        themeName: String,
        bundle: Bundle? = nil,
        maximumTokenizationLineLength: Int = 0
    ) {
        self.init(
            documentSnapshot: makeDocumentSnapshot(from: lines),
            language: language,
            themeName: themeName,
            bundle: bundle,
            warmCacheIdentity: nil,
            maximumTokenizationLineLength: maximumTokenizationLineLength
        )
    }

    public static func resetWarmCacheForTesting() {
        warmCache.removeAll()
        warmCacheOrder.removeAll()
    }

    public func currentSnapshot() -> SyntaxSnapshot {
        snapshot
    }

    public func noteVisibleRange(_ range: SourceLineRange) {
        visibleRange = range
        snapshot = SyntaxSnapshot(
            revision: snapshot.revision,
            lineCount: snapshot.lineCount,
            visibleRange: range,
            linesByIndex: snapshot.storedLines
        )
    }

    public func schedule(_ request: SyntaxRequest) {
        let range = clamp(request.preferredRange.range)
        guard !range.isEmpty else { return }

        _ = SyntaxRuntimeDiagnostics.recordSyntaxRequest(
            operation: "SyntaxController.schedule",
            metadata: nextScheduledBatchMetadata(
                preferredRange: range,
                batchSize: max(1, request.batchSize),
                backlogPolicy: request.backlogPolicy
            )
        )

        guard pendingBatchTask == nil else { return }
        pendingBatchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pendingBatchTask = nil }
            await self.processNextBatch(
                preferredRange: range,
                batchSize: max(1, request.batchSize),
                backlogPolicy: request.backlogPolicy
            )
        }
    }

    public func replaceAll(lines: [String]) {
        replaceDocumentSnapshot(makeDocumentSnapshot(from: lines))
    }

    public func replaceDocumentSnapshot(_ documentSnapshot: DocumentSnapshot) {
        self.documentSnapshot = documentSnapshot
        version += 1
        pendingDocumentUpdate = nil
        pendingInvalidation = fullDocumentInvalidation(for: documentSnapshot.lineCount)
        snapshot = SyntaxSnapshot(
            revision: consumeSnapshotRevision(),
            lineCount: documentSnapshot.lineCount,
            visibleRange: visibleRange,
            linesByIndex: [:]
        )
    }

    public func updateWarmCacheIdentity(_ identity: SyntaxWarmCacheIdentity?) {
        warmCacheIdentity = identity
    }

    public func updateLines(_ lines: [String], dirtyFrom lineIndex: Int) {
        updateDocument(makeDocumentSnapshot(from: lines), dirtyFrom: lineIndex)
    }

    public func updateDocument(_ documentSnapshot: DocumentSnapshot, dirtyFrom lineIndex: Int) {
        pendingDocumentUpdate = nil
        self.documentSnapshot = documentSnapshot
        version += 1
        let invalidation = fallbackInvalidation(
            for: documentSnapshot,
            dirtyFrom: lineIndex
        )
        pendingInvalidation = SyntaxInvalidationSet(
            lineRanges: pendingInvalidation.lineRanges + invalidation.lineRanges
        )
        snapshot = snapshotApplyingInvalidation(
            to: documentSnapshot,
            invalidation: invalidation
        )
    }

    public func updateDocument(_ update: SyntaxDocumentUpdate, dirtyFrom lineIndex: Int) {
        self.documentSnapshot = update.newSnapshot
        version += 1
        pendingDocumentUpdate = update

        let editInvalidation = SyntaxInvalidationSet.fromEdits(
            update.transaction.edits,
            oldSnapshot: update.oldSnapshot,
            newSnapshot: update.newSnapshot,
            policy: .boundedProjection
        )
        let invalidation = editInvalidation.isEmpty
            ? fallbackInvalidation(for: update.newSnapshot, dirtyFrom: lineIndex)
            : editInvalidation
        pendingInvalidation = SyntaxInvalidationSet(
            lineRanges: pendingInvalidation.lineRanges + invalidation.lineRanges
        )
        snapshot = snapshotApplyingInvalidation(
            to: update.newSnapshot,
            invalidation: invalidation
        )
    }

    @discardableResult
    public func prepareActualHighlights(
        visibleRange: SourceLineRange,
        preferredRange: SourceLineRange,
        batchSize: Int,
        budgetNanoseconds: UInt64,
        backlogPolicy: SyntaxBacklogPolicy = .fullDocument
    ) async -> Bool {
        let clampedVisibleRange = clamp(visibleRange.range)
        let clampedPreferredRange = clamp(preferredRange.range)
        guard !clampedVisibleRange.isEmpty else { return true }

        noteVisibleRange(
            SourceLineRange(
                clampedVisibleRange.lowerBound,
                clampedVisibleRange.upperBound
            )
        )

        if snapshot.hasActualHighlights(in: clampedVisibleRange) {
            return true
        }

        let deadline = DispatchTime.now().uptimeNanoseconds &+ budgetNanoseconds
        let normalizedBatchSize = max(batchSize, clampedVisibleRange.count)

        while DispatchTime.now().uptimeNanoseconds < deadline {
            await processNextBatch(
                preferredRange: clampedPreferredRange,
                batchSize: normalizedBatchSize,
                backlogPolicy: backlogPolicy
            )

            if snapshot.hasActualHighlights(in: clampedVisibleRange) {
                return true
            }

            if nextScheduledBatch(
                preferredRange: clampedPreferredRange,
                batchSize: normalizedBatchSize,
                backlogPolicy: backlogPolicy
            ) == nil {
                return false
            }
        }

        return snapshot.hasActualHighlights(in: clampedVisibleRange)
    }

    public func hasScheduledWork(
        preferredRange: SourceLineRange,
        batchSize: Int,
        backlogPolicy: SyntaxBacklogPolicy = .fullDocument
    ) -> Bool {
        nextScheduledBatch(
            preferredRange: preferredRange.range,
            batchSize: batchSize,
            backlogPolicy: backlogPolicy
        ) != nil
    }

    func processNextBatch(
        preferredRange: Range<Int>,
        batchSize: Int,
        backlogPolicy: SyntaxBacklogPolicy = .fullDocument
    ) async {
        let range = clamp(preferredRange)
        guard !range.isEmpty else { return }

        let currentVersion = version
        let currentUpdate = pendingDocumentUpdate
        await worker.sync(
            documentSnapshot: documentSnapshot,
            update: currentUpdate,
            version: currentVersion
        )
        guard currentVersion == version else { return }
        if currentUpdate != nil {
            pendingDocumentUpdate = nil
        }

        let scheduledWork = nextScheduledBatch(
            preferredRange: range,
            batchSize: batchSize,
            backlogPolicy: backlogPolicy
        )
        guard let scheduledWork,
              let result = await worker.highlight(
            range: scheduledWork.range,
            expectedVersion: currentVersion
        ) else {
            return
        }

        guard result.version == version else { return }
        apply(result)
    }

    // swiftlint:disable function_body_length
    func nextScheduledBatch(
        preferredRange: Range<Int>,
        batchSize: Int,
        backlogPolicy: SyntaxBacklogPolicy = .fullDocument
    ) -> SyntaxWorkItem? {
        let normalizedBatchSize = max(1, batchSize)
        let currentSnapshot = snapshot
        let clampedPreferredRange = clamp(preferredRange)
        let clampedVisibleRange = clamp(visibleRange?.range ?? clampedPreferredRange)

        if let targetLine = firstDirtyTargetLine(
            in: clampedVisibleRange,
            snapshot: currentSnapshot
        ) {
            return makeWorkItem(
                priority: .visibleDirty,
                targetLine: targetLine,
                batchSize: normalizedBatchSize
            )
        }

        if let targetLine = firstUncoveredTargetLine(
            in: clampedVisibleRange,
            snapshot: currentSnapshot
        ) {
            return makeWorkItem(
                priority: .visibleUncovered,
                targetLine: targetLine,
                batchSize: normalizedBatchSize
            )
        }

        for range in prefetchSearchRanges(
            preferredRange: clampedPreferredRange,
            visibleRange: clampedVisibleRange
        ) {
            if let targetLine = firstDirtyTargetLine(in: range, snapshot: currentSnapshot) {
                return makeWorkItem(
                    priority: .prefetch,
                    targetLine: targetLine,
                    batchSize: normalizedBatchSize
                )
            }
            if let targetLine = firstUncoveredTargetLine(in: range, snapshot: currentSnapshot) {
                return makeWorkItem(
                    priority: .prefetch,
                    targetLine: targetLine,
                    batchSize: normalizedBatchSize
                )
            }
        }

        for range in backlogSearchRanges(
            preferredRange: clampedPreferredRange,
            visibleRange: clampedVisibleRange,
            backlogPolicy: backlogPolicy
        ) {
            if let targetLine = firstDirtyTargetLine(in: range, snapshot: currentSnapshot) {
                return makeWorkItem(
                    priority: .dirtyBacklog,
                    targetLine: targetLine,
                    batchSize: normalizedBatchSize
                )
            }
        }

        for range in backlogSearchRanges(
            preferredRange: clampedPreferredRange,
            visibleRange: clampedVisibleRange,
            backlogPolicy: backlogPolicy
        ) {
            if let targetLine = firstUncoveredTargetLine(in: range, snapshot: currentSnapshot) {
                return makeWorkItem(
                    priority: .fillBacklog,
                    targetLine: targetLine,
                    batchSize: normalizedBatchSize
                )
            }
        }

        return nil
    }
    // swiftlint:enable function_body_length

    private func firstDirtyTargetLine(
        in range: Range<Int>,
        snapshot: SyntaxSnapshot
    ) -> Int? {
        firstTargetLine(in: range, snapshot: snapshot) { $0 == .dirty }
    }

    private func firstUncoveredTargetLine(
        in range: Range<Int>,
        snapshot: SyntaxSnapshot
    ) -> Int? {
        firstTargetLine(in: range, snapshot: snapshot) { $0 == .uncovered }
    }

    private func firstTargetLine(
        in range: Range<Int>,
        snapshot: SyntaxSnapshot,
        matching predicate: (PendingLineKind) -> Bool
    ) -> Int? {
        for lineIndex in clamp(range) {
            guard let kind = pendingLineKind(at: lineIndex, snapshot: snapshot) else {
                continue
            }
            if predicate(kind) {
                return lineIndex
            }
        }
        return nil
    }

    private func makeWorkItem(
        priority: SyntaxWorkPriority,
        targetLine: Int,
        batchSize: Int
    ) -> SyntaxWorkItem {
        let start = max(0, min(targetLine, max(0, documentSnapshot.lineCount - 1)))
        let end = min(documentSnapshot.lineCount, start + batchSize)
        return SyntaxWorkItem(priority: priority, range: start..<end)
    }

    private func prefetchSearchRanges(
        preferredRange: Range<Int>,
        visibleRange: Range<Int>
    ) -> [Range<Int>] {
        let leadingPrefetch = orderedClampedRange(
            from: preferredRange.lowerBound,
            to: visibleRange.lowerBound
        )
        let trailingPrefetch = orderedClampedRange(
            from: visibleRange.upperBound,
            to: preferredRange.upperBound
        )
        if trailingPrefetch.count >= leadingPrefetch.count {
            return [trailingPrefetch, leadingPrefetch]
        }
        return [leadingPrefetch, trailingPrefetch]
    }

    private func backlogSearchRanges(
        preferredRange: Range<Int>,
        visibleRange: Range<Int>,
        backlogPolicy: SyntaxBacklogPolicy
    ) -> [Range<Int>] {
        let prefersTrailing = prefetchSearchRanges(
            preferredRange: preferredRange,
            visibleRange: visibleRange
        ).first?.lowerBound == visibleRange.upperBound
        let leadingBacklog: Range<Int>
        let trailingBacklog: Range<Int>

        switch backlogPolicy {
        case .fullDocument:
            leadingBacklog = orderedClampedRange(from: 0, to: preferredRange.lowerBound)
            trailingBacklog = orderedClampedRange(
                from: preferredRange.upperBound,
                to: documentSnapshot.lineCount
            )
        case .visibleWindow(let maxLineCount):
            let normalizedLimit = max(0, maxLineCount)
            let lowerBound = max(0, preferredRange.lowerBound - normalizedLimit)
            let upperBound = min(documentSnapshot.lineCount, preferredRange.upperBound + normalizedLimit)
            leadingBacklog = orderedClampedRange(
                from: lowerBound,
                to: preferredRange.lowerBound
            )
            trailingBacklog = orderedClampedRange(
                from: preferredRange.upperBound,
                to: upperBound
            )
        }

        if prefersTrailing {
            return [trailingBacklog, leadingBacklog]
        }
        return [leadingBacklog, trailingBacklog]
    }

    private func nextScheduledBatchMetadata(
        preferredRange: Range<Int>,
        batchSize: Int,
        backlogPolicy: SyntaxBacklogPolicy
    ) -> String {
        let workItem = nextScheduledBatch(
            preferredRange: preferredRange,
            batchSize: batchSize,
            backlogPolicy: backlogPolicy
        )
        let scheduledDescription = workItem.map {
            "\($0.priority.rawValue) scheduled=\($0.range.lowerBound)..<\($0.range.upperBound)"
        } ?? "idle"
        return """
        preferred=\(preferredRange.lowerBound)..<\(preferredRange.upperBound) \
        batch=\(batchSize) \
        backlog=\(backlogPolicy.description) \
        \(scheduledDescription)
        """
    }

    private enum PendingLineKind {
        case dirty
        case uncovered
    }

    private func pendingLineKind(
        at lineIndex: Int,
        snapshot: SyntaxSnapshot
    ) -> PendingLineKind? {
        guard lineIndex >= 0, lineIndex < documentSnapshot.lineCount else { return nil }

        if pendingInvalidation.contains(lineIndex: lineIndex) {
            return .dirty
        }

        switch snapshot.line(lineIndex)?.status {
        case .actual, .intentionallyLimited:
            return nil
        case .stale:
            return .dirty
        case nil:
            return .uncovered
        }
    }

    private func orderedClampedRange(from start: Int, to end: Int) -> Range<Int> {
        let lowerBound = min(start, end)
        let upperBound = max(start, end)
        return clamp(lowerBound..<upperBound)
    }

    private func apply(_ result: SyntaxBatchComputationResult) {
        defaultForeground = result.defaultForeground
        pendingInvalidation = pendingInvalidation.subtracting(result.range)

        var linesByIndex = snapshot.storedLines
        for line in result.lines {
            guard line.lineIndex < documentSnapshot.lineCount else { continue }
            linesByIndex[line.lineIndex] = line
        }
        snapshot = SyntaxSnapshot(
            revision: consumeSnapshotRevision(),
            lineCount: documentSnapshot.lineCount,
            visibleRange: visibleRange,
            linesByIndex: linesByIndex
        )
        updateWarmCacheIfPossible()
    }

    private func snapshotApplyingInvalidation(
        to documentSnapshot: DocumentSnapshot,
        invalidation: SyntaxInvalidationSet
    ) -> SyntaxSnapshot {
        let previousSnapshot = snapshot
        var linesByIndex: [Int: SyntaxHighlightedLine] = [:]

        for (storedLineIndex, previous) in previousSnapshot.storedLines {
            guard storedLineIndex < documentSnapshot.lineCount else { continue }
            guard invalidation.contains(lineIndex: storedLineIndex) == false else {
                let updatedText = documentSnapshot.line(storedLineIndex).text
                if previous.text == updatedText {
                    linesByIndex[storedLineIndex] = previous.withStatus(.stale)
                }
                continue
            }
            linesByIndex[storedLineIndex] = previous
        }

        return SyntaxSnapshot(
            revision: consumeSnapshotRevision(),
            lineCount: documentSnapshot.lineCount,
            visibleRange: visibleRange,
            linesByIndex: linesByIndex
        )
    }

    private func fallbackInvalidation(
        for documentSnapshot: DocumentSnapshot,
        dirtyFrom lineIndex: Int
    ) -> SyntaxInvalidationSet {
        guard documentSnapshot.lineCount > 0 else {
            return SyntaxInvalidationSet(lineRanges: [])
        }

        let lowerBound = max(0, min(lineIndex, max(0, documentSnapshot.lineCount - 1)))
        return SyntaxInvalidationSet(
            lineRanges: [
                SourceLineRange(lowerBound, documentSnapshot.lineCount)
            ]
        )
    }

    private func fullDocumentInvalidation(for lineCount: Int) -> SyntaxInvalidationSet {
        guard lineCount > 0 else {
            return SyntaxInvalidationSet(lineRanges: [])
        }
        return SyntaxInvalidationSet(
            lineRanges: [
                SourceLineRange(0, lineCount)
            ]
        )
    }

    private func clamp(_ range: Range<Int>) -> Range<Int> {
        let lowerBound = max(0, min(range.lowerBound, documentSnapshot.lineCount))
        let upperBound = max(lowerBound, min(range.upperBound, documentSnapshot.lineCount))
        return lowerBound..<upperBound
    }

    private func consumeSnapshotRevision() -> UInt64 {
        defer { nextSnapshotRevision += 1 }
        return nextSnapshotRevision
    }

    private func updateWarmCacheIfPossible() {
        guard pendingInvalidation.isEmpty,
              pendingDocumentUpdate == nil,
              let key = Self.makeWarmCacheKey(
                identity: warmCacheIdentity,
                language: language,
                themeName: themeName,
                maximumTokenizationLineLength: maximumTokenizationLineLength
              ) else {
            return
        }

        let cacheableLines = snapshot.storedLines.filter { _, line in
            line.status.countsAsActual
        }
        guard !cacheableLines.isEmpty else { return }

        let cacheableSnapshot = SyntaxSnapshot(
            revision: snapshot.revision,
            lineCount: snapshot.lineCount,
            visibleRange: snapshot.visibleRange,
            linesByIndex: cacheableLines
        )
        Self.storeWarmCacheEntry(
            SyntaxWarmCacheEntry(
                snapshot: cacheableSnapshot,
                defaultForeground: defaultForeground
            ),
            for: key
        )
    }

    private static func makeWarmCacheKey(
        identity: SyntaxWarmCacheIdentity?,
        language: String,
        themeName: String,
        maximumTokenizationLineLength: Int
    ) -> WarmCacheKey? {
        guard let identity else { return nil }
        return WarmCacheKey(
            identity: identity,
            language: language,
            themeName: themeName,
            maximumTokenizationLineLength: maximumTokenizationLineLength
        )
    }

    private static func entryForWarmCacheKey(
        _ key: WarmCacheKey,
        lineCount: Int
    ) -> SyntaxWarmCacheEntry? {
        guard let entry = warmCache[key], entry.snapshot.lineCount == lineCount else {
            return nil
        }
        touchWarmCacheKey(key)
        return entry
    }

    private static func storeWarmCacheEntry(
        _ entry: SyntaxWarmCacheEntry,
        for key: WarmCacheKey
    ) {
        warmCache[key] = entry
        touchWarmCacheKey(key)

        while warmCacheOrder.count > warmCacheLimit {
            let evicted = warmCacheOrder.removeFirst()
            warmCache.removeValue(forKey: evicted)
        }
    }

    private static func touchWarmCacheKey(_ key: WarmCacheKey) {
        warmCacheOrder.removeAll { $0 == key }
        warmCacheOrder.append(key)
    }
}
// swiftlint:enable type_body_length

private extension SyntaxBacklogPolicy {
    var description: String {
        switch self {
        case .fullDocument:
            "fullDocument"
        case .visibleWindow(let maxLineCount):
            "visibleWindow(\(maxLineCount))"
        }
    }
}
