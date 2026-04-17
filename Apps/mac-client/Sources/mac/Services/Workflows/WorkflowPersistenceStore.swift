import AppFeatures
import Foundation
import Workspace

actor WorkflowPersistenceStore {
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadWorkspace(
        workspaceID _: Workspace.ID,
        rootURL: URL
    ) throws -> WorkflowWorkspaceSnapshot {
        let definitions = try loadDefinitions(rootURL: rootURL)
        let runs = try loadRuns(rootURL: rootURL)
        return WorkflowWorkspaceSnapshot(definitions: definitions, runs: runs)
    }

    func saveDefinition(
        _ definition: WorkflowDefinition,
        rootURL: URL
    ) throws {
        let definitionURL = definitionDirectory(
            definitionID: definition.id,
            rootURL: rootURL
        )
        let promptsURL = definitionURL.appendingPathComponent("prompts", isDirectory: true)
        try fileManager.createDirectory(at: promptsURL, withIntermediateDirectories: true)

        var persistedDefinition = definition
        persistedDefinition.workers = try persistedDefinition.workers.map { worker in
            try persist(worker: worker, promptsURL: promptsURL)
        }
        persistedDefinition.nodes = try persistedDefinition.nodes.map { node in
            try persist(node: node, promptsURL: promptsURL)
        }

        let data = try encoded(persistedDefinition)
        try data.write(
            to: definitionURL.appendingPathComponent("definition.json", isDirectory: false),
            options: .atomic
        )
    }

    func deleteDefinition(
        _ definitionID: String,
        rootURL: URL
    ) throws {
        let definitionURL = definitionDirectory(definitionID: definitionID, rootURL: rootURL)
        guard fileManager.fileExists(atPath: definitionURL.path) else { return }
        try fileManager.removeItem(at: definitionURL)
    }

    func saveRun(
        _ run: WorkflowRun,
        rootURL: URL
    ) throws {
        let runDirectoryURL = runsDirectory(rootURL: rootURL)
        try fileManager.createDirectory(at: runDirectoryURL, withIntermediateDirectories: true)
        let data = try encoded(run)
        try data.write(
            to: runDirectoryURL.appendingPathComponent("\(run.id.uuidString).json", isDirectory: false),
            options: .atomic
        )
    }

    func deleteRun(
        _ runID: UUID,
        rootURL: URL
    ) throws {
        let runURL = runsDirectory(rootURL: rootURL)
            .appendingPathComponent("\(runID.uuidString).json", isDirectory: false)
        guard fileManager.fileExists(atPath: runURL.path) else { return }
        try fileManager.removeItem(at: runURL)
    }

    func loadPlanSnapshot(
        planFilePath: String,
        rootURL: URL
    ) throws -> WorkflowPlanSnapshot {
        let trimmedPath = planFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw NSError(
                domain: "WorkflowPersistenceStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Workflow plan path is empty."]
            )
        }

        let planURL = resolvedPlanURL(path: trimmedPath, rootURL: rootURL)
        let content = try String(contentsOf: planURL, encoding: .utf8)
        return WorkflowPlanParser.parse(
            content: content,
            planFilePath: planURL.path
        )
    }

    func appendFollowUpTicket(
        _ request: WorkflowPlanAppendRequest,
        rootURL: URL
    ) throws -> WorkflowPlanSnapshot {
        let planURL = resolvedPlanURL(path: request.planFilePath, rootURL: rootURL)
        let existingContent = try String(contentsOf: planURL, encoding: .utf8)
        let updatedContent = try WorkflowPlanUpdater.appendFollowUp(
            content: existingContent,
            request: request
        )
        try updatedContent.write(to: planURL, atomically: true, encoding: .utf8)
        return WorkflowPlanParser.parse(
            content: updatedContent,
            planFilePath: planURL.path
        )
    }
}

private extension WorkflowPersistenceStore {
    func loadDefinitions(rootURL: URL) throws -> [WorkflowDefinition] {
        let definitionsURL = definitionsDirectory(rootURL: rootURL)
        guard fileManager.fileExists(atPath: definitionsURL.path) else { return [] }

        let entries = try fileManager.contentsOfDirectory(
            at: definitionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try entries.compactMap { entry in
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }
            let data = try Data(
                contentsOf: entry.appendingPathComponent("definition.json", isDirectory: false)
            )
            return try decoder.decode(WorkflowDefinition.self, from: data)
        }
    }

    func loadRuns(rootURL: URL) throws -> [WorkflowRun] {
        let runsURL = runsDirectory(rootURL: rootURL)
        guard fileManager.fileExists(atPath: runsURL.path) else { return [] }

        let entries = try fileManager.contentsOfDirectory(
            at: runsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return try entries
            .filter { $0.pathExtension == "json" }
            .map { entry in
                let data = try Data(contentsOf: entry)
                return try decoder.decode(WorkflowRun.self, from: data)
            }
    }

    func persist(
        worker: WorkflowWorker,
        promptsURL: URL
    ) throws -> WorkflowWorker {
        var persistedWorker = worker
        let promptRelativePath = promptRelativePath(
            id: worker.id,
            existingPath: worker.promptFilePath
        )
        let promptURL = promptsURL.appendingPathComponent(
            (promptRelativePath as NSString).lastPathComponent,
            isDirectory: false
        )
        try worker.prompt.write(to: promptURL, atomically: true, encoding: .utf8)
        persistedWorker.promptFilePath = "prompts/\(promptURL.lastPathComponent)"
        return persistedWorker
    }

    func persist(
        node: WorkflowNode,
        promptsURL: URL
    ) throws -> WorkflowNode {
        var persistedNode = node
        guard let override = workflowPersistedPromptText(node.promptOverride) else {
            persistedNode.promptOverride = nil
            persistedNode.promptFilePath = nil
            return persistedNode
        }

        let promptRelativePath = promptRelativePath(
            id: "node-\(node.id)",
            existingPath: node.promptFilePath
        )
        let promptURL = promptsURL.appendingPathComponent(
            (promptRelativePath as NSString).lastPathComponent,
            isDirectory: false
        )
        try override.write(to: promptURL, atomically: true, encoding: .utf8)
        persistedNode.promptOverride = override
        persistedNode.promptFilePath = "prompts/\(promptURL.lastPathComponent)"
        return persistedNode
    }

    func promptRelativePath(
        id: String,
        existingPath: String?
    ) -> String {
        let trimmedPath = existingPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedPath.isEmpty, !trimmedPath.hasPrefix("/") {
            return trimmedPath
        }
        return "\(id).md"
    }

    func encoded<T: Encodable>(_ value: T) throws -> Data {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    func definitionsDirectory(rootURL: URL) -> URL {
        WorkflowStorageLocations.definitionsRootURL(for: rootURL)
            .appendingPathComponent("definitions", isDirectory: true)
    }

    func definitionDirectory(
        definitionID: String,
        rootURL: URL
    ) -> URL {
        definitionsDirectory(rootURL: rootURL)
            .appendingPathComponent(definitionID, isDirectory: true)
    }

    func runsDirectory(rootURL: URL) -> URL {
        WorkflowStorageLocations.runsDirectory(for: rootURL, fileManager: fileManager)
    }

    func resolvedPlanURL(
        path: String,
        rootURL: URL
    ) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return rootURL.appendingPathComponent(path, isDirectory: false).standardizedFileURL
    }
}

private func workflowPersistedPromptText(
    _ value: String?
) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
