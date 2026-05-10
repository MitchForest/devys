// EditorPreviewSession.swift
// DevysEditor - reusable preview-first editor loading.

import Foundation
import Observation
import Text

/// A reusable preview-first document session for hosts that need fast file display
/// without owning app-level tab, workspace, or save policy.
@MainActor
@Observable
public final class EditorPreviewSession: Identifiable {
    public enum Phase {
        case idle
        case loading
        case preview(LoadedDocumentPreview)
        case loaded(EditorDocument)
        case failed(String)
    }

    public let id: UUID
    public private(set) var url: URL
    public private(set) var phase: Phase = .idle
    public private(set) var document: EditorDocument?

    private let previewRequest: DocumentPreviewRequest

    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    @ObservationIgnored
    private var loadRevision: UInt64 = 0

    public init(
        url: URL,
        previewRequest: DocumentPreviewRequest = .default,
        startsLoading: Bool = true
    ) {
        self.id = UUID()
        self.url = url.standardizedFileURL
        self.previewRequest = previewRequest

        if startsLoading {
            startLoading()
        }
    }

    public var isLoading: Bool {
        switch phase {
        case .loading:
            true
        case .preview(let preview):
            preview.isEligibleForFullLoad
        case .idle, .loaded, .failed:
            false
        }
    }

    public var lastError: String? {
        if case .failed(let message) = phase {
            return message
        }
        return nil
    }

    public func open(_ newURL: URL) {
        let canonicalURL = newURL.standardizedFileURL
        guard canonicalURL != url || document == nil else { return }
        url = canonicalURL
        document?.fileURL = canonicalURL
        startLoading()
    }

    public func reload() {
        startLoading()
    }

    public func cancelLoading() {
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
        let request = previewRequest

        loadTask?.cancel()
        phase = .loading

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let preview = try await DefaultDocumentIOService().loadPreview(
                    url: targetURL,
                    request: request
                )
                guard !Task.isCancelled else { return }

                let expectedVersion = self.applyPreviewResult(
                    revision: revision,
                    preview: preview,
                    url: targetURL
                )
                guard preview.isEligibleForFullLoad else {
                    self.completePreviewOnlyResult(revision: revision)
                    return
                }

                let preparedDocument = try await EditorDocument.prepareTextDocument(
                    content: preview.content ?? ""
                )
                guard !Task.isCancelled else { return }

                try await self.finishLoading(
                    revision: revision,
                    preview: preview,
                    preparedDocument: preparedDocument,
                    expectedVersion: expectedVersion,
                    url: targetURL
                )
            } catch is CancellationError {
                self.clearLoadTask(revision: revision)
            } catch {
                guard !Task.isCancelled else { return }
                self.applyFailureResult(
                    revision: revision,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func applyPreviewResult(
        revision: UInt64,
        preview: LoadedDocumentPreview,
        url: URL
    ) -> DocumentVersion {
        guard revision == loadRevision else {
            return document?.documentVersion ?? DocumentVersion()
        }

        guard let content = preview.content else {
            document = nil
            phase = .preview(preview)
            return DocumentVersion()
        }

        if let document,
           document.fileURL?.standardizedFileURL == url.standardizedFileURL {
            document.fileURL = url
            phase = .preview(preview)
            return document.documentVersion
        }

        let previewDocument = EditorDocument.makePreviewDocument(
            content: content,
            language: preview.language,
            fileURL: url
        )
        document = previewDocument
        phase = .preview(preview)
        return previewDocument.documentVersion
    }

    private func finishLoading(
        revision: UInt64,
        preview: LoadedDocumentPreview,
        preparedDocument: TextDocument,
        expectedVersion: DocumentVersion,
        url: URL
    ) async throws {
        guard revision == loadRevision else { return }

        if let document {
            try await document.activatePreparedTextDocument(
                preparedDocument,
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

    private func applySuccessfulLoad(
        revision: UInt64,
        document loadedDocument: EditorDocument
    ) {
        guard revision == loadRevision else { return }
        document = loadedDocument
        loadTask = nil
        phase = .loaded(loadedDocument)
    }

    private func applyFailureResult(
        revision: UInt64,
        message: String
    ) {
        guard revision == loadRevision else { return }
        document = nil
        loadTask = nil
        phase = .failed(message)
    }

    private func completePreviewOnlyResult(revision: UInt64) {
        guard revision == loadRevision else { return }
        loadTask = nil
    }

    private func clearLoadTask(revision: UInt64) {
        guard revision == loadRevision else { return }
        loadTask = nil
    }
}
