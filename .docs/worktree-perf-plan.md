# Devys Worktree Performance Plan

Updated: 2026-04-06

Supersedes:

- `.docs/perf-plan.md`
- `.docs/worktree-recovery-plan.md`

This is the single source of truth for worktree, repository, file-open, sidebar, and launcher performance work in Devys.

## Performance Stance

Performance is a product feature.

Any interaction on the critical path that visibly waits, flashes a spinner, or blocks on avoidable global work is a bug.

The standard is not "pretty good for SwiftUI" or "fine on my machine." The standard is:

- local interactions do local work
- expensive work is scoped, shared, cached, or deferred
- correctness-critical state is always-on and cheap
- UI-facing heavy observation is subscription-driven
- regressions are caught by instrumentation and tests before they ship

## Goal

Make the following interactions feel immediate again, even in windows with many repositories, many worktrees, lots of ignored files, and active runtime state:

- open a file
- switch workspace
- switch repository
- open the files sidebar
- open `Claude`, `Codex`, `Shell`, or `Run`

## Current Measured Baseline

These numbers were measured against the current repo state on 2026-04-06 and are the most important reality check for this plan:

- `git worktree list --porcelain`: about `0.00s`
- `git status --porcelain=v1`: about `0.04s`
- `git ls-files --others -i --exclude-standard`: about `1.26s`
- current steady-state git refresh command bundle for the sidebar path: about `0.94s`
- tracked status entries in this repo: `78`
- ignored paths returned by the ignored-file expansion command: `82,874`
- ignored output size written to disk during measurement: about `9.1 MB`
- local reproduction of `WorkspaceFileTreeGitStatusIndex` construction over the current `allChanges` payload: about `135ms` average per rebuild

The biggest remaining regression is therefore not worktree listing. It is the combination of:

- ignored-file enumeration on the steady-state git path
- render-time reconstruction of the file-tree git decoration index from that huge change set
- full-file text loading on file open
- repository/workspace selection paths that still await too much work before restoring visible state

## Non-Negotiable User-Visible Budgets

These are acceptance gates, not aspirations.

### File Open

- Clicking a file in an already-loaded workspace must create or reuse the preview tab synchronously with no repository-wide refresh on the click path.
- Preview tab shell must appear in the same interaction frame on warm path.
- Small UTF-8 text files up to `256 KB` must show text content within:
  - `p50 <= 100ms`
  - `p95 <= 200ms`
- Small UTF-8 text files up to `1 MB` must become fully interactive within:
  - `p50 <= 200ms`
  - `p95 <= 400ms`
- Opening one file must not trigger full tab-strip reconciliation, full git refresh, or whole-window invalidation.

### Workspace Switch

- Switching to an already-known workspace must restore visible shell state within:
  - `p50 <= 100ms`
  - `p95 <= 200ms`
- Switching workspace must not await metadata hydration, port scans, or file-tree reload before restoring cached UI state.
- Only the selected workspace may receive high-priority runtime refresh on switch.

### Repository Switch

- Switching repositories must show the selected workspace shell or empty repository state within:
  - `p50 <= 150ms`
  - `p95 <= 300ms`
- Repository selection must not block on background worktree hydration.

### Sidebar / File Tree

- Opening the files sidebar for a previously-loaded workspace must not rebuild the tree from disk.
- Initial root listing for a workspace must complete within:
  - `p50 <= 75ms`
  - `p95 <= 200ms`
  for roots with up to `2,000` immediate entries on local disk.
- File-tree decoration updates must not enumerate ignored files globally.

### Launchers

- `Claude`, `Codex`, `Shell`, and `Run` must not pay persistent-host cold start on steady state.
- Launching a managed runtime must not cause repeated global `lsof` / `ps` scans.

## Hard Technical Acceptance Criteria

No ticket in this plan is complete unless all applicable conditions are true:

