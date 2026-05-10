import Browser
import Foundation

@MainActor
final class BrowserSessionCache {
    private var sessions: [UUID: BrowserSession] = [:]

    func session(id: UUID, url: URL, fileReadAccessURL: URL?) -> BrowserSession {
        if let session = sessions[id] {
            return session
        }

        let session = BrowserSession(
            id: id,
            url: url.standardizedForBrowserTab,
            fileReadAccessURL: fileReadAccessURL?.standardizedFileURL
        )
        sessions[id] = session
        return session
    }

    func removeSession(id: UUID) {
        sessions.removeValue(forKey: id)?.beginRemoval()
    }

    func removeAll() {
        sessions.values.forEach { $0.beginRemoval() }
        sessions.removeAll()
    }
}
