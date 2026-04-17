# Devys Migration Implementation Plan

Updated: 2026-04-16

## Purpose

This is the only active migration plan for Devys.

It records:

- the current repo state
- which phases are complete
- the completed closeout state through the active migration phases
- the ordered remaining migration boundaries
- the sequencing rules for later phases

It supersedes the old phase-specific working-plan documents.

## Canonical Inputs

- architecture rules: `../reference/architecture.md`
- UI and interaction target: `../reference/ui-ux.md`
- governance ADRs: `../adrs`
- legacy deletion inventory: `../reference/legacy-inventory.md`

## Current Repo Snapshot

As of 2026-04-16, the repo is in a real but incomplete migration state:

- `Packages/AppFeatures` exists and is tested.
- `AppFeature` and `WindowFeature` exist and own meaningful shell and catalog state.
- explicit dependency bootstrapping exists for the new reducer package.
- the live app still runs through a large `ContentView` composition layer, but shell presentation and coordination are now reducer-first.
- run-profile launch and stop intent is now prepared in reducer effects and executed through one-shot host requests instead of view-owned orchestration.
- workspace operational sync policy and runtime-driven port ownership refresh no longer live in `ContentView`.
- workspace pane/tab/layout topology is represented by reducer-native shell models instead of `Split` snapshots.
- reducer actions now own pane focus, tab insertion/selection/closure, split closure, divider persistence, and per-pane preview policy.
- workspace runtime activation no longer swaps app-domain shell state through `WorktreeRuntimeRegistry`.
- `WorkspaceShellState` is deleted as an app-domain owner.
- `Packages/Split` now feeds reducer synchronization through a narrow gesture/render adapter instead of acting as the long-term app-domain persistence model.
- repository and workspace catalog state, refresh, and persistence now enter through reducer-owned `AppFeatures` dependencies.
- the live shell now matches the canonical Files/Agents sidebar model.
- the app now builds and launches successfully through the `mac-client` scheme and the DerivedData app bundle.
- live split move/split/close-pane gestures now emit reducer-meaningful intents instead of round-tripping topology through controller snapshots.
- `Apps/mac-client` no longer reconstructs canonical workspace shell topology from `Split.ExternalTreeNode` snapshots.
- workspace switching and relaunch restore now rebuild reducer-owned shell state first, render `Split` second, and rehydrate hosted content third.
- relaunch snapshot models, snapshot persistence planning, and relaunch restore policy now live in `Packages/AppFeatures` behind an explicit dependency client.
- `ContentView` no longer derives relaunch snapshot contents or workspace-shell restore policy locally; it imports repositories and rehydrates engine-backed terminal and agent sessions from reducer-generated requests.
- `Apps/mac-client` no longer owns `WindowWorkspaceCatalogStore` or bidirectional reducer/catalog sync helpers.
- the controller snapshot bridge and catalog bridge are deleted, so later phases can start from the remaining runtime-oriented owners.
- hosted editor and agent metadata used by active UI now synchronize into reducer-owned state in `WindowFeature`.
- quit/save-all dirty-policy checks now read reducer-owned hosted-content summaries instead of a global editor singleton.
- `GitStoreRegistry` is deleted and `WorktreeRuntimeRegistry` now exposes focused engine accessors instead of broad runtime handles.

## Phase Status

### Phase 0

Status: complete

What is done:

- governance ADRs exist
- baseline quality-gate path exists
- CI quality gate exists
- legacy inventory exists

### Phase 1

Status: complete

What is done:

- `Packages/AppFeatures` exists
- root reducers exist
- reducer tests exist
- explicit dependency registration exists

What still needs closeout:

- none

### Phase 2

Status: complete

What is done:

- warm token system landed in `Packages/UI`
- shared UI primitives exist for command palette, tabs, rows, sheet/popover surfaces, and status surfaces
- titlebar FAB and floating status capsule direction are present
- the live content sidebar now follows the canonical Files/Agents model
- diffs and ports now live under the Files tab instead of surviving as top-level shell modes
- legacy relaunch snapshots normalize old `changes` and `ports` sidebar values into the Files tab
- the dead full-width `StatusBar.swift` shell path is removed

What still needs closeout:

- none

### Phase 3

Status: complete

What is done:

- top-level shell presentation state is meaningfully reducer-owned
- app commands route through explicit reducer actions and one-shot requests
- the old shell command notification-routing path is removed
- semantic workspace shell snapshot state exists in `WindowFeature`
- reducer state now explicitly drives the legacy catalog selection bridge instead of relying on broad `ContentView` selection observers
- the remaining runtime-facing shell bridge is narrowed to files-sidebar visibility and phase 4 topology/runtime activation
- shell coordination docs now describe phase 4 as the only remaining non-reducer shell ownership boundary

What still needs closeout:

- none

### Phase 4

Status: complete

Goal:

- make workspace shell topology and visible pane/tab/layout state reducer-owned

Entry status:

- phase 1 through 3 are complete
- phase 4 entry criteria are satisfied

What is done:

- reducer-native workspace shell models exist in `Packages/AppFeatures`
- reducer actions own pane focus, tab ordering and selection, per-pane preview state, split structure, and divider persistence
- `WorkspaceShellState` is deleted and `WorktreeRuntimeRegistry` no longer owns app-domain shell swapping
- empty panes render CTA surfaces directly instead of synthetic welcome tabs
- `Packages/Split` is narrowed to a render/gesture boundary for most shell interactions
- live split move/split/close-pane gestures now dispatch reducer-meaningful intents into `WindowFeature` instead of syncing topology from controller snapshots
- `ContentView+ShellLayout.swift` no longer rebuild canonical `WorkspaceLayout` from `Split.ExternalTreeNode`
- workspace switch, restore, relaunch restore, and persistence paths now follow reducer-first shell ownership
- phase 4 closeout tests now cover reducer topology mutations, reducer-only restore round-trips, and the app-layer split gesture adapter path
- phase 4 closeout docs, app-layer verification, and shared design-system enforcement now match the completed shell ownership story

