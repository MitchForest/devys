// RepositoryCommandSettings.swift
// DevysCore - Per-repository command settings.

import Foundation

public struct RepositoryCommandSettings: Codable, Equatable, Sendable {
    public var runCommand: String?
    public var buildCommand: String?
    public var testCommand: String?

    public init(
        runCommand: String? = nil,
        buildCommand: String? = nil,
        testCommand: String? = nil
    ) {
        self.runCommand = runCommand
        self.buildCommand = buildCommand
        self.testCommand = testCommand
    }
}
