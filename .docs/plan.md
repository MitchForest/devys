# Devys Plan: Repository and Workspace-Native Shell

Updated: 2026-04-06

## Goal

Move Devys from its current folder-first shell to a repository-first, workspace-first product where:

- one window can contain multiple repositories
- each repository can contain multiple workspaces
- each workspace is exactly one branch and one isolated git worktree
- each workspace owns its own:
  - working directory
  - terminals
  - notifications
  - diffs
  - files
  - ports
  - later chat sessions
- the UI shell is organized around repository and workspace context rather than a global app rail

This plan is written to get from the current codebase to that end state with strict, testable tickets.

## Roadmap Status

Current status as of 2026-04-06:

- Phase 0 is complete:
  - `DVYS-001`
  - `DVYS-002`
  - `DVYS-003`
- Phase 1 is complete:
  - `DVYS-010`
  - `DVYS-011`
  - `DVYS-012`
  - `DVYS-013`
  - `DVYS-014`
- Phase 2 is complete:
  - `DVYS-020`
  - `DVYS-021`
  - `DVYS-022`
- Phase 3 is complete:
  - `DVYS-030`
  - `DVYS-031`
  - `DVYS-032`
  - `DVYS-032A`
  - `DVYS-033`
  - `DVYS-034`
- Phase 4 is complete:
  - `DVYS-040`
  - `DVYS-041`
  - `DVYS-042`
- Phase 5 is complete:
  - `DVYS-050`
  - `DVYS-051`
  - `DVYS-052`
- Phase 6 is complete:
  - `DVYS-060`
  - `DVYS-061`
  - `DVYS-062`
  - `DVYS-063`
- Phase 7 is complete:
  - `DVYS-070`
  - `DVYS-071`
  - `DVYS-072`
  - `DVYS-073`
- Phase 8 is complete:
  - `DVYS-080`
  - `DVYS-081`
- Phase 9 is complete:
  - `DVYS-090`
  - `DVYS-091`
  - `DVYS-092`

Remaining roadmap scope:

- none in this plan
- any follow-on work should start in a new plan rather than reopening closed tickets here

What is now implemented:

- first-class `Repository` and `Workspace` domain models with stable identity and persistence boundaries
- window shell state for multiple repositories plus selected workspace
- explicit global vs repository vs workspace-owned settings/state split
- repository/workspace navigator shell column replacing the old app rail
- strict repository import with recent repository persistence
- workspace creation/import for new branch, existing branch, PR, and existing worktree flows
- navigator workspace metadata for branch, ahead/behind, dirty summary, PR, checks, and line changes
- navigator row actions for pin, archive, unarchive, rename, delete, reveal in Finder, and open in external editor
- workspace-scoped sidebar mode and workspace-scoped split canvas state
- workspace-owned tab identity for editor, diff, and terminal content
- workspace-owned terminal registry, toolbar launch actions, and repository-scoped Claude/Codex launcher profiles
- repository-scoped startup profiles with multi-step `Run` fanout and managed background processes
- Devys-managed detached terminal host with relaunch reattachment when enabled in global settings
- workspace-owned attention model with unread, waiting, and completed notification state
- workspace navigator attention badges and latest-unread routing
- documented terminal-agent notification ingress plus distributed app bridge
- Claude workspace-local hook installation and launcher identity export for workspace/terminal ownership
- notifications panel with workspace-aware open and clear actions
- explicit no-tmux default architecture for core terminal persistence
- workspace-owned port detection with managed-process ownership, process inference, and conflict tracking
- navigator, sidebar, and status surfaces for workspace port counts and active port listings
- workspace port actions for open, copy URL, and stop process
- repository-scoped static port labels with scheme and path metadata
- repository settings UI for port labels plus persistence coverage in Workspace package tests
- workspace-native `Changes` sidebar with staged, unstaged, untracked, and ignored sections
- shell Git actions for fetch, pull, push, commit, create PR, and open PR from workspace surfaces
- workspace-scoped file tree Git indicators derived from active workspace status
- explicit upstream state in navigator and status surfaces, including `NO UPSTREAM` vs `UP TO DATE`
- repository-centric launch page with recent repositories and `Restore Previous Session`
- global notification and restore settings with backward-compatible persistence
- repository settings for workspace creation defaults, launcher defaults, startup profiles, default `Run` profile, and port labels
- restore behavior for repositories, selected workspace, workspace layout, editor/diff tabs, and hosted terminal sessions behind explicit global toggles
- workspace-native command palette that routes directly into repository, workspace, launcher, and notification flows
- editable workspace-shell shortcuts stored in app settings with duplicate detection, reserved binding detection, and per-action or full default restore
- regression and responsiveness hardening for workspace isolation, workspace switching, port refresh, and navigator ordering at 10 repositories and 100 workspaces
- remaining single-folder shell assumptions removed from the active mac client shell surfaces covered by this roadmap