What still needs closeout:

- none

### Verification Notes

Targeted verification that passed:

- `./scripts/check-design-system.sh`
- `./scripts/check-tree-sitter-migration.sh`
- `swift test --package-path Packages/AppFeatures`
- `swift test --package-path Packages/Split`
- `swift test --package-path Packages/UI`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/SplitGestureReducerAdapterTests -only-testing:mac-clientTests/TerminalRelaunchSnapshotTests -only-testing:mac-clientTests/AppContainerAgentLaunchTests -only-testing:mac-clientTests/WorkspaceCatalogRuntimeTests -only-testing:mac-clientTests/WorktreeRuntimeRegistryTests`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' build`

### Phase 5

Status: complete

Goal:

- collapse the remaining catalog bridge and make reducer-owned catalog effects the only app-domain path

What is done:

- `WindowWorkspaceCatalogStore` and the mac-layer catalog refresh/mutation bridge files are deleted
- `WorkspaceCatalogRefreshClient` and `WorkspaceCatalogPersistenceClient` now provide reducer-owned refresh and persistence behavior from `Packages/AppFeatures`
- `AppFeaturesBootstrap` wires live catalog dependencies and restores persisted workspace state into reducer state at launch
- `ContentView` no longer owns a legacy catalog store or bidirectional reducer/catalog sync helpers
- repository and workspace catalog mutations now persist from `WindowFeature` effects instead of dual writes from the view layer
- workspace selection now updates `lastFocused` in reducer state before persistence, preserving navigator ordering without the legacy store
- runtime coordinators now consume `WindowCatalogRuntimeSnapshot` built from reducer-owned catalog snapshots instead of the deleted store
- phase 5 tests now cover reducer-owned catalog effects plus app-layer runtime consumers without `WindowWorkspaceCatalogStore`

What still needs closeout:

- none

### Phase 5 Verification Notes

Targeted verification that passed:

- `swift test --package-path Packages/AppFeatures`
- `swift test --package-path Packages/Workspace`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/WorkspaceCatalogRuntimeTests -only-testing:mac-clientTests/WorktreeMetadataCoordinatorTests -only-testing:mac-clientTests/WorkspacePortOwnershipCoordinatorTests -only-testing:mac-clientTests/WorktreeRuntimeRegistryTests`

### Phase 6

Status: complete

Goal:

- move workspace operational state and workflow coordination into reducer-owned `AppFeatures` state and explicit dependency clients

Why this phase exists:

- phase 4 made pane and tab shell topology reducer-owned
- phase 5 collapsed the remaining catalog bridge
- the next unresolved ownership boundary is workspace operational state that still lives in mac-layer registries, stores, and view-layer synchronization code

Phase 6 sequencing rule:

Phase 6 starts by defining reducer-owned operational models and effect clients.
It does not start by deleting runtime objects with no replacement.

Deletion follows replacement.

Entry criteria:

- phase 1 through 5 are complete
- no second catalog source of truth survives in active code
- the remaining migration targets are the runtime-oriented owners listed in `../reference/legacy-inventory.md`

Status:

- satisfied as of 2026-04-15

### Workstream A: Define Reducer-Owned Workspace Operational State

Deliverables:

- reducer-owned workspace metadata summaries
- reducer-owned workspace port summaries
- reducer-owned attention and notification state
- reducer-owned run-profile lifecycle state
- reducer-owned terminal unread state and related workflow state
- reducer tests that prove operational state transitions and effect flow

Rules:

- reducers own IDs, metadata, lifecycle, presentation, policy, and workflow coordination
- engine handles stay outside reducer state
- views render reducer state and invoke explicit actions

Progress:

- complete

### Workstream B: Introduce Explicit Operational Dependency Clients

Deliverables:

- `AppFeatures` dependency clients for worktree metadata, workspace ports, terminal runtime coordination, attention ingress, and workspace run orchestration
- live bootstrap wiring from `Apps/mac-client`
- narrow app-layer adapters that may temporarily wrap existing runtime/store implementations while reducer ownership is established

Rules:

- app-domain effects run through dependency clients
- client interfaces are `Sendable` unless a narrower actor-isolated boundary is intentional
- new adapters must have a deletion path for any legacy owner they temporarily wrap

Progress:

- complete

### Workstream C: Migrate Attention, Notifications, And Run State

Deliverables:

- delete `WorkspaceAttentionStore` as the app-domain owner
- delete `WorkspaceRunStore` as the app-domain owner
- reducer-owned notification filtering, navigation, and clearing behavior
- reducer-owned run-profile launch and stop state transitions

Rules:

- no app-domain attention or notification routing remains view-owned
- notification ingress may stay as integration glue only, never as app-domain state ownership

Progress:

- complete

### Workstream D: Reclassify Metadata And Port Ownership

Deliverables:

- reducer-owned metadata and port summaries used by navigator, sidebar, command palette, and status capsule
- `WorktreeInfoStore` and `WorkspacePortStore` reduced to low-level client internals or deleted if replacement is direct
- metadata and port coordination removed from `WorktreeRuntimeRegistry`

Rules:

- repository and workspace operational summaries shown in UI are reducer-owned
- low-level watchers and scanners may survive only behind explicit clients

Progress:

- complete

### Workstream E: Shrink `ContentView` To Host/Rendering Responsibilities

Deliverables:

- delete view-owned operational synchronization paths
- move selection-driven refresh and observation policy into reducer effects
- keep `ContentView` focused on hosting engine views, split rendering, and app-framework integration only

Rules:

- no new long-lived app-domain state may be introduced in `ContentView`
- views may hold narrow engine handles only where required for rendering or hosting

Progress:

- complete

### Ordered Ticket Sequence

1. Define reducer-owned workspace operational state in `Packages/AppFeatures`.
2. Add explicit dependency clients for metadata, ports, terminal status, attention ingress, and run orchestration.
3. Wire live app-layer adapters through `AppFeaturesBootstrap`.
4. Migrate attention, notification, and unread-terminal ownership into reducer state.
5. Migrate run-profile lifecycle ownership into reducer state and narrow background-process ownership to handles.
6. Reclassify metadata and port stores as low-level client internals or delete them where replacement is direct.
7. Remove metadata and port coordination ownership from `WorktreeRuntimeRegistry`.
8. Rewire navigator, sidebar, command palette, notifications, and status capsule surfaces to reducer state.
9. Delete obsolete view-owned synchronization and legacy store ownership in the same stream.
10. Update tests, docs, and verification notes before phase closeout. Complete.

### Phase 6 Verification Notes

- `swift test --package-path Packages/AppFeatures`
- `swift test --package-path Packages/Split`
- `swift test --package-path Packages/UI`
- `swift test --package-path Packages/Workspace`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/WorkspaceOperationalControllerTests -only-testing:mac-clientTests/WorkspaceTerminalRegistryTests`
- the `mac-client` scheme pre-action quality gate passed on 2026-04-15, including strict SwiftLint, design-system and tree-sitter repo gates, and Periphery package scans

