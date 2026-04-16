# Devys - A Visual Canvas for AI-Native Software Development

## Overview

Devys is a native macOS application built with SwiftUI that serves as an AI-powered development environment. It provides a VS Code-inspired interface with integrated support for AI coding agents (Claude Code, OpenAI Codex), a Metal-accelerated code editor, built-in terminal emulation, Git integration, and a flexible split-pane workspace.

The application is designed with a terminal-inspired aesthetic featuring monospace typography, tree-drawing characters for hierarchy visualization, and support for both dark and light themes with customizable accent colors.

**Minimum Platform:** macOS 14+
**Swift Version:** 6.0 with strict concurrency enabled
**Copyright:** 2026 Devys. All rights reserved.

## Migration Note

The architecture guidance below predates the active TCA migration and is not authoritative when it conflicts with the current repo docs.

For active work:

- `Packages/AppFeatures` is the app-domain home for reducer-owned shell and feature logic.
- `AppContainer` is a temporary live service composition root and factory, not the intended long-term owner of app-domain behavior.
- legacy runtime registries, mirrored shell state, and app-domain `NotificationCenter` routing are migration targets.
- phase 1 through 7 are complete enough that reducer-owned shell topology, catalog state, workspace operational summaries, and hosted-content metadata are the active architecture story.
- phase 8 is complete: reducer-owned tab intent, dirty-tab close policy, workspace transition policy, default-agent launch policy, focused hosted-content publication, and explicit runtime factory boundaries now belong to the migration baseline.
- phase 9 is complete: relaunch snapshot models, relaunch persistence effects, and relaunch restore planning now belong to `Packages/AppFeatures`, while `ContentView` only executes repository import and engine-backed session rehydration.
- the canonical references are `.docs/reference/architecture.md`, `.docs/reference/ui-ux.md`, and `.docs/plan/implementation-plan.md`.

---

## Architecture

### High-Level Architecture

```
DevysApp (Entry Point)
    |
    +-- AppDelegate (NSApplicationDelegate)
    |       - Manages app activation and termination
    |       - Handles dirty session save prompts on quit
    |
    +-- AppContainer (temporary live service composition root)
    |       - Supplies app settings and engine-facing factories
    |       - Creates low-level file tree, git, terminal, and launcher services
    |
    +-- StoreOf<AppFeature>
    |       - Root reducer store created by AppFeaturesBootstrap
    |       - AppFeature owns lifecycle state
    |       - WindowFeature owns reducer-first shell and catalog state
    |
    +-- ContentView (migration-era composition layer)
            |
            +-- store-driven shell presentation and command routing
            +-- legacy runtime registries and split controller
            +-- engine-backed editor / terminal / agent session hosting
```

### Dependency Injection Pattern

The app currently uses two layers:

- SwiftUI environment for live services and UI support objects
- TCA dependencies for app-domain reducer behavior

```swift
WindowGroup {
    AppFeatureHost(store: appStore) {
        ContentView(store: appStore.scope(state: \.window, action: \.window))
    }
        .environment(container)
        .environment(container.appSettings)
        .environment(container.recentRepositoriesService)
        .environment(container.layoutPersistenceService)
}
```

`AppContainer` remains a temporary live factory layer. New app-domain behavior should enter through `Packages/AppFeatures` reducers and explicit dependency clients.

---

## Package Dependencies

The Devys app depends on a monorepo of Swift packages located in `/Packages/`:

| Package | Purpose |
|---------|---------|
| **DevysCore** | Shared models, settings, file tree service, workspace file nodes, layout persistence |
| **DevysUI** | Design system: themes (`DevysTheme`), spacing constants (`DevysSpacing`), typography (`DevysTypography`), reusable components |
| **DevysSplit** | Split-pane tab management system (VS Code-style panes with tabs, drag-drop, and empty-pane CTA surfaces) |
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
|       |   |-- ContentView+StateSync.swift    # Reducer-first catalog/runtime bridge
|       |   |-- ContentView+EditorTabs.swift   # Editor URL updates
|       |   |-- ContentView+StatusBar.swift     # Floating status capsule rendering
|       |   |-- ContentView+Preview.swift      # SwiftUI previews
|       |   |-- TabContentView.swift           # Renders tab content by type
|       |   |-- ProjectPickerView.swift        # Initial folder picker
|       |   |-- PlaceholderViews.swift         # Placeholder/loading views
|       |   |-- HarnessPickerSheet.swift       # AI harness selection sheet
|       |   |-- TerminalViewWrapper.swift      # Terminal session wrapper
|       |
|       |-- Sidebar/
|       |   |-- FeatureRail.swift              # Content sidebar tab identifiers
|       |   |-- SidebarContentView.swift       # Expandable sidebar content
|       |
|       |-- FileTree/
|       |   |-- FileTreeView.swift             # Virtualized file tree (LazyVStack)
|       |   |-- FileTreeRow.swift              # File tree row with connector lines and git indicators
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
    |-- WelcomeTab.swift                      # Legacy welcome-tab experiment, not part of the active shell model
