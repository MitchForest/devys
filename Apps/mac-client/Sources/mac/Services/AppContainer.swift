// AppContainer.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import ACPClientKit
import Foundation
import Observation
import Workspace
import Git

@MainActor
@Observable
final class AppContainer {
    let appSettings: AppSettings
    let recentRepositoriesService: RecentRepositoriesService
    let layoutPersistenceService: LayoutPersistenceService
    let repositorySettingsStore: RepositorySettingsStore
    let repositoryDiscoveryService: GitRepositoryDiscoveryService
    let workspaceCreationService: WorkspaceCreationService
    let agentAdapterLauncher: ACPAdapterLauncher
    let agentComposerSpeechService: any AgentComposerSpeechService

    private let fileTreeService: FileTreeService
    private let fileWatchServiceFactory: (URL) -> FileWatchService
    private let gitStoreFactory: (URL?) -> GitStore
    @ObservationIgnored private var fileTreeModelsByRoot: [URL: FileTreeModel] = [:]
    @ObservationIgnored private var fileIndexesByRoot: [URL: WorkspaceFileIndex] = [:]

    init(
        appSettings: AppSettings = AppSettings(),
        recentRepositoriesService: RecentRepositoriesService = RecentRepositoriesService(),
        layoutPersistenceService: LayoutPersistenceService = LayoutPersistenceService(),
        repositorySettingsStore: RepositorySettingsStore = RepositorySettingsStore(),
        repositoryDiscoveryService: GitRepositoryDiscoveryService = GitRepositoryDiscoveryService(),
        workspaceCreationService: WorkspaceCreationService = WorkspaceCreationService(),
        agentAdapterLauncher: ACPAdapterLauncher = ACPAdapterLauncher(),
        agentComposerSpeechService: any AgentComposerSpeechService = DefaultAgentComposerSpeechService(),
        fileTreeService: FileTreeService = DefaultFileTreeService(),
        sharedFileWatchRegistry: SharedFileWatchRegistry = SharedFileWatchRegistry(),
        fileWatchServiceFactory: ((URL) -> FileWatchService)? = nil,
        gitStoreFactory: @escaping (URL?) -> GitStore = { GitStore(projectFolder: $0) }
    ) {
        self.appSettings = appSettings
        self.recentRepositoriesService = recentRepositoriesService
        self.layoutPersistenceService = layoutPersistenceService
        self.repositorySettingsStore = repositorySettingsStore
        self.repositoryDiscoveryService = repositoryDiscoveryService
        self.workspaceCreationService = workspaceCreationService
        self.agentAdapterLauncher = agentAdapterLauncher
        self.agentComposerSpeechService = agentComposerSpeechService
        self.fileTreeService = fileTreeService
        self.fileWatchServiceFactory = fileWatchServiceFactory ?? {
            sharedFileWatchRegistry.makeService(rootURL: $0)
        }
        self.gitStoreFactory = gitStoreFactory
    }

    func makeFileTreeModel(rootURL: URL) -> FileTreeModel {
        let normalizedRootURL = rootURL.standardizedFileURL
        if let model = fileTreeModelsByRoot[normalizedRootURL] {
            return model
        }

        let model = FileTreeModel(
            rootURL: normalizedRootURL,
            settings: appSettings,
            fileTreeService: fileTreeService,
            fileWatchServiceFactory: fileWatchServiceFactory
        )
        fileTreeModelsByRoot[normalizedRootURL] = model
        return model
    }

    func makeGitStore(projectFolder: URL?) -> GitStore {
        gitStoreFactory(projectFolder)
    }

    func makeWorkspaceFileIndex(rootURL: URL) -> WorkspaceFileIndex {
        let normalizedRootURL = rootURL.standardizedFileURL
        if let existingIndex = fileIndexesByRoot[normalizedRootURL] {
            return existingIndex
        }

        let index = WorkspaceFileIndex(
            rootURL: normalizedRootURL
        ) { [weak self] in
            self?.appSettings.explorer ?? ExplorerSettings()
        }
        fileIndexesByRoot[normalizedRootURL] = index
        return index
    }

    func defaultAgentAdapterLaunchOptions(
        configuredExecutableURL: URL? = nil,
        currentDirectoryURL: URL? = nil
    ) -> ACPAdapterLaunchOptions {
        let fallbackSearchDirectories = fallbackAgentExecutableSearchDirectories()
        return ACPAdapterLaunchOptions(
            configuredExecutableURL: configuredExecutableURL,
            bundledExecutableSearchRoots: bundledAgentExecutableSearchRoots(),
            fallbackSearchDirectories: fallbackSearchDirectories,
            environment: agentAdapterEnvironment(
                fallbackSearchDirectories: fallbackSearchDirectories
            ),
            currentDirectoryURL: currentDirectoryURL,
            clientInfo: ACPImplementationInfo(
                name: "Devys",
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ),
            clientCapabilities: .standard(
                fileSystem: ACPFileSystemCapabilities(
                    readTextFile: true,
                    writeTextFile: true
                ),
                terminal: true
            )
        )
    }

    private func agentAdapterEnvironment(
        fallbackSearchDirectories: [URL]
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var pathEntries: [String] = []
        var seenEntries: Set<String> = []

        func appendPathEntries(_ rawPath: String?) {
            guard let rawPath else { return }
            for component in rawPath.split(separator: ":") {
                let path = String(component).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty,
                      seenEntries.insert(path).inserted else {
                    continue
                }
                pathEntries.append(path)
            }
        }

        appendPathEntries(environment["PATH"])
        for directory in fallbackSearchDirectories {
            appendPathEntries(directory.path(percentEncoded: false))
        }

        environment["PATH"] = pathEntries.joined(separator: ":")
        return environment
    }

    private func fallbackAgentExecutableSearchDirectories() -> [URL] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return [
            homeDirectory.appending(path: ".local/bin", directoryHint: .isDirectory),
            homeDirectory.appending(path: ".cargo/bin", directoryHint: .isDirectory),
            homeDirectory.appending(path: "bin", directoryHint: .isDirectory),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/sbin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/sbin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true),
            URL(fileURLWithPath: "/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/sbin", isDirectory: true),
            URL(fileURLWithPath: "/sbin", isDirectory: true),
        ]
    }

    private func bundledAgentExecutableSearchRoots() -> [URL] {
        let helperRoot = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers", directoryHint: .isDirectory)
        let sharedSupport = Bundle.main.sharedSupportURL
        return [helperRoot, sharedSupport]
            .compactMap { $0 }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