Verification status:

- `swift test` passes in `Packages/Workspace`
- `swift test` passes in `Packages/Git`
- `DEVYS_SKIP_APP_PERIPHERY=1 ./scripts/quality-gate.sh` passes
- `./scripts/build-mac-client.sh` passes and is the canonical CLI verification path for the active app
- `xcodebuild test -project Devys.xcodeproj -scheme mac-client -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` passes through the repo quality gate
- targeted Phase 4 verification passes:
  - `xcodebuild test -project Devys.xcodeproj -scheme mac-client -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:mac-clientTests/WorkspaceAttentionStoreTests -only-testing:mac-clientTests/WorkspaceAttentionIngressTests`
- targeted Phase 5 verification passes:
  - `xcodebuild test -project Devys.xcodeproj -scheme mac-client -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:mac-clientTests/WorkspacePortStoreTests`
- targeted Phase 7 verification passes:
  - `xcodebuild test -project Devys.xcodeproj -scheme mac-client -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO -only-testing:mac-clientTests/WindowStateTests -only-testing:mac-clientTests/WorkspaceAttentionStoreTests -only-testing:mac-clientTests/TerminalRelaunchSnapshotTests`
- targeted Phase 8 and 9 verification passes:
  - `xcodebuild test -project Devys.xcodeproj -scheme mac-client -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO -only-testing:mac-clientTests/WorkspaceShellShortcutSupportTests -only-testing:mac-clientTests/WindowStateTests -only-testing:mac-clientTests/TerminalRelaunchSnapshotTests -only-testing:mac-clientTests/WorkspacePortStoreTests`
- raw `xcodebuild -target ...` verification is stale for this repo and should not be used as the source of truth
- the canonical CLI build path is now warning-clean through `generic/platform=macOS`

Roadmap closeout notes:

- there is no remaining open ticket in this roadmap
- keep the same implementation rules for any follow-on work:
  - no backwards-compatibility shims
  - no new generic abstraction layers
  - workspace owns runtime state directly
  - shell views render state and invoke closures; side effects stay in shell/state services
- key implementation locations for the closed-out Phase 8 and 9 work:
  - `Apps/mac-client/Sources/mac/Services/DevysApp.swift`
  - `Apps/mac-client/Sources/mac/Models/NotificationNames.swift`
  - `Apps/mac-client/Sources/mac/Models/WorkspaceShellShortcutSupport.swift`
  - `Apps/mac-client/Sources/mac/Views/Window/ContentView+CommandPalette.swift`
  - `Apps/mac-client/Sources/mac/Views/Window/WorkspaceCommandPaletteView.swift`
  - `Apps/mac-client/Sources/mac/Views/Settings/SettingsView.swift`
  - `Packages/Workspace/Sources/Core/Models/WorkspaceShellShortcutSettings.swift`
  - `Apps/mac-client/Tests/mac-clientTests/WorkspaceShellShortcutSupportTests.swift`
  - `Apps/mac-client/Tests/mac-clientTests/WindowStateTests.swift`
  - `Apps/mac-client/Tests/mac-clientTests/TerminalRelaunchSnapshotTests.swift`

Phase 4 completion notes:

- workspace attention is now owned by `WorkspaceAttentionStore` and rendered through workspace navigator metadata
- built-in Claude launch now installs workspace-local hooks and emits waiting/completed notifications through the `--workspace-notify` and `--workspace-notify-hook` ingress
- Codex notification integration is explicitly unavailable for the built-in plain CLI path and Devys reports that rather than faking hooks
- latest-unread routing and notifications panel are implemented as workspace navigation, not terminal-only navigation

Phase 5 completion notes:

- `DVYS-050` is complete through `WorkspacePortStore`, navigator/status integration, and workspace sidebar `Ports` mode
- `DVYS-051` is complete through explicit `owned` / `unowned` / `conflicted` rendering plus open, copy, and stop actions
- `DVYS-052` is complete through `RepositorySettings.portLabels`, repository settings UI, and persistence coverage
- Devys-managed startup profile steps now provide the authoritative ownership path for managed background processes, with inference only as fallback
- port conflicts remain explicit and visible; ownership is never silently collapsed to one workspace

Phase 6 completion notes:

- `DVYS-060` is complete through the active workspace `Changes` sidebar mode backed by `GitSidebarView`
- `DVYS-061` is complete through existing shell surfaces such as `StatusBar`, workspace toolbar actions, and navigator metadata rather than a separate Git dashboard
- `DVYS-062` is complete through per-file Git status in the file tree row model plus aggregated dirty state at directory rows
- `DVYS-063` is complete through explicit local vs remote state in navigator and status surfaces when that data is available
- Git state remains workspace-scoped; no repository-global cache is used to leak status across workspaces

Phase 8 completion notes:

- `DVYS-080` is complete through the workspace-native command palette and direct routing into existing repository, workspace, launcher, and unread-notification flows
- shipped command-palette coverage includes switch repository, switch workspace, create workspace, import worktrees, add repository, launch `Shell`, launch `Claude`, launch `Codex`, run the default profile, jump to latest unread workspace, and reveal the current workspace in the navigator
- `DVYS-081` is complete through explicit `WorkspaceShellShortcutSettings` persistence, shared menu/settings bindings, duplicate binding detection, reserved binding detection, per-action restore, and restore-all-defaults
- keep the command palette as a thin router over explicit shell actions rather than a second command graph
- keep shortcut definitions in shared settings models so menus and settings UI continue to resolve from one source of truth

Phase 9 completion notes:

- `DVYS-090` is complete through direct regression coverage for workspace selection, tab-layout restore isolation, and workspace-owned port state
- `DVYS-091` is complete through responsiveness coverage for workspace switching, navigator ordering, and background port refresh at 10 repositories and 100 workspaces
- `DVYS-092` is complete through removal of active shell assumptions that still treated the app as single-folder-first
- keep Phase 9 guarantees enforced with direct tests instead of compatibility shims or fallback behavior

## Historical Design Record

The remainder of this document preserves the rationale, architectural decisions, and acceptance criteria that drove the shipped roadmap. `Roadmap Status` above is the source of truth for current completion state.

## Executive Decisions

These are the architectural decisions this plan assumes.

### 1. Workspace is the main runtime primitive

Definition:
- one workspace = one branch = one git worktree = one working directory

Consequence:
- Git state, terminals, ports, notifications, file tree state, and layout are all workspace-scoped

### 2. The active canvas is single-workspace

Definition:
- the split/tab canvas always belongs to exactly one selected workspace

Consequence:
- switching workspace swaps the active sidebar and canvas state
- cross-workspace panes are not supported by default

### 3. Repository navigator replaces the current app rail

Definition:
- the leftmost shell is a repository/workspace navigator, not `Files / Git / Agents / Settings`

Consequence:
- files and changes move into a contextual workspace sidebar

### 4. Terminal agents are first-class now, chat agents later

Definition:
- Claude Code and Codex launch into workspace terminals first
- future chat is a separate pane type, not a shell primitive for v1

### 5. No tmux as the default persistence model

Decision:
- do not require tmux for workspace switching or app restart

Reason:
- switching workspaces does not require tmux if PTY sessions are owned by long-lived workspace runtime state
- app restart persistence is better handled by a Devys-managed terminal host/daemon than by exposing tmux as a hard dependency
- tmux can remain optional for power users later, but it should not define Devys core UX

### 6. Ports are workspace-scoped, not globally assigned

Decision:
- Devys should detect running ports per workspace and expose conflicts explicitly
- Devys should not invent mandatory workspace port ranges as a default policy

Reason:
- Superset is right here: per-workspace ownership and detection are more flexible
- deterministic port allocation can be layered later through presets or run scripts

## Original Starting Point (Historical Context)

This section preserves the starting conditions that justified the roadmap. The shipped state is captured in `Roadmap Status` above.

Current strengths:
- native macOS shell
- split/tab canvas
- custom editor
- strong Git package
- worktree-aware models and status
- Ghostty-backed terminal surface
- appearance and explorer settings

Original gaps:
- shell is still one-folder-per-window
- no multi-repo model
- no active worktree navigator
- no workspace-scoped canvas
- no terminal persistence strategy beyond current in-process session objects
- no preset system for Claude Code or Codex
- no first-class notifications center or waiting-state model
- no ports model
- no file explorer Git status indicators

## Target End State

