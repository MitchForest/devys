// AppContainer.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

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

    private let fileTreeService: FileTreeService
    private let fileWatchServiceFactory: (URL) -> FileWatchService
    private let gitStoreFactory: (URL?) -> GitStore
    private let worktreeListingServiceFactory: () -> any WorktreeListingService
    private let worktreeInfoProviderFactory: () -> WorktreeInfoProvider
    private let worktreeInfoWatcherFactory: () -> WorktreeInfoWatcher
    @ObservationIgnored private var fileTreeModelsByRoot: [URL: FileTreeModel] = [:]

    init(
        appSettings: AppSettings = AppSettings(),
        recentRepositoriesService: RecentRepositoriesService = RecentRepositoriesService(),
        layoutPersistenceService: LayoutPersistenceService = LayoutPersistenceService(),
        repositorySettingsStore: RepositorySettingsStore = RepositorySettingsStore(),
        repositoryDiscoveryService: GitRepositoryDiscoveryService = GitRepositoryDiscoveryService(),
        workspaceCreationService: WorkspaceCreationService = WorkspaceCreationService(),
        fileTreeService: FileTreeService = DefaultFileTreeService(),
        sharedFileWatchRegistry: SharedFileWatchRegistry = SharedFileWatchRegistry(),
        fileWatchServiceFactory: ((URL) -> FileWatchService)? = nil,
        gitStoreFactory: @escaping (URL?) -> GitStore = { GitStore(projectFolder: $0) },
        worktreeListingServiceFactory: @escaping () -> any WorktreeListingService = {
            DefaultGitWorktreeService()
        },
        worktreeInfoProviderFactory: @escaping () -> WorktreeInfoProvider = {
            DefaultWorktreeInfoProvider()
        },
        worktreeInfoWatcherFactory: @escaping () -> WorktreeInfoWatcher = {
            DefaultWorktreeInfoWatcher()
        }
    ) {
        self.appSettings = appSettings
        self.recentRepositoriesService = recentRepositoriesService
        self.layoutPersistenceService = layoutPersistenceService
        self.repositorySettingsStore = repositorySettingsStore
        self.repositoryDiscoveryService = repositoryDiscoveryService
        self.workspaceCreationService = workspaceCreationService
        self.fileTreeService = fileTreeService
        self.fileWatchServiceFactory = fileWatchServiceFactory ?? {
            sharedFileWatchRegistry.makeService(rootURL: $0)
        }
        self.gitStoreFactory = gitStoreFactory
        self.worktreeListingServiceFactory = worktreeListingServiceFactory
        self.worktreeInfoProviderFactory = worktreeInfoProviderFactory
        self.worktreeInfoWatcherFactory = worktreeInfoWatcherFactory
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

    func releaseFileTreeModel(rootURL: URL) {
        let normalizedRootURL = rootURL.standardizedFileURL
        fileTreeModelsByRoot[normalizedRootURL]?.deactivate()
    }

    func makeGitStore(projectFolder: URL?) -> GitStore {
        gitStoreFactory(projectFolder)
    }

    func makeWorktreeManager() -> WorktreeManager {
        WorktreeManager(listingService: worktreeListingServiceFactory())
    }

    func makeWorktreeInfoStore() -> WorktreeInfoStore {
        WorktreeInfoStore(
            infoProvider: worktreeInfoProviderFactory(),
            infoWatcher: worktreeInfoWatcherFactory()
        )
    }
}