Current closeout status:

- step 1 is complete
- step 2 is complete
- step 3 is complete
- step 4 is complete
- step 5 is complete
- step 6 is complete
- step 7 is complete
- step 8 is complete
- step 9 is complete
- step 10 is complete

### Exit Criteria

- workspace operational summaries used by active UI are reducer-owned
- no app-domain attention, unread-terminal, or run-profile state survives in mac-layer observable stores
- metadata and port coordination no longer live in `WorktreeRuntimeRegistry`
- `ContentView` no longer owns view-driven operational synchronization as app-domain behavior
- phase 6 lands without introducing mirrored ownership or new permanent shims

### Branch 7 Entry Status

Status: ready

Reason:

- phase 5 and phase 6 closeout work is complete
- branch closeout verification was rerun on 2026-04-15 after the reducer-owned run-profile lifecycle and `ContentView` sync cleanup landed

## Phase 7

Status: complete

Goal:

- move hosted editor, agent, and git session metadata and workflow coordination into reducer-owned `AppFeatures` state and explicit dependency clients or one-shot host requests

Why this phase exists:

- phase 4 made pane and tab shell topology reducer-owned
- phase 5 collapsed the remaining catalog bridge
- phase 6 moved workspace operational ownership into reducer state
- the next unresolved migration boundary is hosted content session ownership that still lives in `ContentView`, runtime registries, and host-side session objects

Phase 7 sequencing rule:

Phase 7 starts by defining reducer-owned hosted-content models and explicit host clients.
It does not start by deleting engine handles with no replacement.

Deletion follows replacement.

Entry criteria:

- phase 1 through 6 are complete
- workspace operational summaries used by active UI are reducer-owned
- the remaining migration targets are the hosted-content owners listed in `../reference/legacy-inventory.md`

Status:

- satisfied as of 2026-04-15

### Workstream A: Define Reducer-Owned Hosted Content State

Deliverables:

- reducer-owned editor document summaries for dirty/loading/title state
- reducer-owned agent session summaries for title, subtitle, busy state, and activity ordering
- reducer-owned hosted-content projections used by tab chrome, sidebar, command palette, status capsule, and quit/save policy
- reducer tests that prove hosted-content state updates remain reducer-owned

Rules:

- reducers own IDs, metadata, lifecycle state, presentation, and workflow policy
- editor documents, ACP connections, PTY sessions, and git engine handles stay outside reducer state
- `WorkspaceTabContent` remains semantic identity only

Progress:

- complete

### Workstream B: Introduce Explicit Hosted Content Clients

Deliverables:

- host-facing clients for editor session coordination, agent session coordination, and workspace git coordination
- live bootstrap wiring from `Apps/mac-client`
- narrow host adapters that may temporarily wrap existing runtime objects while reducer ownership is established

Rules:

- app-domain effects run through dependency clients or one-shot host requests
- new adapters must have a same-stream deletion path for any legacy owner they temporarily wrap
- no new app-domain singleton, registry, or manager may be introduced

Progress:

- complete

### Workstream C: Collapse Global And Hidden Runtime Owners

Deliverables:

- delete `GitStoreRegistry`
- delete `EditorSessionRegistry.shared` and replace it with an explicit host-scoped dependency
- remove reducer-irrelevant session ownership from `ContentView`
- shrink `WorktreeRuntimeRegistry` toward engine-only scope as replacement clients land

Rules:

- no mirrored long-lived ownership survives between reducers and runtime objects
- host caches may survive only as client internals, never as UI-facing authorities

Progress:

- complete

### Workstream D: Rewire Hosted Content UI Surfaces To Reducer State

Deliverables:

- agents sidebar reads reducer-owned session summaries
- command palette reads reducer-owned agent metadata and active-workspace projections
- status capsule reads reducer-owned agent counts and activity metadata
- tab presentation updates continue to flow from live sessions, but their visible metadata is synchronized into reducer state

Rules:

- views render reducer state for visible app behavior
- views may still hold narrow engine handles only where rendering requires them

Progress:

- complete

### Workstream E: Close Out Docs, Tests, And Inventory

Deliverables:

- update the architecture reference and app/package contributor guidance to phase 7 language
- refresh the legacy inventory as runtime owners are deleted or reclassified
- targeted reducer and app-layer tests for hosted content synchronization and host request execution

Progress:

- complete

### Ordered Ticket Sequence

1. Define reducer-owned hosted-content models in `Packages/AppFeatures`.
2. Add host-side synchronization from editor and agent sessions into reducer state.
3. Replace `EditorSessionRegistry.shared` with an explicit host-scoped dependency.
4. Delete `GitStoreRegistry` and remove package-level registry entry points.
5. Rewire sidebar, command palette, status capsule, and tab metadata surfaces to reducer-backed hosted-content summaries.
6. Narrow `WorktreeRuntimeRegistry` as hosted content slices leave it.
7. Update tests, docs, and verification notes before phase closeout.