```text
+----------------------+---------------------------+--------------------------------------+
| Repositories         | Workspace Sidebar         | Workspace Canvas                     |
| and Workspaces       | Files | Changes | Ports   | editor / terminal / diff / later     |
|                      |                           | browser / chat                       |
| Repo A               | scoped to active         | scoped to active workspace           |
|   main               | workspace only           | only                                 |
|   feat/auth          |                           |                                      |
|   pr/182             |                           |                                      |
|                      |                           |                                      |
| Repo B               |                           |                                      |
|   main               |                           |                                      |
|   fix/nav            |                           |                                      |
+----------------------+---------------------------+--------------------------------------+
| Status Bar: repo, workspace, branch, ahead/behind, PR, checks, ports, waiting state      |
+------------------------------------------------------------------------------------------+
```

## Settings Scope Model

This is the target settings split.

### Global settings

Applies across all windows and repositories.

Examples:
- appearance
- keyboard shortcuts
- notification preferences
- default external editor
- default terminal font and behavior
- whether terminal persistence survives relaunch
- whether Devys restores previous repositories on launch

### Repository settings

Applies to one repository and all its workspaces unless overridden.

Examples:
- default base branch
- workspace naming rules
- copy ignored/untracked behavior on workspace creation
- terminal presets available in this repository
- default launcher profiles for built-in agent actions
- startup profiles for multi-service development environments
- static port labels and optional run scripts
- GitHub integration preferences for that repository

### Workspace settings or state

Mostly runtime and ephemeral, with selective persistence.

Examples:
- selected sidebar mode
- files tree expansion
- open tabs and split layout
- active terminals
- current port ownership
- PR linkage
- unread or waiting state
- last focused pane

Rule:
- workspace should own runtime state, not broad configuration

## Terminal Persistence Strategy

### Workspace switching

Requirement:
- switching away from a workspace must not kill terminals

Approach:
- terminal sessions are owned by workspace runtime state, not by visible SwiftUI views
- switching workspace hides the session surface but does not terminate the PTY

Acceptance definition:
- a long-running process continues while its workspace is inactive

### App close and relaunch

Requirement:
- user-configurable persistence across app restarts

Recommended approach:
- build a Devys terminal host process or daemon that owns PTYs outside the main app process
- the app reconnects to that host on relaunch

Non-goal for v1:
- tmux requirement

Why not tmux by default:
- adds external dependency and user mental model overhead
- creates mismatch between Devys tabs/splits and tmux windows/panes
- makes notifications, per-workspace metadata, and pane ownership harder to reason about cleanly

Possible later advanced option:
- allow “run inside tmux” preset mode for power users

## Port Management Strategy

### Core behavior

Ports belong to workspaces.

Devys should:
- detect listening ports from processes associated with a workspace
- show them in workspace UI
- show collisions clearly
- allow opening previews and killing the owning process

### Ownership model

Primary rule:
- processes launched by Devys for a workspace are tagged with that workspace ID
- ports opened by those processes, or by their descendants, belong to that workspace

Fallback rule:
- if a process was not launched by Devys, ownership may be inferred from cwd, process ancestry, and worktree path
- if ownership is ambiguous, the port is marked `unowned` or `conflicted` rather than silently assigned

### Conflict model

If two workspaces both try to run the same service port:
- show conflict state in both workspaces
- do not silently reassign
- provide quick actions:
  - open the live one
  - stop the conflicting process
  - copy URL

### Default model

Do not enforce per-workspace port offsets by default.

Optional later repository-level support:
- static port labels
- deterministic port environment variables in presets or run scripts

## Launcher and Startup Profile Strategy

These need to be first-class.

### Two distinct concepts

Devys should support two different profile types:

- `Launcher Profiles`
  - one-click actions that launch a single terminal command
  - examples: normal shell, Claude Code, Codex

- `Startup Profiles`
  - multi-step development environment orchestration for a repository
  - launches multiple terminals or managed processes for the active workspace
  - examples: API server, web app, database, ngrok, worker

These solve different problems and should not be collapsed into one abstraction.

### Built-in launch types

Every workspace should support one-click launch for:
- normal terminal
- Claude Code via a built-in editable launcher profile
- Codex via a built-in editable launcher profile

### Editable launcher profiles

Repository settings should allow editable launcher profiles for:
- `Claude Code`
- `Codex`

These are shipped defaults, not fixed command names.

Each launcher profile should support:
- base command
- dangerous permissions flag toggle
- model
- reasoning level
- extra arguments
- optional “run immediately” vs “stage command in terminal”

Optional later convenience:
- import an existing shell alias or function as the starting command
- but imported alias names are never part of the core product model

### Startup profiles

Repository settings should allow defining startup profiles that can launch multiple steps for the active workspace.

Each startup profile should support:
- display name
- optional description
- ordered steps
- per-step cwd
- per-step command
- per-step env vars
- per-step launch mode
  - new tab
  - split
  - background managed process
