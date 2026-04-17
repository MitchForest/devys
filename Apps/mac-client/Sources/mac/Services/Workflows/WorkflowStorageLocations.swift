import CryptoKit
import Foundation

enum WorkflowStorageLocations {
    static func definitionsRootURL(
        for rootURL: URL
    ) -> URL {
        rootURL
            .appendingPathComponent(".devys", isDirectory: true)
            .appendingPathComponent("workflows", isDirectory: true)
    }

    static func runtimeRootURL(
        for rootURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Devys", isDirectory: true)
            .appendingPathComponent("WorkflowRuns", isDirectory: true)

        return (baseURL ?? fileManager.temporaryDirectory)
            .appendingPathComponent(worktreeKey(for: rootURL), isDirectory: true)
    }

    static func runsDirectory(
        for rootURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        runtimeRootURL(for: rootURL, fileManager: fileManager)
            .appendingPathComponent("runs", isDirectory: true)
    }

    static func promptsDirectory(
        for rootURL: URL,
        runID: UUID,
        fileManager: FileManager = .default
    ) -> URL {
        runtimeRootURL(for: rootURL, fileManager: fileManager)
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
            .appendingPathComponent("prompts", isDirectory: true)
    }

    private static func worktreeKey(
        for rootURL: URL
    ) -> String {
        let path = rootURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
