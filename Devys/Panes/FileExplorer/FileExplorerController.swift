import AppKit
import SwiftUI

/// Protocol for file explorer delegate callbacks
@MainActor
public protocol FileExplorerDelegate: AnyObject {
    /// Called when a file is double-clicked (should open in editor)
    func fileExplorer(_ controller: FileExplorerController, didRequestOpen url: URL)

    /// Called when selection changes
    func fileExplorer(_ controller: FileExplorerController, didSelectItems urls: [URL])
}

/// AppKit controller hosting NSOutlineView for efficient file tree rendering.
///
/// Uses NSOutlineView for native macOS performance with large directories.
/// Supports lazy loading, expansion state, and file system watching.
@MainActor
public final class FileExplorerController: NSViewController {
    /// Root URL being displayed
    public var rootURL: URL? {
        didSet {
            if rootURL != oldValue {
                reloadRoot()
            }
        }
    }

    /// Delegate for callbacks
    public weak var delegate: FileExplorerDelegate?

    /// Whether to show hidden files
    public var showHiddenFiles: Bool = false {
        didSet {
            if showHiddenFiles != oldValue {
                reloadRoot()
            }
        }
    }

    /// Root file item
    private var rootItem: FileItem?

    /// The outline view
    private var outlineView: NSOutlineView!

    /// Scroll view containing the outline
    private var scrollView: NSScrollView!

    /// File system watcher
    private var watcher: FileSystemWatcher?

    /// Watch task
    private var watchTask: Task<Void, Never>?

    // MARK: - Lifecycle

    public override func loadView() {
        // Create scroll view
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Create outline view
        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .default
        outlineView.indentationPerLevel = 16
        outlineView.autoresizesOutlineColumn = true
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.usesAlternatingRowBackgroundColors = false

        // Create column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        // Set data source and delegate
        outlineView.dataSource = self
        outlineView.delegate = self

        // Double-click action
        outlineView.target = self
        outlineView.doubleAction = #selector(handleDoubleClick)

        // Add to scroll view
        scrollView.documentView = outlineView

        self.view = scrollView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Set up context menu
        outlineView.menu = createContextMenu()

        // Load initial content
        reloadRoot()
    }

    // MARK: - Public Methods

    /// Reload the file tree from disk
    public func reloadRoot() {
        stopWatching()

        guard let url = rootURL else {
            rootItem = nil
            outlineView?.reloadData()
            return
        }

        rootItem = FileItem(url: url)
        rootItem?.loadChildren(showHidden: showHiddenFiles)
        rootItem?.isExpanded = true

        outlineView?.reloadData()

        // Expand root
        if let root = rootItem {
            outlineView?.expandItem(root)
        }

        // Start watching
        startWatching()
    }

    /// Refresh a specific item
    public func refreshItem(_ item: FileItem) {
        item.reloadChildren(showHidden: showHiddenFiles)
        outlineView.reloadItem(item, reloadChildren: true)
    }

    // MARK: - File System Watching

    private func startWatching() {
        guard let url = rootURL else { return }

        watcher = FileSystemWatcher(rootURL: url)

        watchTask = Task {
            guard let watcher = watcher else { return }

            for await events in await watcher.startWatching() {
                await handleFileSystemEvents(events)
            }
        }
    }

    private func stopWatching() {
        watchTask?.cancel()
        watchTask = nil

        Task {
            await watcher?.stopWatching()
            watcher = nil
        }
    }

    private func handleFileSystemEvents(_ events: [FileChangeEvent]) async {
        // Find affected items and refresh their parents
        var affectedParents: Set<URL> = []

        for event in events {
            let parentURL = event.url.deletingLastPathComponent()
            affectedParents.insert(parentURL)
        }

        // Refresh each affected parent
        for parentURL in affectedParents {
            if let item = findItem(for: parentURL) {
                refreshItem(item)
            }
        }
    }

    /// Find a FileItem for a given URL
    private func findItem(for url: URL) -> FileItem? {
        guard let root = rootItem else { return nil }

        if root.url == url {
            return root
        }

        return findItem(for: url, in: root)
    }

    private func findItem(for url: URL, in parent: FileItem) -> FileItem? {
        guard let children = parent.children else { return nil }

        for child in children {
            if child.url == url {
                return child
            }

            if url.path.hasPrefix(child.url.path + "/"), child.isDirectory {
                return findItem(for: url, in: child)
            }
        }

        return nil
    }

    // MARK: - Actions

    @objc private func handleDoubleClick() {
        let row = outlineView.clickedRow
        guard row >= 0,
              let item = outlineView.item(atRow: row) as? FileItem else {
            return
        }

        if item.isDirectory {
            // Toggle expansion
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
        } else {
            // Open file
            delegate?.fileExplorer(self, didRequestOpen: item.url)
        }
    }

    // MARK: - Context Menu