- optional restart policy
- optional dependency ordering or readiness rules

Example startup profile:
- `API`: cwd `apps/api`, command `bun run dev`
- `Web`: cwd `apps/web`, command `bun run dev`
- `Supabase`: cwd repo root, command `supabase start`
- `Ngrok`: cwd repo root, command `ngrok http 3000`

### `Run` button behavior

The workspace toolbar `Run` button should launch the repository's default startup profile for the active workspace.

If no default startup profile exists:
- `Run` is unavailable until the repository defines a startup profile

### UX shape

Workspace toolbar should expose:
- `Shell`
- `Claude`
- `Codex`
- `Run`

Advanced editing belongs in settings, not the main toolbar.

## Git Integration Strategy

Git should be first-class, but focused on the 80/20:

### Must-have Git capabilities

- branch name and ahead/behind
- dirty counts
- staged/unstaged/untracked lists
- diff preview and persistent diff tabs
- commit
- push and pull
- fetch
- PR badge and checks state
- open PR in browser
- create PR

### Nice-to-have later

- richer review mode
- merge queue or deployment integration
- review comments and advanced GitHub threading

### File explorer Git status

Each file row should show workspace-specific Git status.

Minimum statuses:
- modified
- added
- deleted
- renamed
- untracked
- ignored

For directories:
- aggregate dirty indicators from descendants

## Launch Page Strategy

Current launch page is recent folders only. That will be replaced by the repository model.

New launch page should support:
- recent repositories
- restore last session
- add repository
- recent workspaces optionally

Primary action should become:
- `Add Repository`

Not:
- `Open Folder`

## Phases

The implementation should move in the following order:

1. Data model and shell architecture
2. Repository/workspace navigator
3. Workspace-scoped sidebars and canvas
4. Terminal host and launcher system
5. Notifications and port management
6. Git and explorer status parity
7. Launch page and settings overhaul

---

## Tickets

Each ticket below has strict acceptance criteria.

All tickets in this section are complete as of 2026-04-06. The acceptance criteria remain here as the historical completion bar for the shipped roadmap.

### Phase 0: Architecture Groundwork

#### DVYS-001: Define repository and workspace domain models

Scope:
- add first-class `Repository` and `Workspace` domain models
- preserve current worktree data where possible
- define identity, persistence keys, and relationships

Deliverables:
- model types
- persistence contracts

Acceptance criteria:
- there is a first-class `Repository` model with stable ID, root URL, display name, and settings reference
- there is a first-class `Workspace` model with stable ID, repository ID, branch name, worktree URL, and workspace kind
- `Workspace` explicitly represents one branch and one worktree only
- current single-folder assumptions are removed from the active architecture
- unit tests cover encode/decode and stable ID behavior

#### DVYS-002: Replace window-level folder state with repository/workspace selection state

Scope:
- replace `WindowState.folder` model with window shell state
- support multiple repositories per window and one selected workspace per window

Acceptance criteria:
- window state can represent zero or more repositories
- window state can represent exactly one selected workspace or no selection
- opening a repository updates the new state model instead of only setting a single folder
- no active shell code depends on `folder != nil` as the only “project loaded” condition
- unit tests cover selection behavior and empty-state behavior

#### DVYS-003: Define settings scopes and persistence boundaries

Scope:
- formalize global vs repository vs workspace settings

Acceptance criteria:
- settings types are split into global, repository, and workspace-owned state or settings
- repository settings can override launcher templates and workspace creation defaults
- workspace runtime state is not persisted in global settings blobs
- tests verify repository settings do not leak across repositories

### Phase 1: Repository and Workspace Navigator

#### DVYS-010: Build repository/workspace navigator shell column

Scope:
- replace current feature rail with repository/workspace navigator
- show repositories as top-level groups and workspaces as children

Acceptance criteria:
- the leftmost shell column no longer uses the current `Files/Git/Agents/Settings` rail as the primary navigation model
- repositories render as top-level sections
- workspaces render under their repository
- selecting a workspace updates active workspace state
- empty state supports adding a repository
- UI tests verify navigation selection updates the active workspace

#### DVYS-011: Implement repository import and recent repository persistence

Scope:
- add repository import flow
- persist recent repositories instead of only recent folders

Acceptance criteria:
- user can add one or multiple repositories
- only valid Git repositories are accepted
- invalid selections show actionable error states
- recent repositories persist across relaunch
- launch page uses recent repositories, not only recent folders

#### DVYS-012: Implement workspace creation flows

Scope:
- create workspace from:
  - new branch
  - existing branch
  - pull request
  - imported worktree