### Exit Criteria

- hosted editor and agent metadata shown in active UI is reducer-owned
- `EditorSessionRegistry.shared` is deleted
- `GitStoreRegistry` is deleted
- `ContentView` no longer acts as the long-lived UI-facing owner of hosted content metadata
- remaining runtime registries are narrowed to engine-only handles or clearly-defined host adapters
- phase 7 lands without introducing mirrored ownership or new permanent shims

### Phase 7 Verification Notes

Targeted verification that passed:

- `swift test --package-path Packages/AppFeatures`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/WorktreeRuntimeRegistryTests`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/WorktreeAgentRuntimeTests`

## Phase 8

Status: complete

Goal:

- move workspace tab intent policy, workspace lifecycle coordination, and hosted session workflow policy into reducer-owned `AppFeatures` state and explicit host clients so `ContentView` becomes a narrower host/rendering surface

Why this phase exists:

- phase 7 moved visible hosted metadata into reducer-owned state
- tab open and close policy still lives in `ContentView`
- workspace activation, restore, and discard sequencing still live in `ContentView`
- `WorktreeRuntimeRegistry` and `AppContainer` still retain app-facing workflow coordination that the architecture charter classifies as migration targets

Phase 8 sequencing rule:

Phase 8 starts by defining reducer-owned semantic intents and focused host clients.
It does not start by deleting host runtimes or engine handles with no replacement.

Deletion follows replacement.

Entry criteria:

- phase 1 through 7 are complete
- hosted metadata shown in active UI is reducer-owned
- the remaining migration targets are the view-layer and runtime-owner hotspots listed in `../reference/legacy-inventory.md`

Status:

- satisfied as of 2026-04-16

### Workstream A: Define Reducer-Owned Tab Intent Policy

Deliverables:

- reducer-owned semantic actions for opening workspace content in preview or permanent mode
- reducer-owned duplicate-tab selection and preview-tab promotion policy
- reducer-owned tab close request policy hooks that keep app-domain behavior out of `ContentView`
- reducer tests that prove tab intent behavior without view-layer orchestration

Rules:

- reducers own tab intent, duplication policy, preview policy, and selection outcomes
- views may still perform narrow host follow-up such as keyboard focus and renderer synchronization
- `WorkspaceTabContent` remains semantic identity only

Progress:

- reducer-owned semantic tab open actions landed in `Packages/AppFeatures`
- preview reuse, duplicate detection, and preview promotion now resolve in reducer state before host follow-up executes
- `ContentView+Tabs` no longer owns the primary duplicate and preview policy path
- dirty-editor tab close policy now resolves through reducer-owned close requests before the host presents save confirmation

### Workstream B: Define Reducer-Owned Workspace Lifecycle Requests

Deliverables:

- reducer-owned workspace activation, restore, and discard requests
- focused host execution hooks for runtime activation, hydration, disposal, and restore sequencing
- reducer tests that prove lifecycle requests originate from app-domain state instead of `ContentView`

Rules:

- reducers own lifecycle policy and ordering intent
- host code executes engine-bound work and reports results back through explicit actions or synchronization helpers
- no new registry, manager, or service-locator owner may be introduced

Progress:

- reducer-owned workspace transition requests now derive repository/workspace switching intent before host execution
- `ContentView` selection entry points consume reducer-generated lifecycle requests instead of recomputing switch policy locally

### Workstream C: Replace View-Owned Hosted Content Synchronization

Deliverables:

- focused host synchronization paths for editor and agent summaries
- reducer-backed hosted content updates that do not depend on broad `ContentView` scans of live runtime state
- reduced `ContentView` responsibility for tab metadata and hosted-content summary derivation

Rules:

- visible app behavior must render reducer state
- host observation may survive only as a narrow adapter for engine-owned objects
- no mirrored long-lived ownership survives between reducers and runtime objects

Progress:

- reducer-owned hosted content remains the canonical visible state
- hosted editor and agent summaries now publish through a focused `HostedWorkspaceContentBridge` instead of broad `ContentView` scans
- hosted browser sessions now use the same bridge boundary: reducer-owned tab identity with host-owned `BrowserSession` handles and reducer-backed URL/title summaries
- Ghostty `OPEN_URL` actions now route through a narrow host callback into the existing reducer-owned split/tab flow, reusing an existing browser pane or creating a side-by-side browser pane for local app testing links
- visible agent ordering and editor dirty/loading metadata now derive from focused host observation rather than runtime-wide rescans
- primary default-agent launch policy now resolves in reducer state before the host decides between direct launch and picker presentation

### Workstream D: Narrow Runtime Owners To Host-Only Boundaries

Deliverables:

- `WorktreeRuntimeRegistry` reduced to engine-handle caching and lookup only
- `AppContainer` reduced toward assembly and factory responsibilities only
- same-stream deletion of obsolete bridges created by prior migration phases

Rules:

- runtime caches may survive only as host internals
- app-domain workflow coordination moves into reducers or explicit dependency clients
- host layers must expose focused interfaces instead of broad mutable object graphs

Progress:

- browser session handles now live in a focused `WorkspaceBrowserRegistry` host cache instead of re-expanding `WorktreeRuntimeRegistry`

Progress:

- `WorktreeRuntimeRegistry` no longer sorts agent sessions for UI-visible ordering; ordering now happens in hosted summary derivation
- `WorktreeRuntimeRegistry` now accepts focused Git and file-tree factories instead of retaining `AppContainer`
- `AppContainer` remains a composition root and factory while host runtime wiring consumes only narrow factory closures

### Workstream E: Close Out Docs, Tests, And Inventory

Deliverables:

- update the architecture reference and app/package contributor guidance to phase 8 language
- refresh the legacy inventory as phase 8 narrows or deletes runtime-owner responsibilities
- targeted reducer and app-layer tests for tab intent policy, workspace lifecycle requests, and hosted session execution paths

