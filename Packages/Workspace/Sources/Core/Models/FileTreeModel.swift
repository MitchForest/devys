// FileTreeModel.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

/// Manages the file tree state for efficient virtualized rendering.
///
/// This model:
/// - Maintains the tree structure with lazy loading
/// - Provides a flattened list for LazyVStack rendering
/// - Handles expansion state and file watching
@MainActor
@Observable
public final class FileTreeModel {
    public static let itemsDeletedNotification = Notification.Name(
        "Workspace.FileTreeModel.ItemsDeleted"
    )
    public static let deletedURLsUserInfoKey = "deletedURLs"

    // MARK: - Properties
    
    /// Flattened nodes for virtualized rendering.
    public private(set) var flattenedNodes: [FlatFileNode] = []
    
    /// Currently selected URLs in the tree.
    public private(set) var selectedURLs: Set<URL> = []

    /// Primary focused URL for keyboard/context actions.
    public private(set) var focusedURL: URL?

    /// Anchor URL used for shift-range selection.
    public private(set) var selectionAnchorURL: URL?
    
    /// Whether the tree is loading.
    public private(set) var isLoading = false
    
    /// The root URL of the file tree.
    let rootURL: URL

    /// Settings model for explorer configuration.
    private let settings: AppSettings

    /// Service for file tree loading.
    private let fileTreeService: FileTreeService

    /// Factory for creating file watch services per root.
    private let fileWatchServiceFactory: (URL) -> FileWatchService
    
    // MARK: - Private Properties
    
    private var rootNode: CEWorkspaceFileNode?
    private var fileWatchService: FileWatchService?
    private var isWatchingActive = false
    private var loadedDirectories: Set<URL> = []
    private var invalidatedDirectories: Set<URL> = []
    private var expandedDirectories: Set<URL> = []
    
    // MARK: - Initialization
    
    /// Creates a new file tree model.
    /// - Parameter rootURL: The root folder URL.
    public convenience init(rootURL: URL, settings: AppSettings) {
        self.init(
            rootURL: rootURL,
            settings: settings,
            fileTreeService: DefaultFileTreeService()
        ) { SharedFileWatchRegistry.shared.makeService(rootURL: $0) }
    }

    public init(
        rootURL: URL,
        settings: AppSettings,
        fileTreeService: FileTreeService,
        fileWatchServiceFactory: @escaping (URL) -> FileWatchService
    ) {
        self.rootURL = URL(fileURLWithPath: rootURL.standardizedFileURL.path).standardizedFileURL
        self.settings = settings
        self.fileTreeService = fileTreeService
        self.fileWatchServiceFactory = fileWatchServiceFactory
    }

    deinit {
        MainActor.assumeIsolated {
            stopWatching()
        }
    }
    
    // MARK: - Public Methods
    
    /// Loads the file tree from the root URL.
    public func loadTree() async {
        isLoading = true
        defer { isLoading = false }

        await reloadRoot()
        await restoreExpandedSubdirectories()
        rebuildFlattenedList()
        startWatching()
    }

    /// Loads the file tree once, then reactivates watchers on later mounts.
    public func loadTreeIfNeeded() async {
        guard rootNode == nil else {
            activate()
            return
        }

        await loadTree()
    }

    /// Reattaches filesystem observation for an already-loaded tree.
    public func activate() {
        guard rootNode != nil else { return }
        startWatching()
    }

    /// Stops filesystem observation when no mounted UI is using the tree.
    public func deactivate() {
        stopWatching()
    }
    
    /// Toggles expansion state of a directory node.
    /// - Parameter node: The node to toggle.
    public func toggleExpansion(_ node: CEWorkspaceFileNode) {
        guard node.isDirectory else { return }

        let normalizedURL = normalize(node.url)

        if node.isExpanded {
            node.isExpanded = false
            expandedDirectories.remove(normalizedURL)
            rebuildFlattenedList()
            return
        }

        node.isExpanded = true
        expandedDirectories.insert(normalizedURL)

        Task {
            await ensureDirectoryLoaded(node, force: invalidatedDirectories.contains(normalizedURL))
            rebuildFlattenedList()
        }
    }
    