```

---

## Key Types and Protocols

### AppFeature / WindowFeature

Reducer-owned app and window state:

```swift
@Reducer
public struct AppFeature {
    public struct State: Equatable {
        public var lifecycle: Lifecycle
        public var window: WindowFeature.State
    }
}
```

`WindowFeature` is the current reducer-first home for:

- repository and workspace selection
- shell presentation state
- command request routing
- semantic workspace tab content
- workspace shell snapshots used during the migration

### WorkspaceTabContent

Semantic tab identity now lives in `Packages/AppFeatures`:

```swift
public enum WorkspaceTabContent: Equatable, Sendable {
    case terminal(workspaceID: Workspace.ID, id: UUID)
    case agentSession(workspaceID: Workspace.ID, sessionID: AgentSessionID)
    case gitDiff(workspaceID: Workspace.ID, path: String, isStaged: Bool)
    case settings
    case editor(workspaceID: Workspace.ID, url: URL)
}
```

Design principle: `WorkspaceTabContent` is semantic identity only. Dynamic metadata still comes from the hosted editor, terminal, git, and agent session state.

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

Host-scoped registry tracking open editor sessions for save-all execution. Dirty-session policy is reducer-owned after phase 7:

```swift
@MainActor @Observable
final class EditorSessionRegistry {
    init()
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

The content sidebar is a two-tab Files/Agents surface and persists that tab per workspace:

```swift
enum WorkspaceSidebarMode: String, CaseIterable, Codable, Sendable {
    case files
    case agents
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
  - `agentSession(workspaceID:sessionID:)` -> `WorktreeRuntimeRegistry.agentSession(id:in:)`
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

### NotificationCenter Usage

```swift
// Allowed: external integration ingress and engine/framework observation.
.onReceive(NotificationCenter.default.publisher(for: .devysWorkspaceAttentionIngress)) { notification in
    ingestExternalAttention(notification)
}
```

Do not add new app-domain command routing through `NotificationCenter`. Reducer actions and explicit dependency clients are the expected path.

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
7. Show empty panes with CTA buttons
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

Dia-browser-modeled. See `Packages/UI/CLAUDE.md` and `.docs/reference/ui-ux-v2.md` for full spec.

### Theme

`Theme` (via `@Environment(\.theme)`) provides adaptive colors:

- `base`, `card`, `overlay` — Three surface levels
- `text`, `textSecondary`, `textTertiary` — Text hierarchy
- `accent`, `accentMuted`, `accentSubtle` — Theme accent
- `primaryFill`, `primaryFillForeground` — Primary button colors
- `border`, `borderFocus` — Two border levels
- `hover`, `active`, `cardHover` — Interaction states

### Typography

SF Pro (proportional) for UI, SF Mono for code:

- `Typography.display/title/heading/body/label/caption/micro` — 7 UI sizes
- `Typography.Code.base/sm/lg/gutter` — 4 code sizes
- `Typography.Chat.body/heading/caption/code` — 4 chat sizes

### Spacing

4px grid. `Spacing.tight/normal/comfortable/relaxed/spacious`.

- `Spacing.radius` (12pt) — the one radius for everything
- `Spacing.radiusMicro` (4pt) — tiny elements only
- `Spacing.radiusFull` (9999pt) — circles only
- All `RoundedRectangle` must use `style: .continuous`

### Elevation

`.elevation(.base/.card/.popover/.overlay)` — sets background + border + shadow + radius in one call.

### Animations

- `Animations.spring` — all structural transitions
- `Animations.micro` — all micro-interactions (120ms ease-out)

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
- `ContentView+StateSync.swift` - Reducer-first catalog/runtime bridge
- `ContentView+EditorTabs.swift` - Editor updates
- `ContentView+StatusBar.swift` - Floating status capsule
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