    private func createContextMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "New File...", action: #selector(newFile), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "New Folder...", action: #selector(newFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Rename...", action: #selector(renameItem), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Delete", action: #selector(deleteItems), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy Path", action: #selector(copyPath), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshTree), keyEquivalent: ""))

        for item in menu.items {
            item.target = self
        }

        return menu
    }

    @objc private func newFile() {
        guard let targetURL = contextTargetDirectory() else { return }

        let alert = NSAlert()
        alert.messageText = "New File"
        alert.informativeText = "Enter the file name:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = "untitled.swift"
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let fileName = input.stringValue
            let fileURL = targetURL.appendingPathComponent(fileName)

            do {
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                showError("Failed to create file: \(error.localizedDescription)")
            }
        }
    }

    @objc private func newFolder() {
        guard let targetURL = contextTargetDirectory() else { return }

        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Enter the folder name:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = "New Folder"
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let folderName = input.stringValue
            let folderURL = targetURL.appendingPathComponent(folderName)

            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            } catch {
                showError("Failed to create folder: \(error.localizedDescription)")
            }
        }
    }

    @objc private func renameItem() {
        guard let item = selectedItems().first else { return }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter the new name:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = item.name
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = input.stringValue
            let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)

            do {
                try FileManager.default.moveItem(at: item.url, to: newURL)
            } catch {
                showError("Failed to rename: \(error.localizedDescription)")
            }
        }
    }

    @objc private func deleteItems() {
        let items = selectedItems()
        guard !items.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \(items.count) item(s)?"
        alert.informativeText = "This will move them to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            for item in items {
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                } catch {
                    showError("Failed to delete \(item.name): \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func revealInFinder() {
        guard let item = selectedItems().first else { return }
        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path)
    }

    @objc private func copyPath() {
        guard let item = selectedItems().first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
    }

    @objc private func refreshTree() {
        reloadRoot()
    }

    // MARK: - Helpers

    private func selectedItems() -> [FileItem] {
        outlineView.selectedRowIndexes.compactMap { row in
            outlineView.item(atRow: row) as? FileItem
        }
    }

    private func contextTargetDirectory() -> URL? {
        let row = outlineView.clickedRow
        if row >= 0, let item = outlineView.item(atRow: row) as? FileItem {
            return item.isDirectory ? item.url : item.url.deletingLastPathComponent()
        }
        return rootURL
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}

// MARK: - NSOutlineViewDataSource

extension FileExplorerController: NSOutlineViewDataSource {
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // Root level - return root item's children
            return rootItem?.children?.count ?? 0
        }

        guard let fileItem = item as? FileItem else { return 0 }
        return fileItem.children?.count ?? 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            // Root level
            return rootItem?.children?[index] as Any
        }

        guard let fileItem = item as? FileItem else { return NSNull() }
        return fileItem.children?[index] as Any
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let fileItem = item as? FileItem else { return false }
        return fileItem.isDirectory
    }
}

// MARK: - NSOutlineViewDelegate

extension FileExplorerController: NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let fileItem = item as? FileItem else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("FileCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? FileTableCellView
            ?? FileTableCellView(identifier: identifier)

        cell.configure(with: fileItem)
        return cell
    }

    public func outlineViewItemWillExpand(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? FileItem else { return }

        if !item.isLoaded {
            item.loadChildren(showHidden: showHiddenFiles)
        }
        item.isExpanded = true
    }

    public func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? FileItem else { return }
        item.isExpanded = false
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        let urls = selectedItems().map(\.url)
        delegate?.fileExplorer(self, didSelectItems: urls)
    }
}

// MARK: - File Table Cell View

/// Custom cell view for file items
final class FileTableCellView: NSTableCellView {
    private let iconImageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let gitStatusView = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        gitStatusView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.font = .systemFont(ofSize: 13)

        addSubview(iconImageView)
        addSubview(nameLabel)
        addSubview(gitStatusView)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: gitStatusView.leadingAnchor, constant: -4),

            gitStatusView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            gitStatusView.centerYAnchor.constraint(equalTo: centerYAnchor),
            gitStatusView.widthAnchor.constraint(equalToConstant: 12),
            gitStatusView.heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    @MainActor
    func configure(with item: FileItem) {
        nameLabel.stringValue = item.name

        // Set icon
        let iconName = item.iconName
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            iconImageView.image = image
            iconImageView.contentTintColor = item.isDirectory ? .secondaryLabelColor : .tertiaryLabelColor
        }

        // Set git status
        if let status = item.gitStatus {
            gitStatusView.isHidden = false
            if let image = NSImage(systemSymbolName: status.iconName, accessibilityDescription: status.rawValue) {
                gitStatusView.image = image
                gitStatusView.contentTintColor = NSColor(named: status.color) ?? .secondaryLabelColor
            }
        } else {
            gitStatusView.isHidden = true
        }
    }
}
