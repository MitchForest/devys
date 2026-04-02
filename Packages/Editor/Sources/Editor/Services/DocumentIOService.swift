// DocumentIOService.swift
// Document load/save abstraction.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Syntax

@MainActor
protocol DocumentIOService {
    func load(url: URL) async throws -> (content: String, language: String)
}

public struct DefaultDocumentIOService: DocumentIOService {
    public init() {}

    public func load(url: URL) async throws -> (content: String, language: String) {
        let content = try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value
        let language = LanguageDetector.detect(from: url)
        return (content, language)
    }

    public func save(content: String, to url: URL) async throws {
        try await Task.detached {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }
}
