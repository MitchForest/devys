import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("App Container Agent Launch Tests")
struct AppContainerAgentLaunchTests {
    @Test("Default agent launch options include explicit fallback search directories")
    @MainActor
    func defaultLaunchOptionsIncludeFallbackSearchDirectories() {
        let options = AppContainer().defaultAgentAdapterLaunchOptions()
        let paths = Set(options.fallbackSearchDirectories.map(normalizedPath(for:)))
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let environmentPath = options.environment["PATH"] ?? ""

        #expect(
            paths.contains(
                normalizedPath(homeDirectory.appending(path: ".local/bin", directoryHint: .isDirectory).path)
            )
        )
        #expect(
            paths.contains(
                normalizedPath(homeDirectory.appending(path: ".cargo/bin", directoryHint: .isDirectory).path)
            )
        )
        #expect(paths.contains(normalizedPath("/opt/homebrew/bin")))
        #expect(paths.contains(normalizedPath("/usr/local/bin")))
        #expect(paths.contains(normalizedPath("/usr/bin")))
        #expect(paths.contains(normalizedPath("/bin")))
        #expect(environmentPath.contains("/opt/homebrew/bin"))
        #expect(environmentPath.contains("/usr/local/bin"))
    }

    private func normalizedPath(for url: URL) -> String {
        normalizedPath(url.path(percentEncoded: false))
    }

    private func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return "/" }
        return "/" + trimmed
    }
}

@Suite("Window Workspace Catalog Store Tests")
struct WindowWorkspaceCatalogStoreTests {
    @Test("Catalog keeps repository-scoped workspace state and navigator ordering")
    @MainActor
    func repositoryScopedWorkspaceState() async throws {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/catalog-repo"))
        let primary = Worktree(
            name: "main",
            detail: ".",
            workingDirectory: repository.rootURL,
            repositoryRootURL: repository.rootURL
        )
        let feature = Worktree(
            name: "feature/perf",
            detail: "feature/perf",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-perf"),
            repositoryRootURL: repository.rootURL
        )
        let listingService = StubCatalogWorktreeListingService(
            worktreesByRepositoryRoot: [repository.id: [primary, feature]]
        )
        let catalog = WindowWorkspaceCatalogStore {
            WorktreeManager(listingService: listingService)
        }

        catalog.importRepository(repository)
        await catalog.refreshRepository(repositoryID: repository.id)
        catalog.selectWorkspace(feature.id, in: repository.id)
        catalog.setWorkspacePinned(feature.id, in: repository.id, isPinned: true)
        catalog.setWorkspaceDisplayName("Perf Branch", for: feature.id, in: repository.id)
        catalog.setWorkspaceArchived(primary.id, in: repository.id, isArchived: true)

        let visibleWorkspaceIDs = catalog.visibleNavigatorWorkspaces().map(\.workspace.id)
        let featureContext = try #require(catalog.workspaceContext(for: feature.id))

        #expect(catalog.selectedRepositoryID == repository.id)
        #expect(catalog.selectedWorkspaceID == feature.id)
        #expect(catalog.displayName(for: feature) == "Perf Branch")
        #expect(visibleWorkspaceIDs == [feature.id])
        #expect(catalog.worktreeState(for: feature.id)?.isPinned == true)
        #expect(featureContext.repository.id == repository.id)
        #expect(featureContext.worktree.id == feature.id)
    }

    @Test("Removing the active repository falls back to the remaining repository")
    @MainActor
    func removingActiveRepositoryFallsBackToRemainingSelection() {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/catalog-a"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/catalog-b"))
        let catalog = WindowWorkspaceCatalogStore {
            WorktreeManager(listingService: NoopWorktreeListingService())
        }

        catalog.importRepository(firstRepository)
        catalog.importRepository(secondRepository)
        catalog.removeRepository(secondRepository.id)

        #expect(catalog.selectedRepositoryID == firstRepository.id)
        #expect(catalog.hasRepositories)

        catalog.removeRepository(firstRepository.id)

        #expect(catalog.selectedRepositoryID == nil)
        #expect(catalog.selectedWorkspaceID == nil)
        #expect(!catalog.hasRepositories)
    }

    @Test("Moving repositories updates navigator order without changing selection")
    @MainActor
    func movingRepositoriesUpdatesOrder() {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/catalog-order-a"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/catalog-order-b"))
        let thirdRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/catalog-order-c"))
        let catalog = WindowWorkspaceCatalogStore {
            WorktreeManager(listingService: NoopWorktreeListingService())
        }

        catalog.importRepository(firstRepository)
        catalog.importRepository(secondRepository)
        catalog.importRepository(thirdRepository)

        #expect(catalog.repositories.map(\.id) == [firstRepository.id, secondRepository.id, thirdRepository.id])
        #expect(catalog.selectedRepositoryID == thirdRepository.id)

        catalog.moveRepository(thirdRepository.id, by: -1)

        #expect(catalog.repositories.map(\.id) == [firstRepository.id, thirdRepository.id, secondRepository.id])
        #expect(catalog.selectedRepositoryID == thirdRepository.id)

        catalog.moveRepository(firstRepository.id, by: 10)

        #expect(catalog.repositories.map(\.id) == [thirdRepository.id, secondRepository.id, firstRepository.id])
        #expect(catalog.selectedRepositoryID == thirdRepository.id)
    }

    @Test("Catalog distinguishes cached selections from unresolved repositories")
    @MainActor
    func cachedSelectionResolution() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/catalog-known"))
        let primary = Worktree(
            name: "main",
            detail: ".",
            workingDirectory: repository.rootURL,
            repositoryRootURL: repository.rootURL
        )
        let feature = Worktree(
            name: "feature/instant",
            detail: "feature/instant",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-instant"),
            repositoryRootURL: repository.rootURL
        )
        let listingService = StubCatalogWorktreeListingService(
            worktreesByRepositoryRoot: [repository.id: [primary, feature]]
        )
        let catalog = WindowWorkspaceCatalogStore {
            WorktreeManager(listingService: listingService)
        }

        catalog.importRepository(repository)

        #expect(!catalog.hasResolvedRepository(repository.id))
        #expect(!catalog.canResolveWorkspaceSelection(feature.id, in: repository.id))

        await catalog.refreshRepository(repositoryID: repository.id)
        catalog.selectWorkspace(feature.id, in: repository.id)

        #expect(catalog.hasResolvedRepository(repository.id))
        #expect(catalog.canResolveWorkspaceSelection(feature.id, in: repository.id))
        #expect(!catalog.canResolveWorkspaceSelection("/tmp/devys/catalog-known/missing", in: repository.id))
    }
}

