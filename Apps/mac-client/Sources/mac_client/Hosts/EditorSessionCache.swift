import Editor
import Foundation

@MainActor
final class EditorSessionCache {
    private var sessions: [UUID: EditorPreviewSession] = [:]

    func session(
        id: UUID,
        url: URL,
        previewRequest: DocumentPreviewRequest
    ) -> EditorPreviewSession {
        if let session = sessions[id] {
            return session
        }
        let session = EditorPreviewSession(
            url: url.standardizedFileURL,
            previewRequest: previewRequest
        )
        sessions[id] = session
        return session
    }

    func removeSession(id: UUID) {
        sessions.removeValue(forKey: id)
    }

    func removeAll() {
        sessions.removeAll()
    }
}