Acceptance criteria:
- new workspace modal supports all four flows
- creating a workspace produces a real git worktree on disk
- imported worktrees can be bulk-imported
- PR workspaces can be created from PR selection or pasted URL
- failures return explicit actionable messages
- integration tests cover creation and import flows

#### DVYS-013: Implement workspace row metadata and status badges

Scope:
- navigator rows display workspace metadata

Acceptance criteria:
- each workspace row shows branch name
- each row shows dirty summary
- each row shows ahead/behind when available
- each row shows PR badge and checks status when available
- each row shows unread or waiting indicator when present
- each row can show port count when ports exist

#### DVYS-014: Implement workspace row actions

Scope:
- context menu and row actions for common operations

Acceptance criteria:
- user can pin, archive, unarchive, rename, and delete workspace from the row or its context menu
- user can open workspace in Finder
- user can open workspace in configured external editor
- main worktree cannot be deleted accidentally
- destructive actions require confirmation

### Phase 2: Workspace-Scoped Sidebar and Canvas

#### DVYS-020: Replace current left sidebar modes with contextual workspace sidebar

Scope:
- move files and changes into a workspace-scoped sidebar column
- remove global app-section assumptions from the main shell

Acceptance criteria:
- selecting a workspace updates the middle sidebar contents
- middle sidebar exposes `Files` and `Changes` modes
- active mode persists per workspace
- files and changes are no longer modeled as global shell sections

#### DVYS-021: Make canvas state workspace-scoped

Scope:
- split and tab layout belongs to the active workspace
- switching workspace swaps layout and tab state

Acceptance criteria:
- each workspace has its own tab and split layout state
- switching workspaces restores the previously used layout for that workspace
- switching workspaces does not show tabs from another workspace
- inactive workspace state is preserved in memory without forcing visible rendering

#### DVYS-022: Make all tab content workspace-aware

Scope:
- update tab identity and content ownership so editors, terminals, and diffs belong to a workspace

Acceptance criteria:
- editor tabs are tied to one workspace
- diff tabs are tied to one workspace
- terminal tabs are tied to one workspace
- opening a file or diff from workspace A never resolves into workspace B tab state
- tests cover tab identity scoping

### Phase 3: Terminal Runtime and Persistence

#### DVYS-030: Introduce workspace terminal registry

Scope:
- store terminals under workspace ownership rather than window-global loose dictionaries

Acceptance criteria:
- every terminal session references a workspace ID
- terminals remain alive when their workspace is not selected
- switching workspace does not shut down background terminal processes
- terminal metadata and unread state remain consistent across workspace switches

#### DVYS-031: Build workspace terminal toolbar and one-click launcher UX

Scope:
- add first-class toolbar actions for shell, Claude, Codex, and run

Acceptance criteria:
- active workspace toolbar exposes `Shell`, `Claude`, `Codex`, and `Run`
- clicking `Shell` opens a normal terminal in the workspace root
- clicking `Claude` launches the configured `Claude Code` launcher profile
- clicking `Codex` launches the configured `Codex` launcher profile
- clicking `Run` launches the default startup profile for the active workspace when configured
- if no startup profile is configured, `Run` is disabled and the UI points to repository settings

#### DVYS-032: Add repository-scoped launcher profiles for built-in agent actions

Scope:
- editable repository settings for shipped Claude Code and Codex launcher profiles

Acceptance criteria:
- repository settings include editable launcher profiles for `Claude Code` and `Codex`
- launcher profiles support model override
- launcher profiles support reasoning level
- launcher profiles support dangerous permissions toggle
- launcher profiles support extra flags
- launcher profiles can launch immediately or stage command in terminal without Enter
- launcher profile resolution is tested
- the built-in action labels remain `Claude` and `Codex` even if the underlying command is edited
- no product requirement depends on alias names like `cc` or `cx`
- optional import from a shell alias or function is tracked as follow-up, not required for core functionality

#### DVYS-032A: Add repository-scoped startup profiles for multi-terminal workflows

Scope:
- editable repository settings for multi-step startup profiles

Acceptance criteria:
- repository settings can define one or more startup profiles
- each startup profile supports multiple ordered steps
- each step supports cwd, command, env vars, and launch mode
- launch modes include `new tab`, `split`, and `background managed process`
- one startup profile can be marked as the default `Run` action for the repository
- clicking `Run` in a workspace launches the default startup profile into that workspace only
- startup profile execution is tested for multi-step fanout behavior
- failures in one step are surfaced without silently hiding the rest of the profile state

#### DVYS-033: Build terminal host abstraction that survives app relaunch

