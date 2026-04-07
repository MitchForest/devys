// GitRepositoryDiscoveryService.swift
// Resolve repository roots from user-selected filesystem paths.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

public enum GitRepositoryDiscoveryError: LocalizedError, Sendable {
    case notRepository(URL)
    case commandFailed(URL, message: String)
    case invalidOutput(URL)

    public var errorDescription: String? {
        switch self {
        case .notRepository(let url):
            return "No Git repository found at \(url.path)."
        case .commandFailed(let url, let message):
            return "Failed to inspect repository at \(url.path): \(message)"
        case .invalidOutput(let url):
            return "Git returned an invalid repository root for \(url.path)."
        }
    }
}

public struct GitRepositoryDiscoveryService: Sendable {
    public init() {}

    public func resolveRepository(from selectedURL: URL) async throws -> Repository {
        let normalizedSelection = selectedURL.standardizedFileURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", normalizedSelection.path, "rev-parse", "--show-toplevel"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw GitRepositoryDiscoveryError.commandFailed(normalizedSelection, message: error.localizedDescription)
        }

        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(bytes: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(bytes: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            if errorOutput.contains("not a git repository") {
                throw GitRepositoryDiscoveryError.notRepository(normalizedSelection)
            }
            throw GitRepositoryDiscoveryError.commandFailed(
                normalizedSelection,
                message: errorOutput.isEmpty ? "git rev-parse failed" : errorOutput
            )
        }

        guard !output.isEmpty else {
            throw GitRepositoryDiscoveryError.invalidOutput(normalizedSelection)
        }

        return Repository(rootURL: URL(fileURLWithPath: output))
    }
}
