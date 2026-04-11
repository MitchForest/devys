# Devys - A Visual Canvas for AI-Native Software Development

## Overview

Devys is a native macOS application built with SwiftUI that serves as an AI-powered development environment. It provides a VS Code-inspired interface with integrated support for AI coding agents (Claude Code, OpenAI Codex), a Metal-accelerated code editor, built-in terminal emulation, Git integration, and a flexible split-pane workspace.

The application is designed with a terminal-inspired aesthetic featuring monospace typography, tree-drawing characters for hierarchy visualization, and support for both dark and light themes with customizable accent colors.

**Minimum Platform:** macOS 14+
**Swift Version:** 6.0 with strict concurrency enabled
**Copyright:** 2026 Devys. All rights reserved.

---

## Architecture

### High-Level Architecture

```
DevysApp (Entry Point)
    |
    +-- AppDelegate (NSApplicationDelegate)
    |       - Bootstraps logging (AgentLogging)
    |       - Manages app activation and termination
    |       - Handles dirty session save prompts on quit
    |
    +-- AppContainer (@Observable, dependency injection)
    |       - Factory for services and sessions
    |       - Injects: AppSettings, RecentFoldersService, LayoutPersistenceService
    |       - Creates: FileTreeModel, AgentSessionRuntime, GitStore, Ghostty terminal sessions
    |
    +-- ContentView (Main window content)
            |
            +-- WindowState (per-window folder state)
            +-- ThemeManager (dark/light mode, accent colors)
            +-- DevysSplitController (split pane management)
            +-- Tab and Session Management
```

### Dependency Injection Pattern

The app uses SwiftUI's environment for dependency injection:

```swift
WindowGroup {
    ContentView()
        .environment(container)
        .environment(container.appSettings)
        .environment(container.recentFoldersService)
        .environment(container.layoutPersistenceService)
}
```

`AppContainer` acts as a service locator with factory methods for creating domain-specific objects with proper dependencies.

---

## Package Dependencies

The Devys app depends on a monorepo of Swift packages located in `/Packages/`:

| Package | Purpose |
|---------|---------|
| **DevysCore** | Shared models, settings, file tree service, workspace file nodes, layout persistence |
| **DevysUI** | Design system: themes (`DevysTheme`), spacing constants (`DevysSpacing`), typography (`DevysTypography`), reusable components |
| **DevysSplit** | Split-pane tab management system (VS Code-style panes with tabs, drag-drop, welcome tabs) |
| **ACPClientKit** | Native Swift ACP transport, launcher, and protocol client for Codex and Claude adapters |
| **DevysEditor** | Metal-accelerated code editor with syntax highlighting |
| **DevysSyntax** | Syntax highlighting and language detection |
| **DevysTerminal** | Terminal emulator with Metal rendering, PTY management |
| **DevysGit** | Git integration: status, diffs, staging, PR availability |
| **DevysTextRenderer** | Low-level text rendering utilities |

All packages use Swift 6.0 language mode with `StrictConcurrency` experimental feature enabled.

---

## File Structure