Progress:

- plan, legacy inventory, and app-scoped contributor guidance now reflect the active phase 8 reducer/request boundaries
- reducer tests cover tab close requests and default-agent launch resolution in addition to tab open and workspace lifecycle requests
- app-layer tests now cover the hosted content bridge and runtime-registry factory boundary

### Ordered Ticket Sequence

1. Add phase 8 to this implementation plan and define explicit non-goals.
2. Add reducer-owned semantic tab intent actions and state transitions in `Packages/AppFeatures`.
3. Migrate preview reuse, duplicate detection, and permanent-tab promotion out of `ContentView`.
4. Add reducer-owned workspace lifecycle request actions for activate, restore, and discard flows.
5. Introduce focused host clients or request surfaces for runtime activation, disposal, and hosted session execution.
6. Migrate agent launch, focus, and reducer-visible hosted workflow policy out of `ContentView`.
7. Replace broad view-owned hosted-content synchronization with focused host summary updates.
8. Narrow `WorktreeRuntimeRegistry` and `AppContainer` to host-only responsibilities and delete obsolete bridges in the same stream.
9. Update tests, docs, inventory, and verification notes before phase closeout.

### Exit Criteria

- tab open, duplicate selection, preview reuse, and preview-promotion behavior is reducer-owned
- workspace activation, restore, and discard policy is reducer-owned
- `ContentView` no longer acts as the long-lived app-domain owner of tab intent or workspace lifecycle coordination
- hosted editor and agent summary updates reach reducer state through focused host boundaries instead of broad view scans
- `WorktreeRuntimeRegistry` is narrowed to engine-handle caching and lookup
- `AppContainer` remains a composition root and factory, not an app-domain workflow owner
- phase 8 lands without introducing mirrored ownership or new permanent shims

Phase 8 closeout status: exit criteria satisfied.

### Phase 8 Verification Notes

Targeted verification to run before closeout:

- `swift test --package-path Packages/AppFeatures`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/WorkspaceCatalogRuntimeTests`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/WorktreeRuntimeRegistryTests`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/AgentSessionRuntimeTests`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/EditorSessionTests`

Verification completed during the current phase-8 stream:

- `swift test --package-path Packages/AppFeatures`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/HostedWorkspaceContentBridgeTests -only-testing:mac-clientTests/WorktreeRuntimeRegistryTests`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/AgentSessionRuntimeTests -only-testing:mac-clientTests/EditorSessionTests`

## Phase 9

Status: complete

### Goal

Move relaunch snapshot persistence policy and relaunch restore planning into `Packages/AppFeatures`, leaving `Apps/mac-client` as the host executor for repository import and engine-backed session rehydration only.

### Detailed TODOs

- `P9-01` Move shared relaunch snapshot models out of `Apps/mac-client` and into `Packages/AppFeatures`.
  - Status: complete
- `P9-02` Add an explicit reducer dependency for relaunch snapshot persistence and snapshot loading.
  - Status: complete
- `P9-03` Make reducer effects derive relaunch restore requests from persisted snapshots and current restore settings before any host execution occurs.
  - Status: complete
- `P9-04` Make reducer state rebuild selected repository, selected workspace, sidebar mode, and workspace shell snapshots from relaunch requests.
  - Status: complete
- `P9-05` Narrow `ContentView` relaunch handling so the host only imports repositories and rehydrates engine-backed terminal and agent sessions from reducer-generated requests.
  - Status: complete
- `P9-06` Add reducer coverage and app-layer verification for relaunch persistence planning and relaunch restore execution boundaries.
  - Status: complete
- `P9-07` Update canonical docs, inventory, and contributor guidance to reflect the reducer-owned relaunch boundary.
  - Status: complete

### Ordered Work

1. Move relaunch snapshot types into `Packages/AppFeatures` and delete app-layer ownership of those models.
2. Introduce an explicit relaunch persistence client in `Packages/AppFeatures`.
3. Add reducer-owned snapshot building from shell state and hosted-content summaries.
4. Add reducer-owned restore-request generation from persisted snapshot + restore settings.
5. Apply relaunch restore requests back into reducer-owned repository, workspace, sidebar, and layout state.
6. Narrow `ContentView` to repository import plus terminal/agent rehydration from reducer-issued relaunch requests.
7. Close the phase with reducer tests, app-layer verification, and documentation updates.

### Exit Criteria

- relaunch snapshot model ownership lives in `Packages/AppFeatures`
- relaunch snapshot persistence flows through an explicit dependency client
- reducer effects decide whether relaunch restore should happen and what the host should execute
- reducer state rebuilds repository selection, workspace selection, sidebar state, and workspace shell state from relaunch requests
- `ContentView` no longer derives relaunch snapshot contents or relaunch shell-restore policy locally
- the host only imports repositories and rehydrates engine-backed sessions from reducer-generated relaunch requests
- phase 9 lands without reintroducing mirrored ownership or a new app-domain runtime owner

Phase 9 closeout status: exit criteria satisfied.

### Phase 9 Verification Notes

Targeted verification to run before closeout:

- `swift test --package-path Packages/AppFeatures`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/TerminalRelaunchSnapshotTests`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/HostedWorkspaceContentBridgeTests`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/WorkspaceCatalogRuntimeTests`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' build`

Verification completed during the current phase-9 stream:

- `swift test --package-path Packages/AppFeatures`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' test -only-testing:mac-clientTests/TerminalRelaunchSnapshotTests -only-testing:mac-clientTests/HostedWorkspaceContentBridgeTests -only-testing:mac-clientTests/WorkspaceCatalogRuntimeTests`
- `xcodebuild -project Devys.xcodeproj -scheme mac-client -configuration Debug -destination 'platform=macOS' build`

## Phase 1 Closeout Plan

### Goal

Treat the foundation as landed infrastructure instead of a sidecar experiment.

### Detailed TODOs

