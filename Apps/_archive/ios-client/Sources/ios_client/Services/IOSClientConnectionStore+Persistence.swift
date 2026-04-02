import Foundation

extension IOSClientConnectionStore {
    var normalizedServerURL: URL? {
        URL(string: serverURLText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var normalizedWorkspacePath: String? {
        let trimmed = workspacePathText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
