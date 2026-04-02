# DevysCore Package

DevysCore is the foundational data models and services package for the Devys application. It provides workspace management, file system operations, panel state models, and persistence services.

## Overview

**Package Name:** DevysCore
**Swift Tools Version:** 6.0
**Minimum Platform:** macOS 14
**Language Mode:** Swift 6 with Strict Concurrency
**Version:** 1.0.0

DevysCore is a zero-dependency Swift package that provides:
- Workspace lifecycle management with persistence
- File tree models with virtualized rendering support
- Panel layout system (Bonsplit-based hierarchical splits)
- Application settings with automatic persistence
- File system watching with debouncing
- Drag and drop types for cross-package communication

## Architecture

### Design Principles

1. **Single Source of Truth**: Models like `AppSettings` and `WorkspaceManager` serve as the authoritative state
2. **Observation Pattern**: UI models use `@Observable` for SwiftUI integration
3. **Protocol Abstractions**: Services are protocol-based for testability (e.g., `WorkspacePersistenceService`, `FileTreeService`)
4. **Sendable Compliance**: All types are `Sendable` for Swift 6 concurrency safety
5. **MainActor Isolation**: Observable classes are `@MainActor` isolated

### Concurrency Model

The package enables Swift 6 strict concurrency:
```swift
.swiftLanguageMode(.v6),
.enableExperimentalFeature("StrictConcurrency")
```

All `@Observable` classes are `@MainActor` isolated. Background file operations use `Task.detached` and return to the main actor for UI updates.

## File/Folder Organization

```
Sources/DevysCore/
  DevysCore.swift              # Package entry point and version info
  Models/
    Workspace.swift            # Workspace data model
    WorkspaceManager.swift     # Workspace CRUD and lifecycle
    PanelLayout.swift          # Hierarchical panel tree structures
    PanelContent.swift         # Panel content types enum
    CEWorkspaceFileNode.swift  # File tree node (class-based for references)
    FlatFileNode.swift         # Flattened node for virtualized rendering
    FileTreeModel.swift        # File tree state management
    AppSettings.swift          # Application settings with persistence
    TabContentProvider.swift   # Protocol for dynamic tab metadata
    DragDropTypes.swift        # UTTypes and transferable types
  Services/
    FileSystemService.swift    # Tree building and file I/O
    FileSystemWatcher.swift    # DispatchSource-based file watching
    FileWatchService.swift     # File watch protocol and implementation
    FileTreeService.swift      # Tree loading abstraction
    WorkspacePersistenceService.swift    # Workspace persistence protocol
    LayoutPersistenceService.swift       # Panel layout persistence
    SettingsPersistenceService.swift     # Settings persistence protocol
    RecentFoldersService.swift           # Recent folders tracking

Tests/DevysCoreTests/
  WorkspaceTests.swift         # Unit tests for Workspace and PanelLayout
```

## Key Types

### Models

#### `Workspace`
```swift
public struct Workspace: Identifiable, Codable, Equatable, Sendable
```
Represents a project workspace with:
- `id: UUID` - Unique identifier
- `name: String` - Display name (usually folder name)
- `path: URL` - Root folder URL
- `lastOpened: Date` - For recency sorting
- `panelLayout: PanelLayout?` - Saved panel state

#### `PanelLayout` / `PanelNode`
Hierarchical tree structure for Bonsplit panel layout:
```swift
public enum PanelNode: Codable, Equatable, Sendable {
    case pane(PaneData)
    case split(orientation: SplitOrientation, children: [PanelNode], ratios: [CGFloat])
}
```
- `SplitOrientation`: `.horizontal` or `.vertical`
- `PaneData`: Contains tabs and selection state
- `TabData`: Individual tab with `id`, `filePath`, `title`, `icon`, `isDirty`

#### `CEWorkspaceFileNode`
```swift
@MainActor @Observable
public final class CEWorkspaceFileNode: Identifiable, Hashable
```
Class-based file tree node (inspired by CodeEdit) with:
- Reference semantics for parent pointers
- Lazy child loading (`children: [CEWorkspaceFileNode]?`)
- Expansion state tracking
- Computed properties: `name`, `depth`, `icon`, `iconColor`
- Static methods for file type icons/colors by extension

#### `FlatFileNode`
Struct wrapper for virtualized `LazyVStack` rendering:
```swift
public struct FlatFileNode: Identifiable, Sendable
```
Contains: `id`, `node`, `depth`, `isExpanded`, `hasChildren`, `isLastChild`