- `P1C-01` Document `AppContainer` as a temporary live service composition root only, not the architectural owner of app-domain behavior.
  - Status: complete
- `P1C-02` Update app-scoped contributor guidance to point future work at `Packages/AppFeatures` and explicit dependency clients instead of the old container/store graph.
  - Status: complete
- `P1C-03` Reduce obviously-unused `AppFeatures` public API surface where package-internal dependency scaffolding is not consumed cross-module.
  - Status: complete
- `P1C-04` Audit the remaining public `AppFeatures` surface and justify each exported symbol against current cross-module use.
  - Status: complete
- `P1C-05` Remove or rewrite leftover repo docs/comments that still present legacy shell and store ownership as the intended long-term architecture.
  - Status: complete
- `P1C-06` Verify that new app-domain shell work continues to enter through reducers and explicit clients rather than `Apps/mac-client` state owners.
  - Status: complete

### Ordered Work

1. Treat `Packages/AppFeatures` as the default home for new app-domain shell logic.
2. Audit `AppFeatures` visibility and reduce any unnecessary `public` surface.
3. Document the composition-root rule clearly:
   `AppContainer` may supply live low-level services, but it is not the architecture story for app-domain behavior.
4. Remove or rewrite any docs and comments that still imply the old container/store graph is the intended long-term architecture.

### Exit Criteria

- no new app-domain ownership is introduced outside reducers or explicit clients
- `AppFeatures` boundaries are intentional
- the docs no longer describe Phase 1 as tentative
- the remaining exported `AppFeatures` surface is justified by current cross-module use from `Apps/mac-client`
- app-scoped contributor guidance no longer presents the legacy container/store graph as the intended architecture

## Phase 2 Closeout Plan

### Goal

Finish the shell and design-system normalization that is already partially landed.

### Detailed TODOs

- `P2C-01` Replace the old `.files/.changes/.ports/.agents` shell framing with the canonical two-tab Files/Agents model.
  - Status: complete
- `P2C-02` Move diffs and listening ports under the Files tab instead of preserving them as top-level shell modes.
  - Status: complete
- `P2C-03` Rebuild the content sidebar as a segmented two-tab surface using shared `Packages/UI` primitives and add the workflows placeholder defined by the UI reference.
  - Status: complete
- `P2C-04` Remove sidebar menu items and legacy shell visuals that depend on deleted top-level Changes/Ports shell modes.
  - Status: complete
- `P2C-05` Normalize persistence, tests, and contributor guidance to the new sidebar model while preserving restore compatibility for pre-closeout relaunch snapshots.
  - Status: complete

### Exit Criteria

- the live shell matches the canonical UI reference at the information-architecture level
- no second shell model survives in active app code
- design-system ownership is consistent across active shell surfaces

## Phase 3 Closeout Plan

### Goal

Close the gap between reducer-owned shell intent and the still-live legacy coordination layer.

### Detailed TODOs

- `P3C-01` Remove broad `ContentView` selection observers that mirror reducer selection back into the legacy catalog store.
  - Status: complete
- `P3C-02` Make the remaining bridge directions explicit:
  reducer selection applies to the legacy catalog store, reducer files-sidebar visibility applies to the runtime bridge.
  - Status: complete
- `P3C-03` Relabel the remaining non-reducer shell ownership honestly as the phase 4 topology/runtime activation boundary.
  - Status: complete
- `P3C-04` Update canonical docs and contributor guidance so phase 3 is described as complete and phase 4 is the next unresolved shell authority.
  - Status: complete

### Exit Criteria

- shell presentation and coordination are clearly reducer-first
- remaining non-reducer shell ownership is limited to the phase 4 topology boundary
- no docs overstate Phase 3 completeness

## Phase 4 Execution Plan

### Goal

Replace workspace runtime swapping and controller-owned shell topology with a reducer-owned, value-driven workspace shell.

### Phase 4 Sequencing Rule

Phase 4 starts by defining the reducer-owned shell model. It does not start by deleting random runtime types.

Deletion follows replacement.

### Entry Criteria

- phase 1 through 3 closeout work is complete enough that the remaining shell gap is topology and runtime ownership, not documentation or command-routing confusion
- the canonical docs describe one architecture and one shell model

Status:

- satisfied as of 2026-04-15

### Workstream A: Define The Reducer-Owned Workspace Shell

Deliverables:

- canonical reducer-owned models for panes, tabs, focus, preview tab, empty pane CTA policy, and layout persistence snapshots
- explicit shell actions for pane focus, tab selection, tab creation, split creation, split destruction, and close rules
- reducer tests that prove shell state transitions

Rules:

- reducer state owns visible shell truth
- engine-backed editor, terminal, and agent handles remain outside the reducer
- tab content stays semantic and workspace-scoped
- empty panes render CTA surfaces directly; the shell does not synthesize welcome tabs

### Workstream B: Make `Split` A Rendering Boundary

Deliverables:

- a state/input model that `Packages/Split` can render
- a narrowed adapter layer from reducer state into split rendering
- removal of topology ownership from `SplitViewController` as an app-domain authority

Rules:

- `Packages/Split` may still manage rendering mechanics and gestures
- `Packages/Split` must not remain the source of visible pane/tab topology truth

### Workstream C: Remove Workspace Copy/Swap Ownership

Deliverables:

- delete the imperative workspace shell snapshot copy/restore path as the app-domain owner
- remove `WorkspaceShellState` as a long-lived app-domain authority
- stop swapping visible shell state through `WorktreeRuntimeRegistry`

Rules:

- runtime registries may retain engine handles
- reducer state becomes the only source of visible shell state

### Workstream D: Quarantine Runtime Registries To Engine Scope

Deliverables:

- `WorktreeRuntimeRegistry` reduced to low-level handles and engine-bound caches only
- clear separation between:
  - reducer-owned shell state
  - engine-owned runtime handles
- explicit cleanup paths for terminal, git watcher, file tree, and agent engine resources