```
Apps/Devys/
|-- Sources/Devys/
|   |-- Services/
|   |   |-- DevysApp.swift         # @main entry point, AppDelegate, Scene
|   |   |-- AppContainer.swift     # Dependency injection container
|   |
|   |-- Models/
|   |   |-- WindowState.swift      # Per-window folder state management
|   |   |-- ThemeManager.swift     # Theme/appearance management
|   |   |-- TabContent.swift       # Tab content type enum
|   |   |-- EditorSession.swift    # Editor document session + registry
|   |   |-- NotificationNames.swift # Custom notification definitions
|   |
|   |-- Views/
|       |-- Window/
|       |   |-- ContentView.swift              # Main view with state properties
|       |   |-- ContentView+Layout.swift       # Layout persistence
|       |   |-- ContentView+Workspace.swift    # DevysSplit workspace rendering
|       |   |-- ContentView+Actions.swift      # File/folder actions, save operations
|       |   |-- ContentView+Tabs.swift         # Tab creation, preview tabs
|       |   |-- ContentView+TabClosing.swift   # Tab close handling, dirty prompts
|       |   |-- ContentView+Sidebar.swift      # Sidebar content switching
|       |   |-- ContentView+Agents.swift       # Agent session launch, restore, and routing
|       |   |-- ContentView+StateSync.swift    # Session metadata sync
|       |   |-- ContentView+EditorTabs.swift   # Editor URL updates
|       |   |-- ContentView+StatusBar.swift     # Bottom status bar rendering
|       |   |-- ContentView+Preview.swift      # SwiftUI previews
|       |   |-- TabContentView.swift           # Renders tab content by type
|       |   |-- StatusBar.swift                 # Bottom status bar (branch, PR, run controls)
|       |   |-- ProjectPickerView.swift        # Initial folder picker
|       |   |-- PlaceholderViews.swift         # Placeholder/loading views
|       |   |-- HarnessPickerSheet.swift       # AI harness selection sheet
|       |   |-- TerminalViewWrapper.swift      # Terminal session wrapper
|       |
|       |-- Sidebar/
|       |   |-- FeatureRail.swift              # Workspace sidebar mode identifiers
|       |   |-- SidebarContentView.swift       # Expandable sidebar content
|       |
|       |-- FileTree/
|       |   |-- FileTreeView.swift             # Virtualized file tree (LazyVStack)
|       |   |-- FileTreeRow.swift              # File tree row with tree characters
|       |
|       |-- Settings/
|           |-- SettingsView.swift             # Settings tab with sections
|
|-- Resources/
|   |-- Assets.xcassets/
|   |-- Devys.entitlements                    # Sandbox disabled for terminal/PTY
|   |-- Info.plist                            # App configuration, UTI declarations
|
|-- _deprecated/
    |-- WelcomeTab.swift                      # Deprecated welcome implementation
```

---

## Key Types and Protocols

### WindowState

Per-window state tracking which folder is open:

```swift
@MainActor @Observable
public final class WindowState {
    public private(set) var folder: URL?
    public var hasFolder: Bool { folder != nil }
    public func openFolder(_ url: URL)
}
```

### TabContent

Enum identifying what content a tab displays:

```swift
enum TabContent: Equatable {
    case welcome
    case terminal(workspaceID: Workspace.ID, id: UUID)
    case agentSession(workspaceID: Workspace.ID, sessionID: AgentSessionID)
    case gitDiff(workspaceID: Workspace.ID, path: String, isStaged: Bool)
    case settings
    case editor(workspaceID: Workspace.ID, url: URL)
}
```

Design principle: `TabContent` is an identifier only. Dynamic metadata (title, icon) comes from the associated session.

### EditorSession

Manages a single editor document lifecycle:

```swift
@MainActor @Observable
final class EditorSession: Identifiable {
    let id: UUID
    var url: URL
    var document: EditorDocument?
    var isLoading: Bool
    var isDirty: Bool { document?.isDirty ?? false }

    func load() async
    func save() async throws
    func discardChanges() async throws
}
```

### EditorSessionRegistry

Singleton tracking all open editor sessions for save-all and quit-with-dirty-files handling:

```swift
@MainActor @Observable
final class EditorSessionRegistry {
    static let shared: EditorSessionRegistry
    func register(tabId: TabID, session: EditorSession)
    func unregister(tabId: TabID)
    var dirtySessions: [EditorSession]
    func saveAll() async -> Bool
}
```

### ThemeManager

Manages appearance settings:

```swift
@MainActor @Observable
final class ThemeManager {
    var isDarkMode: Bool
    var accentColor: AccentColor
    var theme: DevysTheme
    var colorScheme: ColorScheme
    func applyAppearance()
}
```

### WorkspaceSidebarMode

The workspace sidebar is section-based and persisted per workspace:

```swift
enum WorkspaceSidebarMode: String, CaseIterable, Codable, Sendable {
    case files
    case changes
    case ports
}
```

### DevysSplitCloseDelegate

Delegate connecting `DevysSplitController` to the app's tab/session management:

```swift
@MainActor
final class DevysSplitCloseDelegate: DevysSplitDelegate {
    var onShouldCloseTab: ((Tab, PaneID) -> Bool)?
    var onDidCloseTab: ((TabID, PaneID) -> Void)?
    var onDidCreateTab: ((Tab, PaneID) -> Void)?
    var onWelcomeTabForPane: ((PaneID) -> Tab?)?
    var onIsWelcomeTab: ((TabID, PaneID) -> Bool)?
    var onDidReceiveDrop: ((DropContent, PaneID, DropZone) -> TabID?)?
    var onShouldAcceptDrop: (([UTType], PaneID) -> Bool)?
}
```

---

## State Management

### ContentView State

The main `ContentView` holds significant state:

```swift
@State var windowState = WindowState()
@State var themeManager = ThemeManager()
@State var activeSidebarItem: WorkspaceSidebarMode? = .files
@State var sidebarWidth: CGFloat = 240

// Stores and services
@State var runtimeRegistry = WorktreeRuntimeRegistry()
@State var workspaceTerminalRegistry = WorkspaceTerminalRegistry()
@State var editorSessions: [TabID: EditorSession] = [:]

// DevysSplit
@State var controller = DevysSplitController(...)
@State var tabContents: [TabID: TabContent] = [:]
@State var selectedTabId: TabID?
@State var previewTabId: TabID?

// Tab closing flow
@State var closeBypass: Set<TabID> = []
@State var closeInFlight: Set<TabID> = []
```

### Session-Tab Relationship

- Each tab has a `TabID` (UUID) assigned by `DevysSplitController`
- `tabContents[TabID]` maps to a `TabContent` enum
- For session-based content:
  - `agentSession(workspaceID:sessionID:)` -> `WorkspaceAgentRuntimeRegistry.session(id:)`
  - `terminal(workspaceID:id:)` -> `WorkspaceTerminalRegistry.session(id:in:)`
  - `editor(workspaceID:url:)` -> `editorSessions[TabID]`

### Preview Tab Pattern (VS Code-style)

- Single-click opens file in preview tab (reusable)
- Double-click opens file in permanent tab
- Only one preview tab exists at a time
- Preview tabs display titles with underscore styling: `_filename.swift_`
- Double-clicking a preview tab promotes it to permanent

---

## Concurrency Patterns

### MainActor Isolation

All observable types and UI-related code are `@MainActor` isolated:

```swift
@MainActor @Observable
final class WindowState { ... }

@MainActor @Observable
final class ThemeManager { ... }

@MainActor
extension ContentView { ... }
```

### Async/Await

File I/O, session loading, and save operations use async/await:

```swift
func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
        let doc = try await EditorDocument.load(from: url)
        document = doc
    } catch {
        lastError = error.localizedDescription
    }
}
```

### Task Usage

Background operations are spawned with Task:

```swift
.task {
    await model.loadTree()
}

Task { @MainActor in
    await openFolder(url)
}
```

### Sendable Compliance

Types exposed across actor boundaries implement `Sendable` where needed. The delegate uses `nonisolated` with `MainActor.assumeIsolated` for callback bridging:

```swift
nonisolated func splitTabBar(
    _ controller: DevysSplitController,
    shouldCloseTab tab: Tab,
    inPane pane: PaneID
) -> Bool {
    MainActor.assumeIsolated {
        onShouldCloseTab?(tab, pane) ?? true
    }
}
```

---

## SwiftUI Patterns

### Environment Usage

```swift
@Environment(AppContainer.self) var container
@Environment(AppSettings.self) var appSettings
@Environment(\.devysTheme) private var theme
```

### ViewBuilder for Conditional Content

```swift
@ViewBuilder
var sidebarContent: some View {
    ContentViewSidebarSurface(...)
}
```

### onChange for State Reactions

```swift
.onChange(of: windowState.folder) { _, newFolder in
    updateGitStore(for: newFolder)
    restoreWorkspaceState(for: selectedWorktree)
}

.onChange(of: themeManager.isDarkMode) { _, _ in
    themeManager.applyAppearance()
}
```

### onReceive for NotificationCenter

```swift
.onReceive(NotificationCenter.default.publisher(for: .devysOpenFolder)) { _ in
    requestOpenFolder()
}

.onReceive(NotificationCenter.default.publisher(for: .devysSave)) { _ in
    saveActiveEditor()
}
```

### Bindings from State

```swift
ContentViewToolbarSurface(...)
```

---

## App Lifecycle

### Startup

1. `DevysApp` is the `@main` entry point
2. `AppDelegate.applicationDidFinishLaunching`:
   - Bootstraps `AgentLogging` for Console.app visibility
   - Activates app and brings to foreground
   - Sets default dark appearance
3. `WindowGroup` creates `ContentView` with environment objects
4. `ContentView.onAppear`:
   - Configures `DevysSplitController` delegate
   - Syncs theme settings from `AppSettings`
   - Initializes stores

### Folder Opening

