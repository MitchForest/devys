# Devys Legacy Inventory

Updated: 2026-04-16

## Purpose

This document records the concrete legacy patterns the migration must delete, absorb, or quarantine intentionally instead of rediscovering ad hoc.

It is supporting reference for `../plan/implementation-plan.md`, not an active plan by itself.

## 1. Notification And Command Bus Inventory

### Classification

- `delete during Phase 3`: app-domain command bus built on `NotificationCenter`
- `keep as engine or integration only`: low-level observer usage tied to rendering or host framework integration

### Delete During Migration

- `Apps/mac-client/Sources/mac/Services/DevysApp.swift`
  - posts app commands and workspace commands through `NotificationCenter.default`
  - also uses `DistributedNotificationCenter` for distributed attention bridging
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+NotificationRouting.swift`
  - receives the app command bus through `.onReceive(NotificationCenter.default.publisher(...))`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView.swift`
  - listens for `FileTreeModel.itemsDeletedNotification`
- `Packages/Workspace/Sources/Core/Models/FileTreeModel.swift`
  - posts `itemsDeletedNotification`

### Keep As Engine / Integration

- `Packages/Git/Sources/Git/Views/Diff/Metal/*`
  - observer usage is tied to Metal/AppKit rendering and scroll integration
- `Packages/GhosttyTerminal/Sources/GhosttyTerminal/GhosttyAppBridge.swift`
  - observer usage is tied to host-bridge integration

## 2. Singleton, Registry, Runtime, And Store Inventory

### Delete Or Absorb Into Reducers

- `Apps/mac-client/Sources/mac/Services/AppContainer.swift`
  - service-locator style composition root
- `Apps/mac-client/Sources/mac/Services/WorktreeRuntimeRegistry.swift`
  - still a migration target, but phase 6 removed metadata and port ownership so it is no longer the app-domain operational-state owner
- `Apps/mac-client/Sources/mac/Models/Agents/AgentSessionModels.swift`
  - `AgentSessionRuntime`
- `Apps/mac-client/Sources/mac/Models/EditorSession.swift`
  - `EditorSessionRegistry`

### Likely Keep As Engine-Oriented Dependency With Narrower Boundary

- `Apps/mac-client/Sources/mac/Services/WorkspaceTerminalRegistry.swift`
  - terminal session and host-handle ownership only after phase 6
- `Apps/mac-client/Sources/mac/Services/WorkspaceBackgroundProcessRegistry.swift`
  - background process handle ownership only after phase 6
- `Apps/mac-client/Sources/mac/Services/WorktreeInfoStore.swift`
  - low-level metadata watcher/client implementation, no longer an app-domain owner
- `Apps/mac-client/Sources/mac/Services/WorkspacePortStore.swift`
  - low-level port watcher/client implementation, no longer an app-domain owner
- `Packages/Workspace/Sources/Core/Services/SharedFileWatchRegistry.swift`
  - low-level shared file-watch transport and reuse
- `Packages/GhosttyTerminal/Sources/GhosttyTerminal/GhosttyAppBridge.swift`
  - host integration bridge
- `Packages/Split/Sources/Split/Internal/Utilities/SplitAnimator.swift`
  - UI engine utility, not app-domain state

### Needs Review During Migration

- `Packages/Workspace/Sources/Core/Models/RepositorySettingsStore.swift`
  - likely replace with reducer-owned persistence or `@Shared`

## 3. `@unchecked Sendable` Inventory

### App-Domain Or Near-App-Domain Types That Must Be Reduced Or Quarantined

- `Apps/mac-client/Sources/mac/Services/PersistentTerminalHostDaemon.swift`
- `Packages/Git/Sources/Git/Services/GitRepositoryMetadataWatcher.swift`
- `Packages/Git/Sources/Git/Services/Worktree/DefaultWorktreeInfoWatcher.swift`

### Engine / Low-Level Integration Types That May Remain Quarantined Behind Boundaries

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

## 4. Immediate Hotspots Blocking Clean Migration

- `Apps/mac-client/Sources/mac/Views/Window/ContentView.swift`
  - still a large host/composition surface even after shell, catalog, and operational-state migration
- `Apps/mac-client/Sources/mac/Models/Agents/AgentSessionModels.swift`
  - agent session runtime ownership remains a later-phase migration target
- `Apps/mac-client/Sources/mac/Models/EditorSession.swift`
  - editor session ownership remains outside reducer-owned app-domain state

## 5. Baseline Fixes Applied In Phase 0

- Split `Packages/Git/Sources/Git/Models/GitStore.swift` into focused partials:
  - `GitStore.swift`
  - `GitStore+Refresh.swift`
  - `GitStore+Changes.swift`
- Fixed a follow-up line-length violation in `Packages/Git/Sources/Git/Services/GitRepositoryMetadataWatcher.swift`
- Replaced synthesized `Equatable` usage in `GitRepositoryMetadataWatcher.swift` with explicit comparisons so Periphery no longer reports assign-only metadata snapshot fields

## 6. Phase 6 Closeout Applied

- `Apps/mac-client/Sources/mac/Services/WorkspaceAttentionStore.swift`
  - deleted in phase 6