### Workstream E: Persistence And Restore Rewrite

Deliverables:

- layout restore reads reducer-owned snapshots
- workspace switching restores reducer-owned shell state directly
- no runtime-owned shell swap semantics remain

### Ordered Ticket Sequence

1. Define the reducer-owned workspace shell model in `Packages/AppFeatures`.
2. Add exhaustive reducer tests for pane/tab/layout state transitions.
3. Introduce the split-rendering adapter so the view layer can consume reducer-owned shell state.
4. Move visible pane and tab topology authority out of controller-owned state.
5. Rewrite workspace restore and selection flows to restore reducer-owned shell state directly.
6. Delete `WorkspaceShellState` as an app-domain authority.
7. Remove shell-state ownership from `WorktreeRuntimeRegistry`.
8. Run a focused cleanup pass over `ContentView` and related shell files to delete obsolete synchronization code.

Current closeout status:

- steps 1 through 8 are complete
- reducer-owned topology, restore order, and split gesture flow now satisfy the phase 4 exit criteria

### Exit Criteria

- pane and tab topology are reducer-owned
- workspace restore is reducer-owned
- runtime shell copying is gone
- `Packages/Split` renders state instead of owning app-domain shell truth
- the repo is ready to finish phase 5 without another round of mirrored ownership

## Post-Phase-5 Starting Point

Later phases should start from the remaining runtime-oriented owners listed in `../reference/legacy-inventory.md`.
Do not recreate a catalog bridge or a second source of truth for repository and workspace state.

## Workflow V1 Execution Track

This section is the active execution plan for the workflow feature described in `../future/workflow-vision.md`.

It is not a new sidecar plan.
It exists here because this file remains the only active execution plan for the repo.

### Goal

Ship a reducer-owned, graph-backed workflow system with Canvas as the definition builder, real PTY-backed terminals as the execution truth, and explicit node-to-node handoff after each run attempt.

### Current Status

- landed reducer-owned graph primitives: `WorkflowWorker`, `WorkflowNode`, `WorkflowEdge`, artifact bindings, run attempts, completion state, and operator-choice state
- landed Canvas-backed definition editing in workflow tabs with reducer-owned graph sync
- landed Canvas as an active production package at `Packages/Canvas`, replacing the archived package path in the shipped app dependency graph
- landed terminal-first execution: workflow attempts launch in real PTY-backed terminals, terminal exit is the default completion signal, and ambiguous next edges pause for operator choice
- landed workflow shell integration: workflow definition and run tabs restore through relaunch, run tabs stay inspector-first, and terminal focus stays the only steering behavior
- landed file and artifact plumbing: markdown plan parsing, append-only follow-up ticket updates, prompt artifact capture, run persistence, and hosted-terminal reattachment
- remaining follow-on product work is optional expansion, not architectural debt: workflow status hints in navigator/status surfaces, optional quality-gate and commit nodes, and later headless execution

### Decisions Locked Now

- workflow surfaces should be tab-first and sidebar-integrated, not modal-first
- workflow truth belongs in `Packages/AppFeatures`; host execution belongs in `Apps/mac-client`
- Canvas is on the v1 path as the workflow-definition builder surface
- Canvas is a builder and visualization primitive, not the runtime source of truth
- real PTY-backed terminal tabs are the execution truth for interactive agent nodes
- `steering` means the operator focuses the running terminal and types into it
- steering is not persisted note state, not a special workflow artifact, and not a dedicated UI panel
- terminal exit is the default completion signal for terminal-backed nodes
- node-to-node handoff happens after a run attempt completes; if the next edge is ambiguous, Devys pauses for operator choice
- the markdown plan file is an artifact binding and progress document, not the workflow topology
- the built-in delivery loop ships as a template, not as hardcoded workflow runtime law
- headless execution may follow on the same run model but must not block the interactive path
- v1 workflow execution must not depend on agent chat UI

### Sequencing Rule

Build the smallest real graph-backed loop first.

Do not start with:

- a second, temporary fixed-loop runtime that preserves executor/reviewer as core types
- a fake terminal or mirrored chat surface in place of the real terminal tab
- chat-oriented workflow execution
- a modal control room that bypasses the existing tab and split shell

Start with the actual primitives:

- worker
- node
- edge
- run attempt
- terminal session
- completion signal
- operator action
- artifact binding

### Workstream A: Reducer-Owned Workflow Domain Rewrite

Deliverables:

- graph-backed workflow models in `Packages/AppFeatures`
- `WorkflowWorker`, `WorkflowNode`, `WorkflowEdge`, `WorkflowArtifactBinding`, `WorkflowRunAttempt`, and explicit completion/handoff policy types
- reducer-owned node execution state, edge traversal state, and operator-decision state
- reducer-owned sidebar and tab presentation state for workflow surfaces
- reducer tests for run state transitions, node completion, edge traversal, interruption, and restore

Rules:

- reducers own IDs, lifecycle, presentation, policy, and visible workflow state
- engine handles, PTYs, ACP connections, and host runtimes stay outside reducer state
- no workflow role semantics should be inferred from string IDs
- the first shipped workflow template may be opinionated, but the runtime primitives must stay generic

Likely placement:

- `Packages/AppFeatures/Sources/AppFeatures/Workflows/...`
- `Packages/AppFeatures/Tests/AppFeaturesTests/Workflow...`

### Workstream B: Canvas Builder Adoption

Deliverables:

- use `Packages/Canvas` as the active workflow-definition builder package
- semantic mapping between reducer-owned workflow nodes/edges and Canvas nodes/connectors
- Canvas editing for workers, nodes, edges, and basic edge labels or conditions
- workflow definition tabs centered on Canvas-first editing instead of list-only role forms

Rules:

- Canvas must not own workflow truth or runtime policy
- node position and connector layout must remain presentation state or persisted builder metadata only
- runtime semantics must round-trip without depending on canvas geometry

Likely placement:

- `Packages/Canvas/...`
- `Apps/mac-client/Sources/mac/Views/Workflows/...`

### Workstream C: Plan File And Artifact Bindings

Deliverables:

- markdown parser support for ordered phase headings and ticket extraction
- append-only follow-up ticket writing for explicit workflow-owned sections
- explicit artifact binding types for plan files, prompt files, diffs, test output, and run artifacts
- tests for phase detection, ticket extraction, and non-destructive file updates

Rules:

- the plan file may live anywhere, but the parser contract must stay explicit
- do not rewrite the whole markdown file just to update workflow state
- do not make the markdown plan the only representation of workflow topology

### Workstream D: Interactive Terminal Runner

Deliverables:

- reducer-issued host requests for launch, stop, retry, reopen, and reattach
- a dedicated host execution coordinator for workflow steps in `Apps/mac-client`
- persisted attempt, event, and artifact capture per run
- reattachment to active hosted terminals after app relaunch

Rules:

- interactive execution uses the existing hosted-terminal infrastructure
- the real terminal is the execution truth
- the workflow tab may inspect execution but must not replace the terminal tab as the primary live surface
- workflow execution may reuse low-level launcher and terminal plumbing, but it should not be modeled as `AgentSessionRuntime`

Likely placement:

- `Apps/mac-client/Sources/mac/Services/Workflows/...`

### Workstream E: Handoff And Edge Traversal

Deliverables:

- explicit completion signals for node attempts
- edge traversal after attempt completion
- pause-for-choice behavior when multiple edges are valid
- built-in edge conditions for the first slice kept small and explicit

Rules:

- process exit is the default completion signal for terminal-backed nodes
- no hidden inference like "the agent stopped acting"
- if Devys cannot determine the next edge unambiguously, it must pause and ask the operator

### Workstream F: Workflow Shell Surfaces

Deliverables:

- `WorkspaceTabContent` cases for workflow definition and workflow run tabs
- reducer actions to open, focus, and restore workflow tabs
- Agents sidebar cards for active runs and recent runs
- command palette and titlebar entry points
- run tab focused on current node, run history, artifacts, and edge state
- workflow status hints in navigator rows and status surfaces once the core loop is stable

Rules:

- workflows should live in the same split/tab shell as files, diffs, and terminals
- no workflow-only parallel navigation model should be introduced
- repeated workflow UI belongs in `Packages/UI`
- "open terminal" must focus the actual live terminal tab for the active attempt
- do not add a persistent steering panel or steering-note surface

Likely placement:

- `Packages/UI/Sources/UI/Views/Components/Workflow/...`
- `Apps/mac-client/Sources/mac/Views/Workflows/...`

### Workstream G: Delivery Loop Template

Deliverables:

- a built-in delivery workflow template expressed as normal workers, nodes, and edges
- initial worker presets for implementation and review
- optional quality-gate and commit nodes after the review pass
- a template that can still target markdown phase work without hardcoding those semantics into the runtime

Rules:

- one active run per worktree in v1
- one workflow run owns one worktree and branch
- do not reintroduce executor/reviewer as privileged runtime types

### Workstream H: Recovery And Operator Controls

Deliverables:

- stop, retry, choose-next-edge, open terminal, open plan file, and open diff actions
- reducer-owned interrupted, blocked, awaiting-choice, failed, and complete states
- run restore after app relaunch
- artifact and log inspection in the workflow run surface

Rules:

- intervention must preserve run state instead of bypassing it
- steering means typing into the active terminal, nothing more
- no hidden fallback path should silently desynchronize the workflow tab from the underlying run

### Workstream I: Deletion And Migration

Deliverables:

- remove fixed executor/reviewer slot logic from the workflow domain
- remove persisted steering state and steering UI
- remove fixed step enums and hardcoded next-step progression
- migrate existing file-backed workflow definitions and runs if required
- update docs and tests in the same change stream as the replacement

Rules:

- delete wrong abstractions instead of wrapping them
- do not preserve the current fixed loop as a compatibility layer without a removal plan

### Ordered Ticket Sequence

1. Done and reusable: real PTY-backed workflow terminal launching and hosted-terminal reattachment exist.
2. Done and reusable: markdown phase parsing and append-only plan updates exist.
3. Done and reusable: file-backed workflow definition and run persistence exist.
4. Done: fixed workflow domain types were replaced with workers, nodes, edges, artifact bindings, and run attempts.
5. Done: Canvas is the active workflow-definition builder path.
6. Done: fixed step sequencing was replaced with explicit completion signals and edge traversal.
7. Done: persisted steering state and steering UI were removed; terminal focus/open is the only steering behavior.
8. Done: the run tab is an inspector/control surface and the real terminal tab stays primary.
9. Done: the built-in delivery loop can ship as template data on top of the generic primitives.
10. Follow-on: add optional quality-gate and commit nodes after the core path is solid.
11. Follow-on: reassess headless execution only after the interactive graph-backed path is solid.

### Recommended First Slice

The first slice should prove the primitives, not a temporary hardcoded loop.

That slice is:

1. select a markdown plan file
2. define two or more workers on a Canvas-backed workflow definition
3. connect those workers with explicit nodes and edges
4. run one node in a real terminal tab
5. click into that terminal and type to steer while it is running
6. treat terminal exit as the default completion signal for that attempt
7. traverse the next edge automatically when unambiguous, or pause for operator choice when it is not
8. append follow-up tickets back into the bound plan file when the workflow definition requests it
9. show current node, attempt state, and artifacts in the run tab and Agents sidebar
10. restore the active run after relaunch

Status:

- complete for the interactive V1 target; remaining work is optional expansion on top of the shipped graph-backed runtime

If that works well, then richer edge conditions, quality-gate nodes, and later headless execution can follow without changing the core runtime model.

## Documentation Maintenance Rule

When migration work lands:

- update this file in the same change stream
- do not create a new temporary phase plan
- delete obsolete plan prose instead of archiving it in place