@Suite("Worktree Runtime Registry Tests")
struct WorktreeRuntimeRegistryTests {
    @Test("Runtime registry preserves per-workspace shell state across activation changes")
    @MainActor
    func preservesWorkspaceShellStateAcrossActivationChanges() {
        let firstWorktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/runtime-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/runtime-repo")
        )
        let secondWorktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/runtime-b"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/runtime-repo")
        )
        let registry = WorktreeRuntimeRegistry()

        registry.activate(worktree: firstWorktree, filesSidebarVisible: false)
        let firstShellState = registry.shellState(for: firstWorktree)
        firstShellState.sidebarMode = .ports
        registry.persistShellState(firstShellState)

        registry.activate(worktree: secondWorktree, filesSidebarVisible: false)
        #expect(registry.activeWorkspaceID == secondWorktree.id)
        #expect(registry.containsRuntime(for: firstWorktree.id))
        #expect(registry.containsRuntime(for: secondWorktree.id))

        registry.activate(worktree: firstWorktree, filesSidebarVisible: false)
        #expect(registry.activeWorkspaceID == firstWorktree.id)
        #expect(registry.activeShellState?.sidebarMode == .ports)

        registry.discardWorkspace(firstWorktree.id)
        #expect(!registry.containsRuntime(for: firstWorktree.id))
        #expect(registry.activeWorkspaceID == nil)
        #expect(registry.storedShellStates[secondWorktree.id] != nil)
    }

    @Test("Runtime registry exposes the active runtime handle without catalog lookups")
    @MainActor
    func exposesActiveRuntimeHandle() {
        let firstWorktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/runtime-handle-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/runtime-handle-repo")
        )
        let secondWorktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/runtime-handle-b"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/runtime-handle-repo")
        )
        let registry = WorktreeRuntimeRegistry()
        registry.configure(container: AppContainer())

        registry.activate(worktree: firstWorktree, filesSidebarVisible: true)

        guard let firstRuntime = registry.activeRuntime else {
            Issue.record("Expected an active runtime for the first worktree")
            return
        }
        #expect(firstRuntime.workspaceID == firstWorktree.id)
        #expect(firstRuntime.worktree.id == firstWorktree.id)
        #expect(firstRuntime.shellState.workspaceID == firstWorktree.id)
        #expect(registry.runtimeHandle(for: firstWorktree.id)?.worktree.id == firstWorktree.id)

        registry.activate(worktree: secondWorktree, filesSidebarVisible: false)

        guard let secondRuntime = registry.activeRuntime else {
            Issue.record("Expected an active runtime for the second worktree")
            return
        }
        #expect(secondRuntime.workspaceID == secondWorktree.id)
        #expect(secondRuntime.worktree.id == secondWorktree.id)
        #expect(registry.runtimeHandle(for: firstWorktree.id)?.worktree.id == firstWorktree.id)
    }

    @Test("Runtime registry caches file-tree Git status index outside view render")
    @MainActor
    func cachesFileTreeGitStatusIndex() async throws {
        let fixture = try TestWorkspaceRuntimeRepositoryFixture()
        defer { fixture.cleanup() }

        let worktree = Worktree(
            workingDirectory: fixture.repositoryRoot,
            repositoryRootURL: fixture.repositoryRoot
        )
        let registry = WorktreeRuntimeRegistry()
        registry.configure(container: AppContainer())
        registry.activate(worktree: worktree, filesSidebarVisible: false)

        let fileNode = CEWorkspaceFileNode(
            url: fixture.repositoryRoot.appendingPathComponent("notes.txt"),
            isDirectory: false
        )

        #expect(registry.activeGitStore != nil)
        #expect(registry.activeGitStatusIndex?.summary(for: fileNode) == nil)

        await registry.hydrateGitRuntimeIfNeeded(for: worktree.id)

        let index = try #require(registry.activeGitStatusIndex)
        #expect(index.summary(for: fileNode)?.label == "?")
    }
}

private struct TestWorkspaceRuntimeRepositoryFixture {
    let repositoryRoot: URL

    init() throws {
        repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
        try runGit(arguments: ["init", "-b", "main"])
        try runGit(arguments: ["config", "user.name", "Devys Tests"])
        try runGit(arguments: ["config", "user.email", "tests@devys.local"])
        try "notes\n".write(
            to: repositoryRoot.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: repositoryRoot)
    }

    func runGit(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = repositoryRoot
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