- instrumentation exists for the interaction
- the instrumentation is scoped enough to isolate the source of time
- at least one automated test covers the regression boundary
- manual validation was run on:
  - this repo
  - a repo with many ignored files
  - a repo with multiple worktrees
- the implementation removes work from the critical path instead of hiding it behind more debounce

## Architectural End State

Devys should converge on this model:

### 1. Stable Window Catalog

One window-owned catalog is the source of truth for:

- repositories
- worktrees by repository
- selection
- navigator ordering and persisted worktree state

Selection is just a pointer into the catalog.

### 2. Stable Per-Worktree Runtime Registry

One per-worktree runtime registry owns:

- git runtime
- file-tree runtime
- workspace shell state
- metadata runtime handle
- port/runtime ownership handle

Runtime objects are keyed by workspace ID and reused. They are not recreated by view mount churn.

### 3. Shared Workspace Filesystem Layer

Filesystem behavior should look more like `superset`:

- bounded reads with `maxBytes`
- revision tokens
- shared watcher transport per workspace/root
- incremental directory invalidation instead of rebuild-everything semantics

Relevant reference files:

- `.docs/repos/superset/packages/workspace-fs/src/fs.ts`
- `.docs/repos/superset/packages/workspace-client/src/hooks/useFileTree/useFileTree.ts`
- `.docs/repos/superset/packages/workspace-client/src/hooks/useFileDocument/useFileDocument.ts`
- `.docs/repos/superset/packages/workspace-client/src/lib/workspaceFsEventRegistry.ts`

### 4. Selected-First Metadata and Port Refresh

Selected workspace:

- fast cadence
- immediate refresh on relevant change
- full UX fidelity

Background workspaces:

- low-priority hydration
- targeted refresh only
- no full file-stream churn

This aligns with `supacode` and `cmux`.

## Branch Status

These items are already landed or largely landed in the current branch and must be preserved:

### Done

- editor load-state fanout removed from tab-strip invalidation
- tab metadata reconciliation made incremental
- persistent terminal host prewarm added
- startup-profile port refresh storms reduced
- full recursive worktree file-stream watching scoped to selected worktree only
- worktree metadata priming changed to selected-first plus deferred hydration
- worktree metadata cadence split between selected and background worktrees
- worktree status summary path moved to lightweight `statusSummary()`
- PR creation refresh scoped to selected worktree
- identical port-observation contexts deduplicated
- initial performance instrumentation added:
  - `Apps/mac-client/Sources/mac/Services/WorkspacePerformanceRecorder.swift`
  - refresh-reason logging in metadata and port stores
- initial subscription-driven file-tree lifecycle landed:
  - `FileTreeModel.activate()`
  - `FileTreeModel.deactivate()`
  - root-scoped file-tree model caching in `AppContainer`
- incremental repository catalog refresh work landed:
  - `WindowWorkspaceCatalogStore`
  - `RepositoryNavigatorCatalogPlanner`

### Partially Done

- `WorktreeRuntimeRegistry` exists, but workspace activation still eagerly creates and refreshes git runtime
- `WindowWorkspaceCatalogStore` exists, but selection paths still await refresh work before visible restore
- file-tree lifetime is better, but filesystem observation is still per-directory and model-owned rather than shared per workspace/root

### Still Not Good Enough

- steady-state git status for the files sidebar still expands ignored paths
- file-tree git decoration index is rebuilt in render from `store.allChanges`
- file open still reads full file contents up front and hydrates full `TextDocument` on the open path
- workspace selection still blocks on catalog refresh in cold paths
- root `ContentView` still coordinates too much feature state
- port inference still relies too much on periodic shell-outs

## Root Cause Summary

The app still slows down when local interactions trigger global work.

The remaining root causes are:

1. The steady-state git path still does explorer-oriented ignored-file expansion.
2. The file sidebar rebuilds expensive git decoration state in `ContentView.body`.
3. Editor preview loading is not bounded by size or mode.
4. Workspace selection still awaits refresh work before restoring UI in some paths.
5. File watching and directory invalidation are still model-local instead of shared service-local.
6. Root view observation still owns too much coordination.

