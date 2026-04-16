import AppFeatures
import Dependencies
import Foundation
import Git
import Split
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

@Suite("Workspace Catalog Client Tests")
struct WorkspaceCatalogClientTests {
    @Test("Refresh client rebuilds repository worktrees from git service")
    @MainActor
    func refreshClientRebuildsRepositorySnapshot() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/catalog-repo"))
        let feature = Worktree(
            name: "feature/perf",
            detail: "feature/perf",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-perf"),
            repositoryRootURL: repository.rootURL
        )
        let client = WorkspaceCatalogRefreshClient.live(
            gitWorktreeService: StubGitWorktreeService(
                worktreesByRepositoryRoot: [repository.id: [feature]]
            )
        )
        let snapshot = WindowFeature.RepositoryCatalogSnapshot(
            repositories: [repository],
            worktreesByRepository: [repository.id: []],
            workspaceStatesByID: [
                feature.id: WorktreeState(worktreeId: feature.id, isPinned: true)
            ]
        )
        let refreshed = await client.refreshRepositories(snapshot, [repository.id])

        #expect(refreshed.repositories == [repository])
        #expect(refreshed.worktreesByRepository[repository.id] == [feature])
        #expect(refreshed.workspaceStatesByID[feature.id]?.isPinned == true)
    }

    @Test("Refresh client falls back to a repository-root worktree when git returns none")
    @MainActor
    func refreshClientFallsBackToRepositoryRoot() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/catalog-empty"))
        let client = WorkspaceCatalogRefreshClient.live(
            gitWorktreeService: StubGitWorktreeService(worktreesByRepositoryRoot: [repository.id: []])
        )

        let refreshed = await client.refreshRepositories(
            WindowFeature.RepositoryCatalogSnapshot(repositories: [repository]),
            [repository.id]
        )

        #expect(refreshed.worktreesByRepository[repository.id] == [
            Worktree(
                workingDirectory: repository.rootURL,
                repositoryRootURL: repository.rootURL,
                name: repository.rootURL.lastPathComponent,
                detail: "."
            )
        ])
    }

    @Test("Persistence client writes repositories and worktree states through workspace services")
    @MainActor
    func persistenceClientWritesThroughWorkspaceServices() {
        let suiteName = "com.devys.tests.catalog-client.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/catalog-persist"))
        let workspaceState = WorktreeState(
            worktreeId: "/tmp/devys/catalog-persist/feature",
            isPinned: true,
            displayNameOverride: "Perf Branch"
        )
        let repositoryPersistenceService = UserDefaultsRepositoryPersistenceService(
            userDefaults: userDefaults
        )
        let worktreePersistenceService = UserDefaultsWorktreePersistenceService(
            userDefaults: userDefaults
        )
        let client = WorkspaceCatalogPersistenceClient.live(
            repositoryPersistenceService: repositoryPersistenceService,
            worktreePersistenceService: worktreePersistenceService
        )

        client.saveRepositories([repository])
        client.saveWorkspaceStates([workspaceState])

        #expect(repositoryPersistenceService.loadRepositories() == [repository])
        #expect(client.loadWorkspaceStates() == [workspaceState])
    }
}

@Suite("Worktree Runtime Registry Tests")
struct WorktreeRuntimeRegistryTests {
    @Test("Runtime registry preserves per-workspace runtimes across activation changes")
    @MainActor
    func preservesRuntimeAcrossActivationChanges() throws {
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
        let firstPool = try #require(registry.editorSessionPool(for: firstWorktree.id))
        let firstPoolIdentity = ObjectIdentifier(firstPool)

        registry.activate(worktree: secondWorktree, filesSidebarVisible: false)
        #expect(registry.activeWorkspaceID == secondWorktree.id)
        #expect(registry.containsRuntime(for: firstWorktree.id))
        #expect(registry.containsRuntime(for: secondWorktree.id))

        registry.activate(worktree: firstWorktree, filesSidebarVisible: false)
        #expect(registry.activeWorkspaceID == firstWorktree.id)
        let activePool = try #require(registry.editorSessionPool(for: firstWorktree.id))
        #expect(ObjectIdentifier(activePool) == firstPoolIdentity)

        registry.discardWorkspace(firstWorktree.id)
        #expect(!registry.containsRuntime(for: firstWorktree.id))
        #expect(registry.activeWorkspaceID == nil)
        #expect(registry.worktree(for: secondWorktree.id)?.id == secondWorktree.id)
    }