    /// Refreshes the file tree.
    public func refresh() async {
        await refreshLoadedDirectories()
    }
    
    /// Expands all ancestors of a given URL to reveal it in the tree.
    /// - Parameter url: The URL to reveal.
    public func revealURL(_ url: URL) async {
        guard let rootNode = rootNode else { return }
        let normalizedURL = normalize(url)

        // Find path from root to URL
        let relativePath = normalizedURL.path.replacingOccurrences(of: rootURL.path, with: "")
        let components = relativePath.split(separator: "/").map(String.init)

        var currentNode = rootNode

        for component in components {
            guard currentNode.isDirectory else { break }

            if !currentNode.isExpanded {
                currentNode.isExpanded = true
                expandedDirectories.insert(normalize(currentNode.url))
            }

            await ensureDirectoryLoaded(
                currentNode,
                force: invalidatedDirectories.contains(normalize(currentNode.url))
            )

            if let child = currentNode.children?.first(where: { $0.name == component }) {
                currentNode = child
            } else {
                break
            }
        }
        
        replaceSelection(with: currentNode.url)
        rebuildFlattenedList()
    }

    public func isSelected(_ url: URL) -> Bool {
        selectedURLs.contains(normalize(url))
    }

    public func replaceSelection(with url: URL) {
        let normalizedURL = normalize(url)
        selectedURLs = [normalizedURL]
        focusedURL = normalizedURL
        selectionAnchorURL = normalizedURL
    }

    public func toggleSelection(of url: URL) {
        let normalizedURL = normalize(url)

        if selectedURLs.contains(normalizedURL) {
            selectedURLs.remove(normalizedURL)
            if focusedURL == normalizedURL {
                focusedURL = selectedURLs.first
            }
            if selectionAnchorURL == normalizedURL {
                selectionAnchorURL = focusedURL
            }
            return
        }

        selectedURLs.insert(normalizedURL)
        focusedURL = normalizedURL
        if selectionAnchorURL == nil {
            selectionAnchorURL = normalizedURL
        }
    }

    public func selectRange(to url: URL, visibleURLs: [URL]) {
        let normalizedURL = normalize(url)
        let normalizedVisibleURLs = visibleURLs.map(normalize)
        let anchorURL = selectionAnchorURL ?? focusedURL ?? normalizedURL

        guard let anchorIndex = normalizedVisibleURLs.firstIndex(of: anchorURL),
              let targetIndex = normalizedVisibleURLs.firstIndex(of: normalizedURL) else {
            replaceSelection(with: normalizedURL)
            return
        }

        let lowerBound = min(anchorIndex, targetIndex)
        let upperBound = max(anchorIndex, targetIndex)
        selectedURLs = Set(normalizedVisibleURLs[lowerBound...upperBound])
        focusedURL = normalizedURL
        if selectionAnchorURL == nil {
            selectionAnchorURL = anchorURL
        }
    }

    public func clearSelection() {
        selectedURLs.removeAll()
        focusedURL = nil
        selectionAnchorURL = nil
    }
    
    // MARK: - Private Methods
    
    private func loadChildren(for node: CEWorkspaceFileNode) async -> [CEWorkspaceFileNode] {
        await fileTreeService.loadChildren(
            for: node,
            explorerSettings: settings.explorer
        )
    }
    
    private func rebuildFlattenedList() {
        var result: [FlatFileNode] = []
        
        func flatten(_ nodes: [CEWorkspaceFileNode]) {
            for (index, node) in nodes.enumerated() {
                let isLast = index == nodes.count - 1
                result.append(FlatFileNode(node: node, isLastChild: isLast))
                
                if node.isDirectory && node.isExpanded, let children = node.children {
                    flatten(children)
                }
            }
        }
        
        if let root = rootNode, let children = root.children {
            flatten(children)
        }

        flattenedNodes = result
        sanitizeSelectionState()
    }
    