## Workstreams

## WS1: Remove Guaranteed Waste From The Critical Path

### PERF-WP-001: Remove ignored-file expansion from steady-state sidebar and workspace runtime

Status: `done`

Problem:

- `GitStore.refresh()` calls `gitService.status()`
- `GitClient.status()` always expands ignored paths
- this repo returns `82,874` ignored paths and costs about `1.26s`

Implementation:

- split git status APIs into:
  - default tracked/untracked/conflict status for steady-state UI
  - explicit ignored-aware explorer status only when truly needed
- ensure selected workspace runtime activation does not call the ignored-aware path
- make ignored-file enumeration opt-in and subtree-scoped if kept at all

Primary files:

- `Packages/Git/Sources/Git/Services/Client/GitClient.swift`
- `Packages/Git/Sources/Git/Services/Client/GitClient+StatusHelpers.swift`
- `Packages/Git/Sources/Git/Models/GitStore.swift`

Acceptance:

- steady-state files sidebar path does not run `git ls-files --others -i --exclude-standard`
- warm git refresh on a repo like this one is dominated by tracked status only
- instrumentation shows at least `70%` improvement in steady-state git refresh time on this repo
- ignored files still remain available only through an explicit non-default path if product still needs them

### PERF-WP-002: Move file-tree git decoration indexing out of render

Status: `done`

Problem:

- `ContentView.sidebarContent` rebuilds `WorkspaceFileTreeGitStatusIndex` inside view render
- current payload size makes that rebuild cost about `135ms`

Implementation:

- build and cache the git status index in a dedicated runtime/store layer
- key cache invalidation to relevant git change set mutations
- pass a stable reference into the file tree instead of reconstructing during body evaluation

Primary files:

- `Apps/mac-client/Sources/mac/Views/Window/ContentView+Sidebar.swift`
- `Apps/mac-client/Sources/mac/Models/WorkspaceFileTreeGitStatusIndex.swift`
- `Apps/mac-client/Sources/mac/Services/WorktreeRuntimeRegistry.swift`

Acceptance:

- no `WorkspaceFileTreeGitStatusIndex(...)` construction occurs inside `ContentView.body`
- file open while files sidebar is visible does not reprocess the full git change set
- git decoration refresh updates only when the underlying git change set changes

### PERF-WP-003: Make active runtime creation lazy and cheap

Status: `done`

Problem:

- `WorktreeRuntimeRegistry.makeGitStore()` immediately refreshes git and PR availability on creation

Implementation:

- create git runtime without synchronous heavy refresh on activation
- separate runtime creation from runtime hydration
- trigger selected-first hydration after shell restore rather than before it

Primary files:

- `Apps/mac-client/Sources/mac/Services/WorktreeRuntimeRegistry.swift`

Acceptance:

- selecting a workspace does not await git refresh before restoring visible shell state
- git hydration starts after restore and only for the selected workspace

## WS2: Make File Open Bounded, Two-Phase, and Revision-Aware

### PERF-WP-010: Introduce bounded preview reads

Status: `done`

Problem:

- `DefaultDocumentIOService.loadPreview()` reads the whole file as `String`
- there is no `maxBytes`, binary detection, or revision token

Implementation:

- add a bounded read API for editor preview loading
- include:
  - `maxBytes`
  - `revision`
  - text vs bytes mode
  - exceeded-limit signal
- use the bounded result to decide:
  - preview text
  - binary placeholder
  - too-large placeholder
  - full hydration eligibility

Primary files:

- `Packages/Editor/Sources/Editor/Services/DocumentIOService.swift`
- `Apps/mac-client/Sources/mac/Models/EditorSession.swift`

Acceptance:

- opening a large file does not read the full contents just to decide it is too large
- binary and too-large files short-circuit before full `TextDocument` creation
- preview reads return an opaque revision token for later reload/conflict checks

