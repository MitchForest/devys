// EditorSession.swift
// Devys - Editor session management.
//
// Tracks a single editor document and save/reload actions.

import Split
import Foundation
import Observation
import Editor

@MainActor
@Observable
final class EditorSession: Identifiable {
    let id: UUID
    var url: URL

    var document: EditorDocument?
    var isLoading = false
    var lastError: String?

    init(url: URL) {
        self.id = UUID()
        self.url = url
        Task {
            await load()
        }
    }

    var isDirty: Bool {
        document?.isDirty ?? false
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let doc = try await EditorDocument.load(from: url)
            document = doc
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            document = EditorDocument(content: "// Failed to load file: \(error.localizedDescription)")
        }
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
        url = newURL
        document?.fileURL = newURL
    }
}

@MainActor
@Observable
final class EditorSessionRegistry {
    static let shared = EditorSessionRegistry()
    private init() {}

    private(set) var sessions: [TabID: EditorSession] = [:]

    func register(tabId: TabID, session: EditorSession) {
        sessions[tabId] = session
    }

    func unregister(tabId: TabID) {
        sessions.removeValue(forKey: tabId)
    }

    var dirtySessions: [EditorSession] {
        sessions.values.filter { $0.isDirty }
    }

    func saveAll() async -> Bool {
        var success = true
        for session in sessions.values where session.isDirty {
            do {
                try await session.save()
            } catch {
                success = false
            }
        }
        return success
    }
}