    private func startWatching() {
        guard !isWatchingActive else { return }

        if let fileWatchService {
            fileWatchService.startWatching()
            isWatchingActive = true
            return
        }

        let watchService = fileWatchServiceFactory(rootURL)
        watchService.onFileChange = { [weak self] changeType, url in
            Task { @MainActor in
                await self?.handleFileChange(changeType, at: url)
            }
        }
        watchService.startWatching()
        fileWatchService = watchService
        isWatchingActive = true
    }

    private func stopWatching() {
        fileWatchService?.stopWatching()
        isWatchingActive = false
    }
    
    func handleFileChange(_ changeType: FileChangeType, at url: URL) async {
        let normalizedURL = normalize(url)

        if changeType == .overflow {
            await refreshLoadedDirectories()
            rebuildFlattenedList()
            return
        }

        let directoryURL = invalidationDirectoryURL(for: changeType, changedURL: normalizedURL)
        let normalizedDirectoryURL = normalize(directoryURL)

        if changeType == .deleted {
            pruneSubtree(at: normalizedURL)
            notifyDeletedItems([normalizedURL])
        }

        invalidatedDirectories.insert(normalizedDirectoryURL)

        if loadedDirectories.contains(normalizedDirectoryURL),
           let directoryNode = findNode(for: normalizedDirectoryURL) {
            await ensureDirectoryLoaded(
                directoryNode,
                force: true,
                allowDirectoryRetarget: changeType == .renamed
            )
        }

        rebuildFlattenedList()
    }
    
}

@MainActor
private extension FileTreeModel {
    func findNode(for url: URL) -> CEWorkspaceFileNode? {
        guard let rootNode = rootNode else { return nil }

        let normalizedURL = normalize(url)
        func search(_ node: CEWorkspaceFileNode) -> CEWorkspaceFileNode? {
            if normalize(node.url) == normalizedURL { return node }
            for child in node.children ?? [] {
                if let found = search(child) { return found }
            }
            return nil
        }

        return search(rootNode)
    }

    func reloadRoot() async {
        let root = await fileTreeService.buildTree(
            rootURL: rootURL,
            explorerSettings: settings.explorer
        )
        rootNode = root
        loadedDirectories = [rootURL]
        invalidatedDirectories.remove(rootURL)
        applyExpansionState(to: root)
    }

    func refreshLoadedDirectories() async {
        let expandedDirectoryURLs = expandedDirectories
            .filter { $0 != rootURL }
            .sorted { $0.pathComponents.count < $1.pathComponents.count }

        await reloadRoot()

        for directoryURL in expandedDirectoryURLs {
            guard let directoryNode = findNode(for: directoryURL) else {
                removeStateForMissingSubtree(at: directoryURL)
                continue
            }
            await ensureDirectoryLoaded(directoryNode, force: true)
        }

        rebuildFlattenedList()
    }

    func restoreExpandedSubdirectories() async {
        let expandedDirectoryURLs = expandedDirectories
            .filter { $0 != rootURL }
            .sorted { $0.pathComponents.count < $1.pathComponents.count }

        for directoryURL in expandedDirectoryURLs {
            guard let directoryNode = findNode(for: directoryURL) else { continue }
            await ensureDirectoryLoaded(directoryNode, force: true)
        }
    }

    func ensureDirectoryLoaded(
        _ node: CEWorkspaceFileNode,
        force: Bool = false,
        allowDirectoryRetarget: Bool = false
    ) async {
        let normalizedURL = normalize(node.url)
        let shouldLoad = force
            || node.children == nil
            || !loadedDirectories.contains(normalizedURL)
            || invalidatedDirectories.contains(normalizedURL)
        guard shouldLoad else { return }

        let fetchedChildren = await loadChildren(for: node)
        reconcileChildren(
            of: node,
            with: fetchedChildren,
            allowDirectoryRetarget: allowDirectoryRetarget
        )
        loadedDirectories.insert(normalizedURL)
        invalidatedDirectories.remove(normalizedURL)
    }