Scope:
- introduce a Devys-managed terminal host process or daemon
- reconnect sessions after app relaunch

Acceptance criteria:
- terminal PTYs are owned outside the main UI process
- quitting and relaunching Devys can reconnect to surviving workspace terminal sessions when enabled in settings
- reconnect flow restores tab and pane ownership to the right workspace
- hard app crash does not automatically kill all PTYs when persistence is enabled
- behavior is gated by a user-visible global setting

#### DVYS-034: Explicitly defer tmux from core dependency status

Scope:
- document and enforce no-tmux default architecture

Acceptance criteria:
- core terminal persistence path does not require tmux installation
- no shipped feature requires tmux to function
- architecture doc explains why tmux is optional, not required

### Phase 4: Notifications and Waiting State

#### DVYS-040: Introduce workspace-level notification and waiting model

Scope:
- elevate notifications from terminal bell counts to workspace attention state

Acceptance criteria:
- notifications are owned by workspace
- a workspace can be marked waiting by a terminal agent event
- workspace row shows unread or waiting indicator
- active workspace clears unread state only when user acknowledges or focuses the relevant session

#### DVYS-041: Add hook-friendly terminal agent notifications

Scope:
- support Claude Code and Codex notification hooks similar to cmux

Acceptance criteria:
- Devys exposes a documented notification entry point for terminal agents
- built-in Claude Code and Codex launcher profiles can emit waiting and completed notifications into Devys
- waiting notifications include source metadata such as `Claude` or `Codex`
- if hook integration is unavailable, Devys reports that explicitly and does not emulate the signal path

#### DVYS-042: Implement latest-unread navigation and notifications panel

Scope:
- first-class notification navigation

Acceptance criteria:
- user can jump to latest unread workspace with a shortcut
- notifications panel lists pending notifications with workspace context
- opening a notification focuses the correct workspace and terminal or pane
- clearing a notification updates row badge state immediately

### Phase 5: Port Detection and Management

#### DVYS-050: Add workspace-scoped port model and detection service

Scope:
- detect listening ports for processes belonging to each workspace

Acceptance criteria:
- ports are associated to a workspace, not just globally listed
- ports launched from Devys-managed startup profile steps inherit the owning workspace automatically
- detection updates when workspace processes start or stop
- workspace row can expose port count
- active workspace can list current ports
- tests cover detection and cleanup

#### DVYS-051: Implement port actions and conflict handling

Scope:
- actions for open, copy, kill, and conflict display

Acceptance criteria:
- user can open `localhost:PORT`
- user can copy port URL
- user can stop the owning process from the port UI
- when two workspaces contend for the same port, both surfaces show conflict state
- conflict state does not silently reassign or hide ownership
- ambiguous ownership is rendered explicitly as `unowned` or `conflicted`

#### DVYS-052: Add repository-scoped static port labels

Scope:
- support static labels and optional port metadata in repository config

Acceptance criteria:
- repository settings or config can define port labels
- static labels override or augment dynamic display
- invalid config surfaces actionable errors
- label updates are detected without app restart

### Phase 6: Git and Explorer Integration

#### DVYS-060: Make `Changes` a first-class workspace sidebar mode

Scope:
- elevate changes list into workspace sidebar

Acceptance criteria:
- changes view is accessible from the active workspace sidebar
- staged, unstaged, and untracked sections are visible
- selecting a change opens diff preview in the active workspace canvas
- double-clicking opens persistent diff tab

#### DVYS-061: Surface 80/20 Git actions in active shell

Scope:
- first-class Git operations for common workflows

Acceptance criteria:
- active workspace exposes fetch, pull, push, commit, create PR, and open PR
- current branch, ahead/behind, and PR state are visible without opening a deep settings screen
- failures are surfaced in actionable language

#### DVYS-062: Add Git status indicators to file explorer

Scope:
- show per-file Git status in workspace file tree

Acceptance criteria:
- modified, added, deleted, renamed, untracked, and ignored states render distinctly
- directory rows aggregate descendant dirty state
- indicators are computed per workspace, not globally
- refreshing one workspace does not leak status into another

#### DVYS-063: Surface local vs remote Git state clearly

Scope:
- make local/remote state visible in row and status surfaces

Acceptance criteria:
- workspace navigator shows ahead/behind counts
- status bar shows branch and remote sync state when available
- PR badge and checks state are visible when GitHub integration is active
- no network state is silently assumed when unavailable

### Phase 7: Launch Page, Settings, and Configuration

#### DVYS-070: Replace folder-centric launch page with repository-centric launch page

