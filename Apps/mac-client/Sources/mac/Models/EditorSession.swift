// EditorSession.swift
// Devys - Editor session management.
//
// Tracks a single editor document and save/reload actions.

// swiftlint:disable file_length

import Split
import Foundation
import Observation
import Editor
import Syntax
import Text

struct EditorSessionPreview: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case text(String)
        case binary
        case tooLarge
    }

    let kind: Kind
    let language: String
    let revision: DocumentPreviewRevision
    let exceededLimit: Bool
    let maxBytes: Int

    init(
        kind: Kind,
        language: String,
        revision: DocumentPreviewRevision = DocumentPreviewRevision(
            fileSize: nil,
            contentModificationDate: nil
        ),
        exceededLimit: Bool = false,
        maxBytes: Int = DocumentPreviewRequest.default.maxBytes
    ) {
        self.kind = kind
        self.language = language
        self.revision = revision
        self.exceededLimit = exceededLimit
        self.maxBytes = maxBytes
    }

    init(content: String, language: String) {
        self.init(kind: .text(content), language: language)
    }

    init(preview: LoadedDocumentPreview) {
        let kind: Kind
        switch preview.kind {
        case .text(let content):
            kind = .text(content)
        case .binary:
            kind = .binary
        case .tooLarge:
            kind = .tooLarge
        }

        self.init(
            kind: kind,
            language: preview.language,
            revision: preview.revision,
            exceededLimit: preview.exceededLimit,
            maxBytes: preview.maxBytes
        )
    }

    var content: String? {
        if case .text(let content) = kind {
            return content
        }
        return nil
    }

    var requiresFullLoad: Bool {
        content != nil && !exceededLimit
    }

    var fileSize: Int64? {
        revision.fileSize
    }

    var isBinary: Bool {
        if case .binary = kind {
            return true
        }
        return false
    }

    var isTooLarge: Bool {
        if case .tooLarge = kind {
            return true
        }
        return false
    }
}

@MainActor
@Observable
// swiftlint:disable:next type_body_length
final class EditorSession: Identifiable {
    enum Phase {
        case idle
        case loading
        case preview(EditorSessionPreview)
        case loaded(EditorDocument)
        case failed(String)
    }

    typealias Loader = @Sendable (URL) async throws -> EditorDocument
    typealias PreviewLoader = @Sendable (URL) async throws -> EditorSessionPreview
    typealias DocumentBuilder = @Sendable (URL, EditorSessionPreview) async throws -> TextDocument

    let id: UUID
    var url: URL

    var phase: Phase = .idle
    var document: EditorDocument?
    var focusRequestID: Int = 0
    var navigationRequestID: Int = 0
    var navigationTarget: EditorNavigationTarget?
    var isFindPresented = false
    var findQuery = "" {
        didSet {
            guard oldValue != findQuery else { return }
            refreshFindMatches()
        }
    }
    private(set) var findMatches: [EditorSearchMatch] = []
    private(set) var activeFindMatchIndex: Int?

    @ObservationIgnored
    private let loader: Loader?

    @ObservationIgnored
    private let previewLoader: PreviewLoader?

    @ObservationIgnored
    private let documentBuilder: DocumentBuilder?

    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    @ObservationIgnored
    private var loadRevision: UInt64 = 0

    @ObservationIgnored
    private var activeRevision: DocumentPreviewRevision?
    @ObservationIgnored
    private var pendingNavigationTarget: EditorNavigationTarget?

    init(
        url: URL,
        loader: @escaping Loader
    ) {
        self.id = UUID()
        self.url = url.standardizedFileURL
        self.loader = loader
        self.previewLoader = nil
        self.documentBuilder = nil
    }

    init(
        url: URL,
        previewLoader: @escaping PreviewLoader = {
            let preview = try await DefaultDocumentIOService().loadPreview(
                url: $0,
                request: .default
            )
            return EditorSessionPreview(preview: preview)
        },
        documentBuilder: @escaping DocumentBuilder = { _, preview in
            try await EditorDocument.prepareTextDocument(content: preview.content ?? "")
        }
    ) {
        self.id = UUID()
        self.url = url.standardizedFileURL
        self.loader = nil
        self.previewLoader = previewLoader
        self.documentBuilder = documentBuilder
    }

    var isDirty: Bool {
        document?.isDirty ?? false
    }

    func requestKeyboardFocus() {
        focusRequestID &+= 1
    }