#### `FileTreeModel`
```swift
@MainActor @Observable
public final class FileTreeModel
```
Manages file tree state:
- `flattenedNodes: [FlatFileNode]` - For virtualized rendering
- `selectedNode: CEWorkspaceFileNode?`
- Methods: `loadTree()`, `toggleExpansion(_:)`, `refresh()`, `revealURL(_:)`
- Handles file watching and change detection

#### `AppSettings`
```swift
@MainActor @Observable
public final class AppSettings
```
Central settings model with automatic persistence:
- `explorer: ExplorerSettings` - File explorer configuration
- `appearance: AppearanceSettings` - Theme, fonts, colors
- `agent: AgentSettings` - AI agent/harness preferences

Settings sub-types:
- `ExplorerSettings`: `showDotfiles`, `excludePatterns`, `shouldExclude(_:)`
- `AppearanceSettings`: `isDarkMode`, `uiFontScale`, `accentColor`
- `AgentSettings`: `defaultHarness` (claudeCode, codex, or nil)

#### `PanelContent`
```swift
public enum PanelContent: Identifiable, Equatable, Sendable {
    case fileViewer(url: URL)
    case empty
}
```
Computed properties: `id`, `title`, `icon`, `iconColor`

#### `IconColor`
```swift
public enum IconColor: String, Sendable {
    case orange, yellow, green, blue, cyan, red, purple, secondary, tertiary
}
```

### Protocols

#### `TabContentProvider`
```swift
@MainActor
public protocol TabContentProvider: AnyObject {
    var tabTitle: String { get }
    var tabIcon: String { get }
    var tabFolder: URL? { get }
    var tabSubtitle: String? { get }
}
```
Enables dynamic tab metadata updates. Sessions conform to provide live title/icon.

#### `WorkspacePersistenceService`
```swift
public protocol WorkspacePersistenceService {
    func loadWorkspaces() -> [Workspace]
    func saveWorkspaces(_ workspaces: [Workspace])
}
```
Default: `UserDefaultsWorkspacePersistenceService`

#### `SettingsPersistenceService`
```swift
public protocol SettingsPersistenceService {
    func loadExplorerSettings() -> ExplorerSettings
    func loadAppearanceSettings() -> AppearanceSettings
    func loadAgentSettings() -> AgentSettings
    func saveExplorerSettings(_ settings: ExplorerSettings)
    func saveAppearanceSettings(_ settings: AppearanceSettings)
    func saveAgentSettings(_ settings: AgentSettings)
}
```
Default: `UserDefaultsSettingsPersistenceService`

#### `FileTreeService`
```swift
@MainActor
public protocol FileTreeService {
    func buildTree(rootURL: URL, explorerSettings: ExplorerSettings) async -> CEWorkspaceFileNode
    func loadChildren(for node: CEWorkspaceFileNode, explorerSettings: ExplorerSettings) async -> [CEWorkspaceFileNode]
}
```
Default: `DefaultFileTreeService`

#### `FileWatchService`
```swift
public protocol FileWatchService: AnyObject {
    var onFileChange: FileChangeHandler? { get set }
    func startWatching()
    func stopWatching()
    func watchDirectory(_ url: URL)
    func unwatchDirectory(_ url: URL)
}
```
Default: `DefaultFileWatchService`

### Services

#### `WorkspaceManager`
```swift
@MainActor @Observable
public final class WorkspaceManager
```
Manages workspace lifecycle:
- `workspaces: [Workspace]` - All workspaces, sorted by recency
- `currentWorkspace: Workspace?`
- Methods: `createWorkspace(from:)`, `openWorkspace(_:)`, `deleteWorkspace(_:)`, `renameWorkspace(_:to:)`, `updateLayout(for:layout:)`

#### `FileSystemService`
Static service for file operations:
- `buildTree(from:explorerSettings:)` - Creates root node with children
- `loadChildren(for:explorerSettings:)` - Loads directory contents

Sorting: Directories first, then case-insensitive alphabetical.

#### `FileSystemWatcher`
```swift
final class FileSystemWatcher: @unchecked Sendable
```
Low-level file watching using `DispatchSource`:
- Per-directory watching with `DispatchSourceFileSystemObject`
- Event mask: `.write`, `.delete`, `.rename`, `.extend`
- Debouncing (default 100ms) to batch rapid changes
- Thread-safe with `NSLock`

#### `LayoutPersistenceService`
Saves/loads default panel layout to UserDefaults.