### PERF-WP-011: Keep file open strictly two-phase

Status: `done`

Problem:

- file open currently does preview and `TextDocument` preparation on the same open path

Implementation:

- phase 1:
  - create/reuse preview tab immediately
  - show bounded preview result or lightweight placeholder
- phase 2:
  - hydrate `TextDocument` only if file is eligible and tab/session is still current
- do not restart work for preview tab reuse unless URL or revision actually changed

Primary files:

- `Apps/mac-client/Sources/mac/Models/EditorSession.swift`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+Tabs.swift`
- `Apps/mac-client/Sources/mac/Views/Window/TabContentView.swift`

Acceptance:

- preview tab creation is synchronous from the user’s perspective
- stale hydration work cannot leak into a reused preview tab
- opening one file must not trigger reload of unrelated editor sessions

### PERF-WP-012: Add editor-open instrumentation with hard checkpoints

Status: `done`

Implementation:

- instrument:
  - click to preview tab visible
  - preview tab visible to preview content visible
  - preview content visible to full interactive text document
- emit file size bucket, file extension, and outcome classification

Acceptance:

- the budgets in this document can be measured directly from logs
- manual profiling does not require guessing where the time went

## WS3: Make Workspace Selection Restore First, Refresh Second

### PERF-WP-020: Stop awaiting repository refresh before visible restore on known workspaces

Status: `done`

Problem:

- current repository/workspace selection paths await `refreshRepositoryCatalog()` before restore in cold cases

Implementation:

- treat selection as:
  - update catalog pointer
  - restore cached shell immediately if runtime already exists
  - schedule catalog refresh and metadata hydration after visible restore
- only block when selection target literally cannot be resolved

Primary files:

- `Apps/mac-client/Sources/mac/Views/Window/ContentView+StateSync.swift`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+WorkspaceState.swift`
- `Apps/mac-client/Sources/mac/Services/WindowWorkspaceCatalogStore.swift`

Acceptance:

- switching to a known workspace never blocks on metadata or file-tree refresh
- workspace restore logs show restore completing before deferred hydration work starts

Completion notes:

- `selectRepository(_:)` now restores immediately for catalog-known workspaces and schedules `selection-refresh-deferred` hydration after first visible restore
- `selectWorkspace(_:in:)` only blocks on catalog refresh when the target workspace cannot already be resolved from cached catalog state
- `WindowWorkspaceCatalogStore` exposes repository/workspace resolvability so selection logic can choose restore-first versus blocking refresh explicitly

### PERF-WP-021: Finish the catalog/runtime ownership split

Status: `done`

Problem:

- there is still too much state translation between catalog, runtime, sidebar, metadata, and ports

Implementation:

- `WindowWorkspaceCatalogStore` owns catalog truth
- `WorktreeRuntimeRegistry` owns per-worktree runtime truth
- root view only binds to selected catalog item plus selected runtime handle

Acceptance:

- selection is a pointer, not a state migration
- no feature has to translate between duplicate repo/worktree caches

Completion notes:

- `WorktreeRuntimeRegistry` now exposes an explicit active runtime handle with worktree, shell state, git store, file tree model, and git status index
- current-workspace UI paths now bind to the active runtime handle instead of re-reading the selected worktree from catalog state
- restore paths now pass the resolved `Worktree` directly into runtime restore instead of resolving the same workspace from catalog state again

## WS4: Shared Filesystem and Watch Infrastructure

### PERF-WP-030: Replace model-local file watching with shared workspace/root watcher ownership

Status: `done`

Problem:

- current `FileTreeModel` owns per-directory watchers via `FileSystemWatcher`
- invalidation model is coarse and reload-oriented

Implementation:

- introduce one shared watcher service per workspace/root
- support:
  - incremental directory invalidation
  - coalesced event delivery
  - multiple listeners over one transport
- keep mounted UI subscription-driven

Primary files:

- `Packages/Workspace/Sources/Core/Services/FileSystemWatcher.swift`
- `Packages/Workspace/Sources/Core/Models/FileTreeModel.swift`
- `Apps/mac-client/Sources/mac/Services/AppContainer.swift`

Reference:

- `.docs/repos/superset/packages/workspace-client/src/lib/workspaceFsEventRegistry.ts`

Acceptance:

- two consumers of the same workspace root do not create two separate watcher stacks
- expanding/collapsing the sidebar only changes listener counts, not root watcher identity
- rename, delete, and overflow scenarios are covered by tests

Completion notes:

- shared root watcher ownership now lives in `SharedFileWatchRegistry`, which fans out one recursive root transport to multiple consumer-specific watcher clients
- `FileTreeModel` now reuses its watcher client across activate/deactivate and no longer recreates watcher stacks on refresh or sidebar remount
- recursive watcher overflow flags now map to an explicit `.overflow` change type and file tree tests cover delete, rename, and overflow full-reload fallback behavior

### PERF-WP-031: Make file-tree loading incremental and invalidation-based

Status: `done`

Problem:

- current tree model rebuilds root state too often and treats delete/rename as reload-all fallback

Implementation:

- track:
  - loaded directories
  - invalidated directories
  - expanded directories
- refresh only affected directories on event paths
- keep full reload as overflow fallback only

Acceptance:

- common file mutations in one directory do not rebuild unrelated tree state
- tree expansion state survives rename/move when paths can be retargeted safely

Completion notes:

- `FileTreeModel` now tracks loaded, invalidated, and expanded directory sets explicitly and refreshes only the affected loaded directory on common file mutation paths
- delete handling prunes only the missing subtree, while overflow remains the only full-reload fallback
- rename handling retargets expansion and loaded-directory state onto the new path when the move is safe, preserving visible tree state without rebuilding unrelated branches
- directory URL normalization now canonicalizes path-equivalent trailing-slash variants so invalidation keys and loaded-directory keys match reliably

## WS5: Port and Runtime Ownership Must Be Event-Led

### PERF-WP-040: Make ownership-led port truth the default

Status: `done`

Problem:

- port detection still depends too heavily on periodic global inference

Implementation:

- use Devys-managed process ownership as primary truth
- use hosted terminal ownership as primary truth where available
- use inference only for unmanaged or unknown processes
- split selected-workspace and background inference cadence

Primary files:

- `Apps/mac-client/Sources/mac/Services/WorkspacePortStore.swift`
- `Apps/mac-client/Sources/mac/Services/WorkspacePortStore+Lifecycle.swift`
- `Apps/mac-client/Sources/mac/Services/WorkspacePortManagedProcessCatalog.swift`
- `Apps/mac-client/Sources/mac/Services/WorkspacePortOwnershipCoordinator.swift`

Acceptance:

- managed process start/stop updates port state without waiting for global scan
- background workspaces do not pay selected-workspace inference cadence

Completion notes:

- `WorkspacePortStore` now has a context-only update mode plus explicit selected and background periodic refresh lanes, so active selection scans stay focused while background workspaces rotate on a slower cadence
- managed process deltas still refresh only the owning workspace, but they now do so immediately through the active repository store instead of waiting on a coordinator debounce
- `WorkspacePortOwnershipCoordinator` now keeps every repository store structurally current while only letting the active repository enter refresh-on-change mode

### PERF-WP-041: Make port refresh reasons first-class and enforceable

Status: `done`

Implementation:

- every port refresh must record reason and workspace count
- add assertions in tests for:
  - no-op context changes
  - managed process launch
  - managed process exit
  - selected periodic
  - manual

Acceptance:

- regressions can be tied to one explicit refresh source
- no future refactor can silently reintroduce global periodic scans

Completion notes:

- `WorkspacePortStore` now records every executed refresh as a `WorkspacePortRefreshRecord` with explicit reason, workspace IDs, workspace count, and duration
- pending refreshes are now queued as reason-preserving `WorkspacePortRefreshRequest` values instead of collapsing into one anonymous follow-up pass
- managed process deltas are classified into `managedProcessLaunch`, `managedProcessExit`, or `contextChange`, so port refreshes remain attributable after future refactors
- coverage now locks the acceptance criteria in place with explicit suites for no-op context updates, managed process launch, managed process exit, selected periodic refresh, background periodic refresh, and manual refresh

## WS6: Root Observation and Render Isolation

### PERF-WP-050: Break `ContentView` into narrower feature surfaces

Status: `done`

Problem:

- root still coordinates too many reactive concerns

Implementation:

- isolate:
  - workspace selection shell
  - tab presentation
  - launcher/runtime controls
  - navigator metadata
  - notifications/attention
- remove render-time derivations that belong in stores

Primary files:

- `Apps/mac-client/Sources/mac/Views/Window/ContentView.swift`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+Lifecycle.swift`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+Sidebar.swift`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+StateSync.swift`

Acceptance:

- changing file selection, git state, or port state does not invalidate unrelated shell surfaces
- profiling shows narrower body recomputation scope in the main workspace shell

Completion notes:

- `ContentView` now delegates navigator, sidebar, workspace canvas, toolbar, status bar, command palette, and notifications to dedicated observation surfaces instead of reading all repository/runtime state directly in the root shell
- root shell composition in `ContentView` now depends on stable store references and local shell layout state, while feature surfaces observe their own repository/runtime slices
- sidebar port-label indexing moved into `RepositorySettingsStore.portLabelsByPort(for:)`, removing the last inline `[Int: RepositoryPortLabel]` derivation from render-time sidebar construction
- validation covers the new store-owned derivation in `RepositorySettingsStoreTests` and app-target compilation/runtime wiring through the existing workspace/runtime and attention suites

## Validation Plan

Every completed workstream must add or update:

- unit tests for state and ownership behavior
- timing logs for the affected interaction
- one manual validation note in the PR or handoff

Minimum manual matrix:

1. This repo with many ignored files and a dirty worktree
2. A small clean repo
3. A repo with multiple linked worktrees
4. A workspace with the files sidebar open
5. A workspace with the files sidebar hidden

Minimum interaction matrix:

1. Single-click file preview repeatedly across different files
2. Double-click permanent open
3. Switch between two known workspaces repeatedly
4. Switch repositories
5. Launch `Claude`, `Codex`, `Shell`, and `Run`

## What Must Not Happen

The following are not acceptable fixes:

- adding another debounce where ownership should be corrected
- hiding slow paths behind a spinner without removing the work
- moving critical-path work from one root observer to another
- reintroducing whole-repository ignored-file expansion on steady state
- reintroducing full-system `lsof` / `ps` scans as default runtime truth
- recreating runtime objects on view mount/unmount churn

## Order Of Execution

This is the implementation order unless a measurement proves otherwise:

1. `PERF-WP-001` remove ignored-file expansion from steady-state paths
2. `PERF-WP-002` move file-tree git decoration indexing out of render
3. `PERF-WP-010` bounded preview reads
4. `PERF-WP-011` strict two-phase editor hydration
5. `PERF-WP-020` restore-first workspace selection
6. `PERF-WP-021` finish catalog/runtime ownership split
7. `PERF-WP-030` shared watcher ownership
8. `PERF-WP-031` incremental invalidation-based file tree
9. `PERF-WP-040` ownership-led port truth
10. `PERF-WP-050` root observation isolation

## Definition Of Done

This plan is complete only when:

- the budgets in this document are met on representative local repos
- ignored-file expansion is not on the steady-state path
- file open is bounded, revision-aware, and two-phase
- workspace switch restores first and refreshes second
- filesystem watchers are shared and subscription-driven
- port truth is event-led first and inferred second
- root render churn is measurably reduced
- the instrumentation and tests make regressions obvious
