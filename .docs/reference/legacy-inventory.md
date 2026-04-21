# Devys Legacy Inventory

Updated: 2026-04-20

## Purpose

This document records the concrete legacy patterns that still need to be deleted, absorbed, or quarantined intentionally instead of rediscovering them ad hoc.

This is a current-state reference, not a phase log.

## Notification And Command Bus Inventory

### Delete From App-Domain Ownership

- `Apps/mac-client/Sources/mac/Services/DevysApp.swift`
  - posts app commands and workspace commands through `NotificationCenter.default`
  - also uses `DistributedNotificationCenter` for distributed attention bridging
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+NotificationRouting.swift`
  - receives the app command bus through `.onReceive(NotificationCenter.default.publisher(...))`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView.swift`
  - listens for `FileTreeModel.itemsDeletedNotification`
- `Packages/Workspace/Sources/Core/Models/FileTreeModel.swift`
  - posts `itemsDeletedNotification`

### Keep As Engine Or Host Integration Only

- `Packages/Git/Sources/Git/Views/Diff/Metal/*`
  - observer usage is tied to Metal/AppKit rendering and scroll integration
- `Packages/GhosttyTerminal/Sources/GhosttyTerminal/GhosttyAppBridge.swift`
  - observer usage is tied to host-bridge integration

## Singleton, Registry, Runtime, And Store Inventory

### Delete Or Absorb Into Reducers

- `Apps/mac-client/Sources/mac/Services/AppContainer.swift`
  - service-locator style composition root
- `Apps/mac-client/Sources/mac/Services/WorktreeRuntimeRegistry.swift`
  - narrowed substantially, with sidebar-visible git ownership removed; still a migration target for remaining host runtime concerns
- `Apps/mac-client/Sources/mac/Models/Agents/AgentSessionModels.swift`
  - `AgentSessionRuntime`
- `Apps/mac-client/Sources/mac/Models/EditorSession.swift`
  - `EditorSessionRegistry`

### Keep As Narrow Engine-Oriented Dependencies

- `Apps/mac-client/Sources/mac/Services/WorkspaceTerminalRegistry.swift`
  - terminal session and host-handle ownership only
- `Apps/mac-client/Sources/mac/Services/WorkspaceBackgroundProcessRegistry.swift`
  - background process handle ownership only
- `Apps/mac-client/Sources/mac/Services/WorktreeInfoStore.swift`
  - low-level workspace git snapshot watcher/client implementation
- `Apps/mac-client/Sources/mac/Services/WorkspacePortStore.swift`
  - low-level port watcher/client implementation
- `Packages/Workspace/Sources/Core/Services/SharedFileWatchRegistry.swift`
  - low-level shared file-watch transport and reuse
- `Packages/GhosttyTerminal/Sources/GhosttyTerminal/GhosttyAppBridge.swift`
  - host integration bridge
- `Packages/Split/Sources/Split/Internal/Utilities/SplitAnimator.swift`
  - UI engine utility, not app-domain state

### Needs Review

- `Packages/Workspace/Sources/Core/Models/RepositorySettingsStore.swift`
  - likely replace with reducer-owned persistence or `@Shared`

## `@unchecked Sendable` Inventory

### App-Domain Or Near-App-Domain Types To Reduce Or Quarantine

- `Apps/mac-client/Sources/mac/Services/PersistentTerminalHostDaemon.swift`
- `Packages/Git/Sources/Git/Services/GitRepositoryMetadataWatcher.swift`
- `Packages/Git/Sources/Git/Services/Worktree/DefaultWorktreeInfoWatcher.swift`

### Engine Or Low-Level Integration Types That May Remain Quarantined Behind Boundaries

- `Packages/Workspace/Sources/Core/Services/RecursiveFileWatchService.swift`
- `Packages/Workspace/Sources/Core/Services/SharedFileWatchRegistry.swift`
- `Packages/Workspace/Sources/Core/Services/FileSystemWatcher.swift`
- `Packages/GhosttyTerminal/Sources/GhosttyTerminal/GhosttyAppBridge.swift`
- `Packages/GhosttyTerminal/Sources/GhosttyTerminal/GhosttySurfaceBox.swift`
- `Packages/Text/Sources/Text/TextDocument.swift`
- `Packages/Split/Sources/Split/Internal/Styling/SplitColors.swift`
- `Packages/Syntax/Sources/Syntax/Services/Theme/ThemeRegistry.swift`
- `Packages/Syntax/Sources/Syntax/Services/Integration/SyntaxRuntimeDiagnostics.swift`
- `Packages/Syntax/Sources/SwiftTreeSitter/SendableTypes.swift`

### Test-Only Unsafe Sendable

- `Apps/mac-client/Tests/mac-clientTests/WorkspacePortStoreTestSupport.swift`
- `Apps/mac-client/Tests/mac-clientTests/AgentSessionRuntimeTests.swift`
- `Apps/mac-client/Tests/mac-clientTests/WorktreeInfoStoreTests.swift`
- `Packages/Git/Tests/GitTests/GitStoreTests.swift`
- `Packages/Workspace/Tests/CoreTests/FileTreeModelTests.swift`
- `Packages/Workspace/Tests/CoreTests/SharedFileWatchRegistryTests.swift`

## Current Hotspots

- `Apps/mac-client/Sources/mac/Views/Window/ContentView.swift`
  - still a large host/composition surface
- `Apps/mac-client/Sources/mac/Models/Agents/AgentSessionModels.swift`
  - agent session runtime ownership remains outside the reducer-owned model
- `Apps/mac-client/Sources/mac/Models/EditorSession.swift`
  - editor session ownership remains outside reducer-owned app-domain state

## Working Interpretation

- Treat notification routing, runtime registries, and shared mutable stores as deletion targets unless they are clearly engine-only.
- Treat engine-level unsafe sendable usage as quarantine targets behind dependency clients.
- Do not add new items to any deletion-target category.
