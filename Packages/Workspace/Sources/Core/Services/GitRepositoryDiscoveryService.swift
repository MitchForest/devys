// GitRepositoryDiscoveryService.swift
// Resolve project roots from user-selected filesystem paths.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

public enum GitRepositoryDiscoveryError: LocalizedError, Sendable {
    case selectionMissing(URL)
    case selectionNotDirectory(URL)
    case selectionUnavailable(URL, message: String)

    public var errorDescription: String? {
        switch self {
        case .selectionMissing(let url):
            return "No project was found at \(url.path)."
        case .selectionNotDirectory(let url):
            return "Devys can only open folders. \(url.path) is not a directory."
        case .selectionUnavailable(let url, let message):
            return "Failed to open \(url.path): \(message)"
        }
    }
}

public struct GitRepositoryDiscoveryService: Sendable {
    public init() {}

    public func resolveRepository(from selectedURL: URL) async throws -> Repository {
        let normalizedSelection = selectedURL.standardizedFileURL
        try validateSelection(normalizedSelection)

        guard let repositoryRoot = try inspectGitRoot(for: normalizedSelection) else {
            return Repository(rootURL: normalizedSelection, sourceControl: .none)
        }

        return Repository(rootURL: repositoryRoot, sourceControl: .git)
    }

    private func validateSelection(_ selectedURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory) else {
            throw GitRepositoryDiscoveryError.selectionMissing(selectedURL)
        }
        guard isDirectory.boolValue else {
            throw GitRepositoryDiscoveryError.selectionNotDirectory(selectedURL)
        }
    }

    private func inspectGitRoot(for selectedURL: URL) throws -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", selectedURL.path, "rev-parse", "--show-toplevel"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        let output = String(
            bytes: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(
            bytes: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            if errorOutput.localizedCaseInsensitiveContains("not a git repository") || errorOutput.isEmpty {
                return nil
            }
            throw GitRepositoryDiscoveryError.selectionUnavailable(selectedURL, message: errorOutput)
        }

        guard !output.isEmpty else { return nil }
        return URL(fileURLWithPath: output).standardizedFileURL
    }
}