    func reconcileChildren(
        of directoryNode: CEWorkspaceFileNode,
        with fetchedChildren: [CEWorkspaceFileNode],
        allowDirectoryRetarget: Bool
    ) {
        let previousChildren = directoryNode.children ?? []
        var previousByURL = Dictionary(
            uniqueKeysWithValues: previousChildren.map { (normalize($0.url), $0) }
        )
        let normalizedFetchedChildren = fetchedChildren.map { child -> CEWorkspaceFileNode in
            child.url = normalize(child.url)
            child.parent = directoryNode
            return child
        }

        if allowDirectoryRetarget,
           let retargeted = retargetDirectoryIfNeeded(
            previousChildren: previousChildren,
            fetchedChildren: normalizedFetchedChildren,
            parent: directoryNode
           ) {
            previousByURL[normalize(retargeted.url)] = retargeted
        }

        let reconciledChildren = normalizedFetchedChildren.map { fetchedChild -> CEWorkspaceFileNode in
            let normalizedChildURL = normalize(fetchedChild.url)
            if let existing = previousByURL[normalizedChildURL] {
                existing.parent = directoryNode
                existing.isExpanded = expandedDirectories.contains(normalizedChildURL)
                return existing
            }

            fetchedChild.isExpanded = expandedDirectories.contains(normalizedChildURL)
            return fetchedChild
        }

        directoryNode.children = reconciledChildren
    }

    func retargetDirectoryIfNeeded(
        previousChildren: [CEWorkspaceFileNode],
        fetchedChildren: [CEWorkspaceFileNode],
        parent: CEWorkspaceFileNode
    ) -> CEWorkspaceFileNode? {
        let previousURLs = Set(previousChildren.map { normalize($0.url) })
        let fetchedURLs = Set(fetchedChildren.map { normalize($0.url) })

        let removedDirectories = previousChildren.filter { child in
            child.isDirectory && !fetchedURLs.contains(normalize(child.url))
        }
        let addedDirectories = fetchedChildren.filter { child in
            child.isDirectory && !previousURLs.contains(normalize(child.url))
        }

        guard removedDirectories.count == 1,
              addedDirectories.count == 1,
              let oldDirectory = removedDirectories.first,
              let newDirectory = addedDirectories.first else {
            return nil
        }

        let oldURL = normalize(oldDirectory.url)
        let newURL = normalize(newDirectory.url)
        guard oldURL.deletingLastPathComponent() == newURL.deletingLastPathComponent() else {
            return nil
        }

        retargetSubtree(oldDirectory, from: oldURL, to: newURL)
        oldDirectory.parent = parent
        oldDirectory.isExpanded = expandedDirectories.contains(newURL)
        retargetTrackedDirectoryState(from: oldURL, to: newURL)
        return oldDirectory
    }

    func retargetSubtree(_ node: CEWorkspaceFileNode, from oldBaseURL: URL, to newBaseURL: URL) {
        let currentURL = normalize(node.url)
        node.url = retargetURL(currentURL, from: oldBaseURL, to: newBaseURL)
        for child in node.children ?? [] {
            retargetSubtree(child, from: oldBaseURL, to: newBaseURL)
        }
    }

    func retargetTrackedDirectoryState(from oldBaseURL: URL, to newBaseURL: URL) {
        loadedDirectories = retargetURLs(in: loadedDirectories, from: oldBaseURL, to: newBaseURL)
        invalidatedDirectories = retargetURLs(
            in: invalidatedDirectories,
            from: oldBaseURL,
            to: newBaseURL
        )
        expandedDirectories = retargetURLs(
            in: expandedDirectories,
            from: oldBaseURL,
            to: newBaseURL
        )
        selectedURLs = retargetURLs(in: selectedURLs, from: oldBaseURL, to: newBaseURL)
        if let focusedURL,
           isWithinPath(oldBaseURL, candidate: normalize(focusedURL)) {
            self.focusedURL = retargetURL(normalize(focusedURL), from: oldBaseURL, to: newBaseURL)
        }
        if let selectionAnchorURL,
           isWithinPath(oldBaseURL, candidate: normalize(selectionAnchorURL)) {
            self.selectionAnchorURL = retargetURL(
                normalize(selectionAnchorURL),
                from: oldBaseURL,
                to: newBaseURL
            )
        }
    }