1. User clicks "Open Folder" or selects recent folder
2. If folder already open, confirm close (with dirty file check)
3. Reset workspace state (close tabs, clear sessions)
4. Open new folder in `WindowState`
5. Add to recent folders
6. Apply default layout from persistence
7. Populate empty panes with welcome tabs
8. Show files sidebar

### Tab Lifecycle

1. **Create**: `controller.createTab(title:icon:inPane:)` returns `TabID`
2. **Track**: Store `tabContents[tabId] = content`
3. **Select**: `controller.selectTab(tabId)`, update `selectedTabId`
4. **Close Request**: Delegate's `onShouldCloseTab` checks for dirty state
5. **Close**: Delegate's `onDidCloseTab` cleans up sessions

### Termination

1. `applicationShouldTerminate` checks for dirty sessions
2. If dirty files exist, show save/don't save/cancel dialog
3. Save all if requested, then terminate

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+T | New Tab |
| Cmd+N | New Window |
| Cmd+O | Open Folder |
| Cmd+S | Save |
| Cmd+Shift+S | Save As |
| Cmd+Option+S | Save All |

Commands are defined in `DevysApp.body` using `CommandGroup`.

---

## Custom UTI Types

Defined in `Info.plist` for drag-drop support:

- `com.devys.git-diff` - Git diff content

These enable dragging items from sidebars to split panes.

---

## Design System

### Theme

`DevysTheme` from DevysUI provides semantic colors:

- `base`, `surface`, `elevated` - Background hierarchy
- `text`, `textSecondary`, `textTertiary` - Text hierarchy
- `accent`, `accentMuted` - Accent colors
- `border`, `borderSubtle` - Borders
- `hover` - Hover states

### Typography

`DevysTypography` provides monospace-based font scales:

- `xs`, `sm`, `base`, `md`, `lg`, `xl` - Size variants
- `label`, `heading` - Semantic styles
- `headerTracking` - Letter spacing for headers

### Spacing

`DevysSpacing` provides consistent spacing values:

- `space1` through `space10` - Spacing scale
- `radiusSm`, `radiusMd`, `radiusLg` - Border radii
- `sidebarCollapsed` - Rail width (48pt)

### Animations

`DevysAnimation` provides standard animation curves:

- `default` - Standard transitions
- `hover` - Hover state changes

---

## Terminal Aesthetic Conventions

The app follows a terminal-inspired design language:

1. **Tree Characters**: File trees use `|`, `+--`, `\`-- for hierarchy
2. **Monospace Typography**: Code and technical content uses monospace fonts
3. **Prompt Styling**: `$ ` prefix for command-like text
4. **Bracket Syntax**: `[ON]`, `[OFF]`, `[x]` for controls
5. **Snake Case Labels**: `show_hidden_files`, `accent_color`
6. **Uppercase Headers**: `EXPLORER`, `SETTINGS`, `RECENT_PROJECTS`

---

## Extension Pattern

`ContentView` is split across multiple files using extensions:

- `ContentView.swift` - Core state and body
- `ContentView+Layout.swift` - Layout persistence
- `ContentView+Workspace.swift` - DevysSplit rendering
- `ContentView+Actions.swift` - User actions
- `ContentView+Tabs.swift` - Tab management
- `ContentView+TabClosing.swift` - Close flow
- `ContentView+Sidebar.swift` - Sidebar content
- `ContentView+Agents.swift` - Agent launch, restore, and workflow routing
- `ContentView+StateSync.swift` - Session sync
- `ContentView+EditorTabs.swift` - Editor updates
- `ContentView+StatusBar.swift` - Bottom status bar
- `ContentView+Preview.swift` - SwiftUI previews

This keeps the main file focused on state declarations while organizing behavior into logical units.

---

## Testing Considerations

- SwiftUI previews are provided for most views
- Preview wrappers handle state and environment setup
- Both light and dark mode previews are typically provided
- Test targets exist in each package for unit testing

---

## Building and Running

The app is built as part of an Xcode workspace that includes all packages. The sandbox is disabled in entitlements to allow:

- Terminal/PTY process spawning (forkpty)
- Running AI coding agents (Claude Code, Codex CLI)
- Shell process execution

View logs with:
```bash
log stream --predicate 'subsystem BEGINSWITH "devys"' --level debug
```

---

## Future Considerations

Several placeholder views indicate planned features:

- Search functionality (`PlaceholderSidebarView` for Search)
- New file/folder creation in context menus
- Rename/delete file operations
- Multiple selection in file tree

The architecture supports these additions through the existing patterns.
