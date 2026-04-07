// DocumentIOService.swift
// Document load/save abstraction.
//
// Copyright © 2026 Devys. All rights reserved.

// periphery:ignore:all - preview-loading API is used by app/document bootstrap paths
import Foundation
import Syntax
import Text

struct LoadedDocumentContents: Sendable {
    let textDocument: TextDocument
    let language: String
}

public struct DocumentPreviewRequest: Sendable, Equatable {
    public static let `default` = DocumentPreviewRequest(maxBytes: 256 * 1024)

    public let maxBytes: Int

    public init(maxBytes: Int) {
        self.maxBytes = max(1, maxBytes)
    }
}

public struct DocumentPreviewRevision: Sendable, Equatable {
    public let fileSize: Int64?
    public let contentModificationDate: Date?

    public init(fileSize: Int64?, contentModificationDate: Date?) {
        self.fileSize = fileSize
        self.contentModificationDate = contentModificationDate
    }

    public static func current(for url: URL) throws -> DocumentPreviewRevision {
        try previewRevision(for: url)
    }
}

public enum LoadedDocumentPreviewKind: Sendable, Equatable {
    case text(String)
    case binary
    case tooLarge
}

public struct LoadedDocumentPreview: Sendable, Equatable {
    public let kind: LoadedDocumentPreviewKind
    public let language: String
    public let revision: DocumentPreviewRevision
    public let exceededLimit: Bool
    public let maxBytes: Int

    public init(
        kind: LoadedDocumentPreviewKind,
        language: String,
        revision: DocumentPreviewRevision,
        exceededLimit: Bool,
        maxBytes: Int
    ) {
        self.kind = kind
        self.language = language
        self.revision = revision
        self.exceededLimit = exceededLimit
        self.maxBytes = maxBytes
    }

    public var content: String? {
        if case .text(let content) = kind {
            return content
        }
        return nil
    }

    public var isBinary: Bool {
        if case .binary = kind {
            return true
        }
        return false
    }

    public var isTooLarge: Bool {
        if case .tooLarge = kind {
            return true
        }
        return false
    }

    public var isEligibleForFullLoad: Bool {
        content != nil && !exceededLimit
    }
}

protocol DocumentIOService: Sendable {
    func load(url: URL) async throws -> LoadedDocumentContents
    func loadPreview(url: URL, request: DocumentPreviewRequest) async throws -> LoadedDocumentPreview
}

extension DocumentIOService {
    func loadPreview(url: URL) async throws -> LoadedDocumentPreview {
        try await loadPreview(url: url, request: .default)
    }
}

public struct DefaultDocumentIOService: DocumentIOService {
    public init() {}

    public func loadPreview(
        url: URL,
        request: DocumentPreviewRequest = .default
    ) async throws -> LoadedDocumentPreview {
        try await Task.detached(priority: .userInitiated) {
            let language = LanguageDetector.detect(from: url)
            let revision = try previewRevision(for: url)

            if let preview = previewForKnownFileSize(
                revision: revision,
                language: language,
                request: request
            ) {
                return preview
            }

            let data = try readPreviewData(from: url, request: request)
            return previewFromData(
                data,
                language: language,
                revision: revision,
                request: request
            )
        }.value
    }

    func load(url: URL) async throws -> LoadedDocumentContents {
        return try await Task.detached(priority: .userInitiated) {
            let content = try String(contentsOf: url, encoding: .utf8)
            let textDocument = TextDocument(content: content)
            let language = LanguageDetector.detect(from: url)
            return LoadedDocumentContents(
                textDocument: textDocument,
                language: language
            )
        }.value
    }

    public func save(content: String, to url: URL) async throws {
        try await Task.detached {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }
}

private func previewForKnownFileSize(
    revision: DocumentPreviewRevision,
    language: String,
    request: DocumentPreviewRequest
) -> LoadedDocumentPreview? {
    guard let fileSize = revision.fileSize,
          fileSize > Int64(request.maxBytes) else {
        return nil
    }

    return makePreview(
        kind: .tooLarge,
        language: language,
        revision: revision,
        exceededLimit: true,
        request: request
    )
}

private func readPreviewData(
    from url: URL,
    request: DocumentPreviewRequest
) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer {
        try? handle.close()
    }

    let readLimit = request.maxBytes == Int.max
        ? Int.max
        : request.maxBytes + 1

    return try handle.read(upToCount: readLimit) ?? Data()
}

private func previewFromData(
    _ data: Data,
    language: String,
    revision: DocumentPreviewRevision,
    request: DocumentPreviewRequest
) -> LoadedDocumentPreview {
    if data.count > request.maxBytes {
        return makePreview(
            kind: .tooLarge,
            language: language,
            revision: revision,
            exceededLimit: true,
            request: request
        )
    }

    if data.contains(0) {
        return makePreview(
            kind: .binary,
            language: language,
            revision: revision,
            exceededLimit: false,
            request: request
        )
    }

    guard let content = String(data: data, encoding: .utf8) else {
        return makePreview(
            kind: .binary,
            language: language,
            revision: revision,
            exceededLimit: false,
            request: request
        )
    }

    return makePreview(
        kind: .text(content),
        language: language,
        revision: revision,
        exceededLimit: false,
        request: request
    )
}

private func makePreview(
    kind: LoadedDocumentPreviewKind,
    language: String,
    revision: DocumentPreviewRevision,
    exceededLimit: Bool,
    request: DocumentPreviewRequest
) -> LoadedDocumentPreview {
    LoadedDocumentPreview(
        kind: kind,
        language: language,
        revision: revision,
        exceededLimit: exceededLimit,
        maxBytes: request.maxBytes
    )
}

private func previewRevision(for url: URL) throws -> DocumentPreviewRevision {
    let values = try url.resourceValues(forKeys: [
        .fileSizeKey,
        .contentModificationDateKey
    ])

    return DocumentPreviewRevision(
        fileSize: values.fileSize.map(Int64.init),
        contentModificationDate: values.contentModificationDate
    )
}
