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

public struct LoadedDocumentPreview: Sendable, Equatable {
    public let content: String
    public let language: String

    public init(content: String, language: String) {
        self.content = content
        self.language = language
    }
}

protocol DocumentIOService: Sendable {
    func load(url: URL) async throws -> LoadedDocumentContents
    func loadPreview(url: URL) async throws -> LoadedDocumentPreview
}

public struct DefaultDocumentIOService: DocumentIOService {
    public init() {}

    public func loadPreview(url: URL) async throws -> LoadedDocumentPreview {
        try await Task.detached(priority: .userInitiated) {
            let content = try String(contentsOf: url, encoding: .utf8)
            let language = LanguageDetector.detect(from: url)
            return LoadedDocumentPreview(content: content, language: language)
        }.value
    }

    func load(url: URL) async throws -> LoadedDocumentContents {
        let preview = try await loadPreview(url: url)
        return try await Task.detached(priority: .userInitiated) {
            let textDocument = TextDocument(content: preview.content)
            return LoadedDocumentContents(
                textDocument: textDocument,
                language: preview.language
            )
        }.value
    }

    public func save(content: String, to url: URL) async throws {
        try await Task.detached {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }
}