    var activeFindMatchID: EditorSearchMatch.ID? {
        guard let activeFindMatchIndex,
              findMatches.indices.contains(activeFindMatchIndex) else {
            return nil
        }
        return findMatches[activeFindMatchIndex].id
    }

    var preview: EditorSessionPreview? {
        if case .preview(let preview) = phase {
            return preview
        }
        return nil
    }

    var currentFileSize: Int64? {
        activeRevision?.fileSize
    }

    var isLoading: Bool {
        switch phase {
        case .loading:
            return true
        case .preview(let preview):
            return preview.requiresFullLoad
        default:
            return false
        }
    }

    // periphery:ignore - surfaced by state observers outside Periphery's analysis
    var lastError: String? {
        if case .failed(let message) = phase {
            return message
        }
        return nil
    }

    func open(_ newURL: URL) {
        let canonicalURL = newURL.standardizedFileURL
        let shouldReload = shouldReload(for: canonicalURL)

        url = canonicalURL
        document?.fileURL = canonicalURL
        guard shouldReload else { return }
        startLoading()
    }

    func reload() {
        startLoading()
    }

    func cancelLoading() {
        loadRevision &+= 1
        loadTask?.cancel()
        loadTask = nil
        if case .loading = phase {
            phase = .idle
        }
    }

