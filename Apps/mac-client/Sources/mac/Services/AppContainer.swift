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
    let recentFoldersService: RecentFoldersService
    let layoutPersistenceService: LayoutPersistenceService
    let commandSettingsStore: RepositoryCommandSettingsStore

    private let fileTreeService: FileTreeService
    private let fileWatchServiceFactory: (URL) -> FileWatchService
    private let gitStoreFactory: (URL?) -> GitStore
    private let worktreeListingServiceFactory: () -> any WorktreeListingService
    private let worktreeInfoProviderFactory: () -> WorktreeInfoProvider
    private let worktreeInfoWatcherFactory: () -> WorktreeInfoWatcher

    init(
        appSettings: AppSettings = AppSettings(),
        recentFoldersService: RecentFoldersService = RecentFoldersService(),
        layoutPersistenceService: LayoutPersistenceService = LayoutPersistenceService(),
        commandSettingsStore: RepositoryCommandSettingsStore = RepositoryCommandSettingsStore(),
        fileTreeService: FileTreeService = DefaultFileTreeService(),
        fileWatchServiceFactory: @escaping (URL) -> FileWatchService = {
            DefaultFileWatchService(rootURL: $0)
        },
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
        self.recentFoldersService = recentFoldersService
        self.layoutPersistenceService = layoutPersistenceService
        self.commandSettingsStore = commandSettingsStore
        self.fileTreeService = fileTreeService
        self.fileWatchServiceFactory = fileWatchServiceFactory
        self.gitStoreFactory = gitStoreFactory
        self.worktreeListingServiceFactory = worktreeListingServiceFactory
        self.worktreeInfoProviderFactory = worktreeInfoProviderFactory
        self.worktreeInfoWatcherFactory = worktreeInfoWatcherFactory
    }

    func makeFileTreeModel(rootURL: URL) -> FileTreeModel {
        FileTreeModel(
            rootURL: rootURL,
            settings: appSettings,
            fileTreeService: fileTreeService,
            fileWatchServiceFactory: fileWatchServiceFactory
        )
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
