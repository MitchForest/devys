import AppKit
import ComposableArchitecture
import Editor
import Foundation

struct DocumentClient: Sendable {
    var loadPreview: @Sendable (URL, DocumentPreviewRequest) async throws -> LoadedDocumentPreview
    var save: @Sendable (String, URL) async throws -> Void
    var revealInFinder: @Sendable (URL) async -> Void

    init(
        loadPreview: @escaping @Sendable (URL, DocumentPreviewRequest) async throws -> LoadedDocumentPreview,
        save: @escaping @Sendable (String, URL) async throws -> Void,
        revealInFinder: @escaping @Sendable (URL) async -> Void
    ) {
        self.loadPreview = loadPreview
        self.save = save
        self.revealInFinder = revealInFinder
    }

    static let liveValue = DocumentClient(
        loadPreview: { url, request in
            try await DefaultDocumentIOService().loadPreview(
                url: url.standardizedFileURL,
                request: request
            )
        },
        save: { content, url in
            try await DefaultDocumentIOService().save(
                content: content,
                to: url.standardizedFileURL
            )
        },
        revealInFinder: { url in
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url.standardizedFileURL])
            }
        }
    )
}

private enum DocumentClientKey: DependencyKey {
    static let liveValue = DocumentClient.liveValue
}

extension DependencyValues {
    var documentClient: DocumentClient {
        get { self[DocumentClientKey.self] }
        set { self[DocumentClientKey.self] = newValue }
    }
}