    @Test("Runtime registry exposes focused active workspace accessors without catalog lookups")
    @MainActor
    func exposesFocusedActiveWorkspaceAccessors() {
        let firstWorktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/runtime-handle-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/runtime-handle-repo")
        )
        let secondWorktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/runtime-handle-b"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/runtime-handle-repo")
        )
        let registry = WorktreeRuntimeRegistry()
        let container = AppContainer()
        registry.configure(
            makeGitStore: { workingDirectory in
                guard let workingDirectory else { return nil }
                return container.makeGitStore(projectFolder: workingDirectory)
            },
            makeFileTreeModel: { rootURL in
                container.makeFileTreeModel(rootURL: rootURL)
            }
        )

        registry.activate(worktree: firstWorktree, filesSidebarVisible: true)

        #expect(registry.activeWorkspaceID == firstWorktree.id)
        #expect(registry.activeWorktree?.id == firstWorktree.id)
        #expect(registry.worktree(for: firstWorktree.id)?.id == firstWorktree.id)
        #expect(registry.editorSessionPool(for: firstWorktree.id) != nil)
        #expect(registry.activeGitStore != nil)

        registry.activate(worktree: secondWorktree, filesSidebarVisible: false)

        #expect(registry.activeWorkspaceID == secondWorktree.id)
        #expect(registry.activeWorktree?.id == secondWorktree.id)
        #expect(registry.worktree(for: firstWorktree.id)?.id == firstWorktree.id)
    }

    @Test("Runtime registry caches file-tree Git status index outside view render")
    @MainActor
    func cachesFileTreeGitStatusIndex() async throws {
        try await withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 1_234_567)
        } operation: {
            let fixture = try TestWorkspaceRuntimeRepositoryFixture()
            defer { fixture.cleanup() }

            let worktree = Worktree(
                workingDirectory: fixture.repositoryRoot,
                repositoryRootURL: fixture.repositoryRoot
            )
            let registry = WorktreeRuntimeRegistry()
            let container = AppContainer()
            registry.configure(
                makeGitStore: { workingDirectory in
                    guard let workingDirectory else { return nil }
                    return container.makeGitStore(projectFolder: workingDirectory)
                },
                makeFileTreeModel: { rootURL in
                    container.makeFileTreeModel(rootURL: rootURL)
                }
            )
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
}

private struct StubGitWorktreeService: GitWorktreeService {
    let worktreesByRepositoryRoot: [Repository.ID: [Worktree]]

    func repositoryRoot(for url: URL) async throws -> URL {
        url.standardizedFileURL
    }

    func listWorktrees(for repositoryRoot: URL) async throws -> [Worktree] {
        worktreesByRepositoryRoot[repositoryRoot.standardizedFileURL.path] ?? []
    }

    func createWorktree(
        at path: URL,
        branchName: String,
        baseRef: String?,
        in repositoryRoot: URL
    ) async throws -> Worktree {
        _ = baseRef
        return Worktree(
            name: branchName,
            detail: ".",
            workingDirectory: path,
            repositoryRootURL: repositoryRoot
        )
    }

    func removeWorktree(_ worktree: Worktree, force: Bool) async throws {
        _ = worktree
        _ = force
    }

    func pruneWorktrees(in repositoryRoot: URL) async throws {
        _ = repositoryRoot
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