- `Apps/mac-client/Sources/mac/Services/WorkspaceRunStore.swift`
  - deleted in phase 6
- `Apps/mac-client/Sources/mac/Services/WorktreeRuntimeRegistry.swift`
  - metadata and port coordination ownership removed in phase 6
- `Apps/mac-client/Sources/mac/Services/WorkspaceTerminalRegistry.swift`
  - unread-terminal ownership removed in phase 6
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+StateSync.swift`
  - reducer-to-runtime operational mirrors collapsed in phase 6
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+ShellCommandRequests.swift`
  - view-owned attention ingress routing removed in phase 6

## 7. Phase 7 Progress Applied

- `Packages/Git/Sources/Git/Services/GitStoreRegistry.swift`
  - deleted in phase 7 as part of hosted-content/runtime-owner cleanup
- `Packages/AppFeatures/Sources/AppFeatures/SharedModels/HostedContentModels.swift`
  - reducer-owned hosted editor and agent metadata summaries added in phase 7
- `Apps/mac-client/Sources/mac/Models/EditorSession.swift`
  - `EditorSessionRegistry.shared` removed in favor of an explicit host-scoped dependency in phase 7
- `Apps/mac-client/Sources/mac/Services/WorktreeRuntimeRegistry.swift`
  - absorbed standalone agent-session lookup and rekeying in phase 7; `WorkspaceAgentRuntimeRegistry` no longer exists as a separate runtime owner
  - narrowed to focused engine accessors in phase 7; broad runtime-handle exposure is removed

## 8. Phase 8 Progress Applied

- `Packages/AppFeatures/Sources/AppFeatures/Window/WindowFeature+TabOpenState.swift`
  - reducer-owned semantic tab intent now handles preview reuse, duplicate-tab focus, and preview promotion
- `Packages/AppFeatures/Sources/AppFeatures/Window/WindowFeature+SelectionRequests.swift`
  - reducer-owned workspace transition requests now derive repository/workspace switch policy before host execution
- `Packages/AppFeatures/Sources/AppFeatures/Window/WindowFeature+TabCloseRequests.swift`
  - reducer-owned dirty-tab close policy now resolves before the host presents save confirmation
- `Packages/AppFeatures/Sources/AppFeatures/Window/WindowFeature+AgentLaunchRequests.swift`
  - reducer-owned default-agent launch policy now resolves whether the host should launch directly or present the harness picker
- `Apps/mac-client/Sources/mac/Services/HostedWorkspaceContentBridge.swift`
  - focused host observation now publishes hosted editor and agent summaries into reducer-owned state without broad `ContentView` scans
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+Tabs.swift`
  - view-owned duplicate and preview policy was replaced by reducer-first tab open requests with narrow host reconciliation
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+ShellCommandRequests.swift`
  - host selection execution now consumes reducer-generated workspace transition requests instead of deriving app-domain switch policy locally
  - host agent launch execution now consumes reducer-generated launch requests for default-harness resolution
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+TabClosing.swift`
  - host tab-close handling now consumes reducer-generated close requests instead of owning dirty-editor close policy
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+Agents.swift`
  - primary agent launch entry points now send reducer-owned launch intents instead of reading default-harness policy directly
- `Apps/mac-client/Sources/mac/Services/WorktreeRuntimeRegistry.swift`
  - UI-visible agent ordering policy removed; registry now returns unsorted engine handles and consumes focused Git/file-tree factories instead of retaining `AppContainer`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+StateSync.swift`
  - broad hosted-content scan was removed; remaining state-sync helpers now limit themselves to tab presentation reconciliation

## 9. Phase 9 Progress Applied

- `Packages/AppFeatures/Sources/AppFeatures/SharedModels/WindowRelaunchModels.swift`
  - relaunch snapshot models moved out of `Apps/mac-client` and into the app-domain package
- `Packages/AppFeatures/Sources/AppFeatures/SharedDependencies/PersistenceClients.swift`
  - explicit `WindowRelaunchPersistenceClient` now owns relaunch snapshot load/save effects for reducers
- `Packages/AppFeatures/Sources/AppFeatures/Window/WindowFeature+RelaunchPersistence.swift`
  - reducer-owned relaunch snapshot planning now derives persisted workspace layouts and hosted-session restore records from shell state plus hosted-content summaries
- `Packages/AppFeatures/Sources/AppFeatures/Window/WindowFeature+ShellRequests.swift`
  - reducer-owned relaunch restore requests now decide whether restore should run before the host imports repositories or rehydrates sessions
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+TerminalPersistence.swift`
  - host relaunch handling is narrowed to repository import plus terminal/agent rehydration from reducer-generated requests
- `Apps/mac-client/Sources/mac/Services/TerminalHostModels.swift`
  - app-layer relaunch model ownership is deleted in favor of `AppFeatures` shared models
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+Lifecycle.swift`
  - startup restore now begins from a reducer intent instead of host-owned relaunch policy

## 10. Actionable Interpretation

- Treat notification routing, runtime registries, and shared mutable stores as deletion targets.
- Treat engine-level unsafe sendable usage as quarantine targets behind dependency clients.
- Do not add new items to any deletion-target category while migration is in progress.