    func retargetURLs(in urls: Set<URL>, from oldBaseURL: URL, to newBaseURL: URL) -> Set<URL> {
        Set(urls.map { url in
            guard isWithinPath(oldBaseURL, candidate: normalize(url)) else { return normalize(url) }
            return retargetURL(normalize(url), from: oldBaseURL, to: newBaseURL)
        })
    }

    func retargetURL(_ url: URL, from oldBaseURL: URL, to newBaseURL: URL) -> URL {
        let oldPath = oldBaseURL.path
        let newPath = newBaseURL.path
        let candidatePath: String
        if url == oldBaseURL {
            candidatePath = newPath
        } else {
            candidatePath = url.path.replacingOccurrences(
                of: oldPath,
                with: newPath,
                options: .anchored
            )
        }
        return URL(fileURLWithPath: candidatePath).standardizedFileURL
    }

    func pruneSubtree(at url: URL) {
        guard let node = findNode(for: url),
              let parent = node.parent else {
            removeStateForMissingSubtree(at: url)
            return
        }

        parent.children?.removeAll { normalize($0.url) == url }
        removeStateForMissingSubtree(at: url)
    }

    func removeStateForMissingSubtree(at url: URL) {
        loadedDirectories = removeSubtreeURLs(from: loadedDirectories, under: url)
        invalidatedDirectories = removeSubtreeURLs(from: invalidatedDirectories, under: url)
        expandedDirectories = removeSubtreeURLs(from: expandedDirectories, under: url)
        selectedURLs = removeSubtreeURLs(from: selectedURLs, under: url)

        if let focusedURL,
           isWithinPath(url, candidate: normalize(focusedURL)) {
            self.focusedURL = nil
        }

        if let selectionAnchorURL,
           isWithinPath(url, candidate: normalize(selectionAnchorURL)) {
            self.selectionAnchorURL = nil
        }

        sanitizeSelectionState()
    }

    func removeSubtreeURLs(from urls: Set<URL>, under baseURL: URL) -> Set<URL> {
        Set(urls.filter { !isWithinPath(baseURL, candidate: normalize($0)) })
    }

    func applyExpansionState(to node: CEWorkspaceFileNode) {
        let normalizedURL = normalize(node.url)
        node.isExpanded = expandedDirectories.contains(normalizedURL)
        for child in node.children ?? [] {
            child.parent = node
            applyExpansionState(to: child)
        }
    }

    func invalidationDirectoryURL(for changeType: FileChangeType, changedURL: URL) -> URL {
        if changeType == .modified,
           let node = findNode(for: changedURL),
           node.isDirectory {
            return normalize(node.url)
        }
        return normalize(changedURL.deletingLastPathComponent())
    }

    func isWithinPath(_ baseURL: URL, candidate: URL) -> Bool {
        let basePath = baseURL.path
        let candidatePath = candidate.path
        return candidatePath == basePath || candidatePath.hasPrefix(basePath + "/")
    }

    func normalize(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path).standardizedFileURL
    }

    func sanitizeSelectionState() {
        selectedURLs = Set(
            selectedURLs
                .map(normalize)
                .filter { selectedURL in
                    guard rootNode != nil else { return true }
                    return findNode(for: selectedURL) != nil
                }
        )

        if let focusedURL {
            let normalizedFocusedURL = normalize(focusedURL)
            self.focusedURL = selectedURLs.contains(normalizedFocusedURL)
                ? normalizedFocusedURL
                : selectedURLs.first
        }

        if let selectionAnchorURL {
            let normalizedAnchorURL = normalize(selectionAnchorURL)
            self.selectionAnchorURL = selectedURLs.contains(normalizedAnchorURL)
                ? normalizedAnchorURL
                : focusedURL
        }
    }

    func notifyDeletedItems(_ urls: [URL]) {
        NotificationCenter.default.post(
            name: Self.itemsDeletedNotification,
            object: self,
            userInfo: [Self.deletedURLsUserInfoKey: urls]
        )
    }
}