Scope:
- redesign initial empty-state and launch experience

Acceptance criteria:
- launch page primary CTA is `Add Repository`
- launch page shows recent repositories
- launch page supports restoring previous session
- launch page can optionally show recent workspaces
- `Open Folder` is no longer the only primary onboarding path

#### DVYS-071: Add global settings sections for shell, notifications, and terminal persistence

Scope:
- expand global settings beyond appearance and explorer

Acceptance criteria:
- global settings include notification preferences
- global settings include terminal persistence toggle
- global settings include default external editor
- global settings include shortcut customization entry point
- settings persistence is tested

#### DVYS-072: Add repository settings for workspace creation and launcher defaults

Scope:
- repository-owned configuration UI

Acceptance criteria:
- repository settings include default base branch
- repository settings include copy ignored/untracked behavior
- repository settings include editable built-in launcher profiles for Claude Code and Codex
- repository settings include startup profiles for multi-service development environments
- repository settings include run command defaults
- repository settings include port label configuration

#### DVYS-073: Add workspace state restore behavior and controls

Scope:
- let users control how much workspace runtime state is restored

Acceptance criteria:
- Devys can restore open repositories
- Devys can restore selected workspace per window
- Devys can restore workspace layout and tabs
- Devys can restore terminal sessions when persistence is enabled
- users can disable restore behaviors globally

### Phase 8: Keyboard and Command Plane

#### DVYS-080: Implement global command palette

Scope:
- keyboard-native control plane

Acceptance criteria:
- command palette can switch workspaces
- command palette can create or import workspaces
- command palette can launch shell, Claude, Codex, and run actions
- command palette can jump to latest unread workspace
- command palette can reveal current workspace in navigator

#### DVYS-081: Add customizable shortcuts for workspace shell

Scope:
- support key bindings for major shell actions

Acceptance criteria:
- shortcuts for switching workspace, toggling sidebar, launching shell, launching Claude, launching Codex, and jumping to unread are user-editable
- conflicts are detected and surfaced
- defaults can be restored

### Phase 9: Validation and Hardening

#### DVYS-090: Add workspace-isolation regression tests

Scope:
- ensure no cross-workspace state leakage

Acceptance criteria:
- tests cover file tree isolation
- tests cover diff isolation
- tests cover terminal ownership isolation
- tests cover port ownership isolation
- tests cover tab layout restore isolation

#### DVYS-091: Add performance validation for large repository and workspace counts

Scope:
- ensure shell remains usable with many repos and workspaces

Acceptance criteria:
- navigator remains responsive with at least:
  - 10 repositories
  - 100 combined workspaces
- switching workspace does not freeze the UI
- background workspace updates do not thrash visible rendering

#### DVYS-092: Remove remaining single-folder shell assumptions

Scope:
- ensure the product no longer depends on the old shell model anywhere

Acceptance criteria:
- no active code path depends on `WindowState.folder`
- no user-facing primary action is named `Open Folder`
- no persistence service stores repository state as recent folders
- no compatibility shim remains between repository/workspace state and the old folder-first shell model

---

## Milestone Definition

The product reaches the intended end state for this plan when all of the following are true:

- a single window can hold multiple repositories
- each repository can hold multiple workspaces
- each workspace is one branch and one worktree
- the left shell is a repository/workspace navigator
- files and changes are workspace-scoped sidebar modes
- the main canvas is workspace-scoped
- Claude Code, Codex, and shell launch in one click inside the active workspace
- terminal sessions survive workspace switches
- terminal sessions can optionally survive app relaunch without tmux
- waiting notifications work at workspace level
- ports are detected and managed per workspace
- file explorer shows Git status per workspace
- global, repository, and workspace settings scopes are implemented cleanly
- launch page is repository-centric

## Recommended Build Order

Strict order:

1. `DVYS-001` through `DVYS-003`
2. `DVYS-010` through `DVYS-014`
3. `DVYS-020` through `DVYS-022`
4. `DVYS-030` through `DVYS-034`
5. `DVYS-040` through `DVYS-042`
6. `DVYS-050` through `DVYS-052`
7. `DVYS-060` through `DVYS-063`
8. `DVYS-070` through `DVYS-073`
9. `DVYS-080` and `DVYS-081`
10. `DVYS-090` through `DVYS-092`

## Non-Goals For This Plan

These are intentionally excluded from the first end-state:

- a full in-app agent chat platform
- browser automation parity with cmux
- mandatory tmux support
- cross-workspace mixed-pane layouts
- advanced GitHub code review threading and inline discussion management

Those can be planned separately after the workspace-native shell is complete.