    private func startLoading() {
        loadRevision &+= 1
        let revision = loadRevision
        let targetURL = url

        loadTask?.cancel()
        phase = .loading

        loadTask = Task { [weak self, loader, previewLoader, documentBuilder] in
            guard let self else { return }
            do {
                if let previewLoader, let documentBuilder {
                    let preview = try await previewLoader(targetURL)
                    guard !Task.isCancelled else { return }
                    let expectedVersion = await self.applyPreviewResult(
                        revision: revision,
                        preview: preview,
                        url: targetURL
                    )
                    guard !Task.isCancelled else { return }
                    guard preview.requiresFullLoad else {
                        await self.completePreviewOnlyResult(revision: revision)
                        return
                    }
                    let preparedTextDocument = try await documentBuilder(targetURL, preview)
                    guard !Task.isCancelled else { return }
                    try await self.finishLoading(
                        revision: revision,
                        preview: preview,
                        preparedTextDocument: preparedTextDocument,
                        expectedVersion: expectedVersion,
                        url: targetURL
                    )
                } else if let loader {
                    let loadedDocument = try await loader(targetURL)
                    guard !Task.isCancelled else { return }
                    await self.applyLoadedDocumentResult(
                        revision: revision,
                        document: loadedDocument
                    )
                } else {
                    throw CancellationError()
                }
            } catch is CancellationError {
                await self.clearLoadTask(revision: revision)
            } catch {
                guard !Task.isCancelled else { return }
                await self.applyFailureResult(
                    revision: revision,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func applyPreviewResult(
        revision: UInt64,
        preview: EditorSessionPreview,
        url: URL
    ) -> DocumentVersion {
        guard revision == loadRevision else {
            return document?.documentVersion ?? DocumentVersion()
        }

        if let content = preview.content {
            if let document,
               document.fileURL?.standardizedFileURL == url.standardizedFileURL {
                document.fileURL = url
                activeRevision = preview.revision
                phase = .preview(preview)
                return document.documentVersion
            }

            let previewDocument = EditorDocument.makePreviewDocument(
                content: content,
                language: preview.language,
                fileURL: url
            )
            document = previewDocument
            applyFindState(to: previewDocument, focusEditor: false)
            activeRevision = preview.revision
            phase = .preview(preview)
            return previewDocument.documentVersion
        }

        document = nil
        activeRevision = preview.revision
        phase = .preview(preview)
        return DocumentVersion()
    }

    private func finishLoading(
        revision: UInt64,
        preview: EditorSessionPreview,
        preparedTextDocument: TextDocument,
        expectedVersion: DocumentVersion,
        url: URL
    ) async throws {
        guard revision == loadRevision else { return }

        if let document {
            try await document.activatePreparedTextDocument(
                preparedTextDocument,
                expectedVersion: expectedVersion,
                fileURL: url
            )
            applySuccessfulLoad(revision: revision, document: document)
            return
        }

        let loadedDocument = try await EditorDocument.makeLoadedDocument(
            content: preview.content ?? "",
            language: preview.language,
            fileURL: url
        )
        applySuccessfulLoad(revision: revision, document: loadedDocument)
    }

    private func applyLoadedDocumentResult(
        revision: UInt64,
        document loadedDocument: EditorDocument
    ) {
        guard revision == loadRevision else { return }
        document = loadedDocument
        applyFindState(to: loadedDocument, focusEditor: false)
        activeRevision = nil
        applySuccessfulLoad(revision: revision, document: loadedDocument)
    }

    private func applyFailureResult(
        revision: UInt64,
        message: String
    ) {
        guard revision == loadRevision else { return }
        loadTask = nil
        activeRevision = nil
        phase = .failed(message)
    }

    private func applySuccessfulLoad(
        revision: UInt64,
        document: EditorDocument
    ) {
        guard revision == loadRevision else { return }
        applyPendingNavigationTargetIfNeeded(to: document)
        applyFindState(to: document, focusEditor: false)
        loadTask = nil
        phase = .loaded(document)
    }

    private func completePreviewOnlyResult(revision: UInt64) {
        guard revision == loadRevision else { return }
        loadTask = nil
    }

    private func clearLoadTask(revision: UInt64) {
        guard revision == loadRevision else { return }
        loadTask = nil
    }

    func save() async throws {
        guard let document else { return }
        let io = DefaultDocumentIOService()
        let targetURL = document.fileURL ?? url
        try await io.save(content: document.content, to: targetURL)
        document.fileURL = targetURL
        document.isDirty = false
    }

    func updateURL(_ newURL: URL) {
        let canonicalURL = newURL.standardizedFileURL
        if url != canonicalURL {
            activeRevision = nil
        }
        url = canonicalURL
        document?.fileURL = canonicalURL
    }

    func replaceDocumentContent(
        with content: String,
        fileURL: URL,
        markDirty: Bool
    ) async throws {
        loadRevision &+= 1
        loadTask?.cancel()
        loadTask = nil

        let canonicalURL = fileURL.standardizedFileURL
        let replacement = try await EditorDocument.makeLoadedDocument(
            content: content,
            language: LanguageDetector.detect(from: canonicalURL),
            fileURL: canonicalURL
        )
        replacement.isDirty = markDirty

        url = canonicalURL
        document = replacement
        applyPendingNavigationTargetIfNeeded(to: replacement)
        applyFindState(to: replacement, focusEditor: false)
        activeRevision = try? DocumentPreviewRevision.current(for: canonicalURL)
        phase = .loaded(replacement)
    }

    func presentFind() {
        if !isFindPresented {
            isFindPresented = true
        }

        if findQuery.isEmpty,
           let seed = selectedTextSearchSeed() {
            findQuery = seed
            return
        }

        refreshFindMatches()
    }

    func dismissFind() {
        isFindPresented = false
        findMatches = []
        activeFindMatchIndex = nil
        requestKeyboardFocus()
    }

    func selectNextFindMatch() {
        guard !findMatches.isEmpty else { return }
        let nextIndex = ((activeFindMatchIndex ?? -1) + 1) % findMatches.count
        setActiveFindMatch(index: nextIndex, focusEditor: false)
    }

    func selectPreviousFindMatch() {
        guard !findMatches.isEmpty else { return }
        let currentIndex = activeFindMatchIndex ?? 0
        let previousIndex = (currentIndex - 1 + findMatches.count) % findMatches.count
        setActiveFindMatch(index: previousIndex, focusEditor: false)
    }

    func navigate(to target: EditorNavigationTarget, focusEditor: Bool = true) {
        pendingNavigationTarget = target
        if let document {
            document.applyNavigationTarget(target)
        }
        navigationTarget = target
        navigationRequestID &+= 1
        if focusEditor {
            requestKeyboardFocus()
        }
    }

    private func shouldReload(for canonicalURL: URL) -> Bool {
        guard url == canonicalURL else {
            return true
        }

        switch phase {
        case .idle, .failed:
            return true
        case .loading:
            return false
        case .preview:
            return revisionHasChanged(for: canonicalURL)
        case .loaded:
            return revisionHasChanged(for: canonicalURL)
        }
    }

    private func revisionHasChanged(for url: URL) -> Bool {
        guard let activeRevision else {
            return false
        }

        guard let currentRevision = try? DocumentPreviewRevision.current(for: url) else {
            return true
        }

        return currentRevision != activeRevision
    }

    private func applyPendingNavigationTargetIfNeeded(to document: EditorDocument) {
        guard let pendingNavigationTarget else { return }
        document.applyNavigationTarget(pendingNavigationTarget)
    }

    private func applyFindState(
        to document: EditorDocument,
        focusEditor: Bool
    ) {
        guard isFindPresented else { return }
        let trimmedQuery = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            findMatches = []
            activeFindMatchIndex = nil
            return
        }

        let previousActiveMatchID = activeFindMatchID
        let matches = document.findMatches(for: trimmedQuery)
        findMatches = matches

        if let previousActiveMatchID,
           let existingIndex = matches.firstIndex(where: { $0.id == previousActiveMatchID }) {
            setActiveFindMatch(index: existingIndex, focusEditor: focusEditor)
            return
        }

        if matches.isEmpty {
            activeFindMatchIndex = nil
            return
        }

        setActiveFindMatch(index: 0, focusEditor: focusEditor)
    }

    private func refreshFindMatches() {
        guard let document else {
            findMatches = []
            activeFindMatchIndex = nil
            return
        }
        applyFindState(to: document, focusEditor: false)
    }

    private func setActiveFindMatch(
        index: Int,
        focusEditor: Bool
    ) {
        guard findMatches.indices.contains(index) else {
            activeFindMatchIndex = nil
            return
        }

        activeFindMatchIndex = index
        navigate(to: .match(findMatches[index]), focusEditor: focusEditor)
    }

    private func selectedTextSearchSeed() -> String? {
        guard let selectedText = document?.selectedText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty,
              !selectedText.contains("\n"),
              selectedText.count <= 200 else {
            return nil
        }
        return selectedText
    }
}

@MainActor
@Observable
final class EditorSessionPool {
    private(set) var sessionsByURL: [URL: EditorSession] = [:]
    private var retainCounts: [URL: Int] = [:]

    func session(for url: URL) -> EditorSession? {
        sessionsByURL[url.standardizedFileURL]
    }

    func acquire(url: URL) -> EditorSession {
        let canonicalURL = url.standardizedFileURL
        if let existingSession = sessionsByURL[canonicalURL] {
            retainCounts[canonicalURL, default: 0] += 1
            existingSession.open(canonicalURL)
            return existingSession
        }

        let session = EditorSession(url: canonicalURL)
        sessionsByURL[canonicalURL] = session
        retainCounts[canonicalURL] = 1
        session.open(canonicalURL)
        return session
    }

    func release(url: URL) {
        let canonicalURL = url.standardizedFileURL
        guard let count = retainCounts[canonicalURL] else { return }
        if count > 1 {
            retainCounts[canonicalURL] = count - 1
            return
        }

        retainCounts.removeValue(forKey: canonicalURL)
        let session = sessionsByURL.removeValue(forKey: canonicalURL)
        session?.cancelLoading()
    }

    func move(session: EditorSession, from oldURL: URL, to newURL: URL) {
        let oldCanonicalURL = oldURL.standardizedFileURL
        let newCanonicalURL = newURL.standardizedFileURL
        guard oldCanonicalURL != newCanonicalURL else { return }

        let retainedCount = retainCounts.removeValue(forKey: oldCanonicalURL) ?? 1
        sessionsByURL.removeValue(forKey: oldCanonicalURL)
        sessionsByURL[newCanonicalURL] = session
        retainCounts[newCanonicalURL] = retainedCount
    }
}

@MainActor
@Observable
final class EditorSessionRegistry {
    init() {}

    private(set) var sessions: [TabID: EditorSession] = [:]

    func register(tabId: TabID, session: EditorSession) {
        sessions[tabId] = session
    }

    func unregister(tabId: TabID) {
        sessions.removeValue(forKey: tabId)
    }

    var dirtySessions: [EditorSession] {
        uniqueSessions.filter { $0.isDirty }
    }

    func saveAll() async -> Bool {
        var success = true
        for session in uniqueSessions where session.isDirty {
            do {
                try await session.save()
            } catch {
                success = false
            }
        }
        return success
    }

    private var uniqueSessions: [EditorSession] {
        var seen: Set<ObjectIdentifier> = []
        var result: [EditorSession] = []
        for session in sessions.values {
            let identifier = ObjectIdentifier(session)
            if seen.insert(identifier).inserted {
                result.append(session)
            }
        }
        return result
    }
}
