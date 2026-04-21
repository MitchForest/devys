import CryptoKit
import Foundation

enum ReviewStorageLocations {
    static func reviewTriggerInboxDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        runtimeBaseURL(fileManager: fileManager)
            .appendingPathComponent("ReviewTriggerInbox", isDirectory: true)
    }

    static func runsDirectory(
        for rootURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        runtimeRootURL(for: rootURL, fileManager: fileManager)
            .appendingPathComponent("runs", isDirectory: true)
    }

    static func runDirectory(
        for rootURL: URL,
        runID: UUID,
        fileManager: FileManager = .default
    ) -> URL {
        runsDirectory(for: rootURL, fileManager: fileManager)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
    }

    static func runtimeRootURL(
        for rootURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        runtimeBaseURL(fileManager: fileManager)
            .appendingPathComponent("ReviewRuns", isDirectory: true)
            .appendingPathComponent(worktreeKey(for: rootURL), isDirectory: true)
    }

    static func promptsDirectory(
        for rootURL: URL,
        runID: UUID,
        fileManager: FileManager = .default
    ) -> URL {
        runDirectory(for: rootURL, runID: runID, fileManager: fileManager)
            .appendingPathComponent("prompts", isDirectory: true)
    }

    private static func worktreeKey(
        for rootURL: URL
    ) -> String {
        let path = rootURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func runtimeBaseURL(
        fileManager: FileManager
    ) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Devys", isDirectory: true)

        return baseURL ?? fileManager.temporaryDirectory
    }
}