#### `RecentFoldersService`
```swift
@MainActor @Observable
public final class RecentFoldersService
```
Tracks recently opened folders (max 20), validates existence on load.

### Drag and Drop Types

#### Custom UTTypes
```swift
extension UTType {
    public static let devysGitDiff = UTType(exportedAs: "com.devys.git-diff")
    public static let devysChatItem = UTType(exportedAs: "com.devys.chat-item")
}
```

#### `GitDiffTransfer`
```swift
public struct GitDiffTransfer: Codable, Sendable, Transferable
```
For dragging git diffs to chat composer:
- `path: String` - Relative file path
- `isStaged: Bool` - Staged vs unstaged changes

## Public API Surface

### Types (Public)
- `DevysCoreInfo` - Package version info
- `Workspace` - Workspace model
- `WorkspaceManager` - Workspace lifecycle
- `PanelLayout`, `PanelNode`, `SplitOrientation`, `PaneData`, `TabData` - Panel structures
- `PanelContent` - Panel content types
- `CEWorkspaceFileNode` - File tree node
- `FlatFileNode` - Flattened tree node
- `FileTreeModel` - Tree state management
- `AppSettings`, `ExplorerSettings`, `AppearanceSettings`, `AgentSettings` - Settings
- `TabContentProvider` - Tab metadata protocol
- `IconColor` - Icon color identifiers
- `FileChangeType` - File change types enum
- `FileChangeHandler` - Callback typealias
- `GitDiffTransfer` - Drag/drop data
- `UTType.devysGitDiff`, `UTType.devysChatItem` - Custom UTTypes

### Protocols (Public)
- `WorkspacePersistenceService`
- `SettingsPersistenceService`
- `FileTreeService`
- `FileWatchService`

### Services (Public)
- `UserDefaultsWorkspacePersistenceService`
- `UserDefaultsSettingsPersistenceService`
- `DefaultFileTreeService`
- `DefaultFileWatchService`
- `LayoutPersistenceService`
- `RecentFoldersService`

### Internal Only
- `FileSystemService` (enum, internal)
- `FileSystemWatcher` (class, internal)

## Dependencies

**None.** DevysCore has zero external dependencies.

Uses only Apple frameworks:
- `Foundation` - Core types, file management, JSON encoding
- `Observation` - `@Observable` macro
- `UniformTypeIdentifiers` - Custom UTTypes for drag/drop
- `SwiftUI` - Only for `Transferable` protocol
- `OSLog` - Logging in FileSystemService

## Conventions and Patterns

### Naming
- File nodes: `CEWorkspaceFileNode` prefix (from CodeEdit heritage)
- Services: `*Service` suffix (e.g., `FileTreeService`)
- Persistence: `*PersistenceService` suffix
- UserDefaults keys: `com.devys.*` or `devys.*` prefix

### Error Handling
- Services return empty arrays on error (fail gracefully)
- Logging via `OSLog.Logger` in `FileSystemService`
- No thrown errors in public API (aside from Codable)

### Testing
- Uses Swift Testing framework (`import Testing`)
- `@Suite` and `@Test` attributes
- `#expect` for assertions
- Tests focus on Codable conformance and initialization

### File Type Detection
File icons and colors are determined by extension lookup tables in `CEWorkspaceFileNode`:
- Swift (`.swift`): orange swift icon
- JavaScript/TypeScript: yellow j.square
- JSON: green curlybraces
- Markdown: blue doc.text
- Python: blue p.square
- And many more...

### UserDefaults Keys
- `devys.workspaces` - Workspace list
- `com.devys.defaultPanelLayout` - Default panel layout
- `com.devys.settings.explorer` - Explorer settings
- `com.devys.settings.appearance` - Appearance settings
- `com.devys.settings.agent` - Agent settings
- `com.devys.recentFolders` - Recent folders list

## Usage Examples

### Creating a Workspace
```swift
let manager = WorkspaceManager()
let workspace = manager.createWorkspace(from: folderURL)
manager.openWorkspace(workspace)
```

### Loading a File Tree
```swift
let model = FileTreeModel(rootURL: workspaceURL, settings: settings)
await model.loadTree()
// Access model.flattenedNodes for rendering
```

### Observing Settings
```swift
@Environment(AppSettings.self) var settings

// Settings auto-save on change
settings.explorer.showDotfiles = false
```

### Conforming to TabContentProvider
```swift
class ChatSession: TabContentProvider {
    var tabTitle: String { harness.displayName }
    var tabIcon: String { "message" }
    var tabFolder: URL? { workspaceURL }
}
```
