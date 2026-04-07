# Devys Workspace Shell and Primitives

Updated: 2026-04-06

## Implementation Snapshot

Current status as of 2026-04-06:

- Phases 0 through 9 are complete
- there is no remaining planned scope in the current workspace-shell roadmap

What now exists in the product:

- repository and workspace are first-class shell primitives
- the left column is a repository and workspace navigator rather than a global app rail
- the middle column is a workspace-scoped sidebar with `Files` and `Changes`
- the middle column now also includes a workspace-scoped `Ports` mode
- the main canvas is restored per workspace, including workspace-owned tabs and split layout
- workspace toolbars can launch `Shell`, `Claude`, `Codex`, and `Run`
- repository settings own launcher profiles and startup profiles
- terminal runtime is workspace-owned and survives workspace switching
- terminal persistence across app relaunch is implemented through a Devys-managed detached terminal host
- workspace attention is first-class with unread, waiting, and completed notification state
- navigator rows show workspace attention badges rather than terminal-only bell state
- built-in Claude launch installs workspace-local hooks and emits workspace attention events into Devys
- latest-unread navigation and a workspace notifications panel are implemented
- workspace-owned port detection, conflict handling, and stop/open/copy actions are implemented
- repository settings now support static port labels with scheme and path metadata
- workspace-native `Changes` sidebar Git affordances are implemented
- file tree Git indicators are workspace-scoped and derived from the active workspace
- shell Git actions now include fetch, pull, push, commit, create PR, and open PR
- launch page is repository-centric and supports restoring the previous session
- global settings now include notifications, restore behavior, external editor defaults, and a shortcut entry point
- repository settings now include workspace creation defaults and explicit default `Run` profile selection
- workspace restore now covers repositories, selected workspace, layout, editor/diff tabs, and hosted terminals
- tmux is explicitly optional rather than a core dependency
- a workspace-native command palette routes into repository, workspace, launcher, and attention flows
- editable workspace-shell shortcuts are persisted in shared settings and drive both menus and settings UI
- regression and responsiveness hardening now covers isolation-sensitive workspace state plus 10-repository / 100-workspace scale paths

What remains in this roadmap:

- nothing
- any further shell work should start in a new follow-on plan rather than reopening closed tickets here

Phase 5 completion notes:

- ports are owned by workspace runtime state, not by a global process dashboard
- Devys-managed run steps stamp ownership at launch time when possible, with inference only as fallback
- navigator rows, status bar, and active workspace sidebar all render the same workspace-owned port state
- ambiguous ownership remains explicit as `conflicted` or `unowned`; Devys does not silently reassign it

Phase 7 completion notes:

- launch page primary CTA is now `Add Repository`
- `Restore Previous Session` is a first-class launch surface action when persisted state exists
- global notification preferences now gate workspace attention at the source rather than only hiding UI
- terminal relaunch persistence has been generalized into explicit restore categories for repositories, selection, layout, and terminals
- repository settings now expose workspace creation defaults and explicit default `Run` profile behavior

Phase 8 completion notes:

- `DVYS-080` is complete through the global command palette and direct routing into repository, workspace, launcher, and unread-attention actions
- shipped command-palette commands include switch repository, switch workspace, create workspace, import worktrees, add repository, launch `Shell`, launch `Claude`, launch `Codex`, run the default profile, jump to latest unread workspace, and reveal the current workspace in the navigator
- `DVYS-081` is complete through explicit persisted workspace-shell shortcut bindings, duplicate binding detection, reserved binding detection, per-binding default restore, and restore-all-defaults
- the command palette stays a thin router over existing shell actions rather than introducing a second command graph
- shortcut definitions live in shared settings models so menus and settings UI resolve from one source of truth

Phase 9 completion notes:

- `DVYS-090` is complete through direct regression coverage for workspace selection, workspace-owned tab identity, layout restore isolation, and workspace-owned port state
- `DVYS-091` is complete through responsiveness coverage for workspace switching, navigator ordering, and background port refresh at 10 repositories and 100 workspaces
- `DVYS-092` is complete through removal of active shell assumptions that still treated Devys as single-folder-first
- the hardening work is kept in direct tests rather than compatibility shims or fallback behavior

Phase 4 completion notes:

- `DVYS-040` is complete through `WorkspaceAttentionStore` and workspace-owned navigator badges
- `DVYS-041` is complete through the `--workspace-notify` / `--workspace-notify-hook` ingress, distributed notification bridge, and Claude hook installation
- Codex notification integration is explicitly unsupported for the built-in plain CLI path and is reported as such rather than emulated
- `DVYS-042` is complete through latest-unread navigation and the notifications panel
- targeted verification passed:
  - `xcodebuild test -project Devys.xcodeproj -scheme mac-client -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:mac-clientTests/WorkspaceAttentionStoreTests -only-testing:mac-clientTests/WorkspaceAttentionIngressTests`

## Terminal Agent Notification Ingress

Devys exposes a CLI notification ingress for terminal agents that need to mark a workspace as waiting or completed.

### Entry points

Explicit payload:

```bash
Devys --workspace-notify \
  --workspace-id "$DEVYS_WORKSPACE_ID" \
  --terminal-id "$DEVYS_TERMINAL_ID" \
  --source claude \
  --kind waiting \
  --title "Claude needs attention" \
  --subtitle "permission prompt"
```

Hook stdin payload:

```bash
Devys --workspace-notify-hook --source claude --kind waiting
```

`--workspace-notify-hook` reads hook JSON from stdin and resolves `workspace-id` / `terminal-id` from the CLI flags or the exported `DEVYS_WORKSPACE_ID` / `DEVYS_TERMINAL_ID` environment variables.

### Built-in launcher behavior

- `Claude` launcher:
  - exports `DEVYS_WORKSPACE_ID`, `DEVYS_TERMINAL_ID`, and `DEVYS_EXECUTABLE_PATH`
  - installs project-local hooks in `.claude/settings.local.json`
  - forwards Claude `Notification`, `Stop`, and `StopFailure` events into Devys workspace attention

- `Codex` launcher:
  - exports the same Devys environment variables
  - currently reports that notification hook integration is unavailable rather than emulating it

### Transport

- the CLI posts a distributed macOS notification named `devys.workspaceAttentionIngress`
- the running app bridges that notification into local app state
- workspace attention stays owned by the workspace even when the originating event comes from one terminal session

### Settings interaction

- agent attention ingress is ignored when global `agent_activity` notifications are disabled
- terminal bell attention is controlled separately by the global `terminal_activity` setting
- disabling a notification category clears stale workspace attention for that source instead of silently keeping old badges around
- restore settings do not change notification ownership; restored terminals and agent launches still resolve back to one workspace

## Historical Design Record

The remainder of this document preserves the rationale and design language that led to the shipped shell model. The implementation snapshot above is the source of truth for current state.

## Why Rethink This

The current Devys shell is still folder-first and app-rail-first. That no longer matches the product direction.

What we want instead:
- multiple repositories open inside Devys at once
- multiple workspaces inside each repository
- each workspace maps 1:1 to a git branch and isolated git worktree
- each workspace owns its own directory, terminals, ports, diffs, files, and later chats
- the shell should be organized around repository and workspace context, not around a global app picker

This is closer to how Superset thinks about the product, with some terminal-first operational ideas borrowed from cmux and some native UX lessons borrowed from Supacode.

## What The Other Apps Get Right

### Superset

The strongest pattern Superset has is its mental model:
- repository/project contains many workspaces
- each workspace is one git worktree
- the main sidebar is a workspace command center
- the active workspace then gets its own contextual UI for files, changes, ports, and pane content

Other strong ideas worth borrowing:
- workspace creation is first-class
- workspaces can be created from new branch, existing branch, pull request, or imported worktree
- each workspace owns terminals and ports
- the right-side contextual panel is workspace-specific, not global
- presets for Claude, Codex, Gemini, and similar tools are built into terminal UX
- the app has a clear distinction between terminal agents and chat agents

### cmux

cmux is less IDE-like, but it gets the operational layer right:
- workspaces are visible and scannable
- workspace rows carry meaningful metadata
- notifications are a first-class routing mechanism
- terminals and browser panes are primitives, not “features”
- the shell is built around fast switching between active contexts

The most useful ideas for Devys:
- the navigator should show status, not just names
- unread and waiting state should be visible without opening a workspace
- workspace rows should expose branch, PR, ports, and latest attention state
- primitives should remain composable instead of hardcoding one workflow

### Supacode

Supacode is the best native reference for:
- repository and worktree sidebar structure
- command palette integration
- keyboard-driven worktree management
- preserving a strong worktree identity in the shell

The most useful ideas for Devys:
- repository in sidebar, worktrees nested beneath it
- command palette for workspace actions
- native-feeling navigation split rather than a global app dashboard

## Proposed Devys Mental Model

Devys should adopt this object model:

- `Repository`
  - an imported git root
  - owns repository-level settings
  - owns a list of workspaces
  - owns defaults like terminal presets, ignored/untracked copy policy, and workspace creation settings

- `Workspace`
  - exactly one git branch and exactly one git worktree
  - exactly one working directory
  - owns workspace-local state
  - owns terminals, ports, notifications, diff state, file tree state, and later chat sessions
  - should be the main unit of focus in the UI

- `Workspace Canvas`
  - the tab and split area for the active workspace
  - contains editors, terminal panes, diff views, browser panes later, and chat panes later
  - should be restored per workspace

- `Workspace Sidebar`
  - contextual sidebar for the active workspace
  - contains files and changes first
  - can later include search and ports

- `Global Shell`
  - manages repositories and workspace switching
  - does not directly own file trees or diff views

## Core Opinion

The most important product opinion should be:

`Active canvas state is scoped to one workspace at a time.`

That means:
- switching workspace should switch the entire middle sidebar and main canvas
- tabs and splits belong to the active workspace
- mixing panes from multiple workspaces in one canvas should not be the default

Reason:
- it keeps the mental model clean
- it matches the isolation promise of worktrees
- it avoids subtle cross-workspace bugs in terminals, ports, chats, and Git state
- it aligns with how Superset and Supacode stay understandable

If we ever want cross-workspace comparison later, that should be an explicit feature, not the default shell behavior.

## Proposed Shell Layout

Replace the current app rail with a three-part shell:

```text
+----------------------+---------------------------+--------------------------------------+
| Repositories         | Workspace Sidebar         | Workspace Canvas                     |
| and Workspaces       | Files | Changes | Search  | Tabs and splits for active workspace |
|                      |                           |                                      |
| Repo A               | file tree or changes     | editor / terminal / diff / browser   |
|   main               | for selected workspace   | later: chat pane                     |
|   feat/auth          |                           |                                      |
|   fix/login          |                           |                                      |
|                      |                           |                                      |
| Repo B               |                           |                                      |
|   main               |                           |                                      |
|   pr-182             |                           |                                      |
+----------------------+---------------------------+--------------------------------------+
| Status Bar: active repo, workspace, branch, ahead/behind, PR, ports, run state          |
+------------------------------------------------------------------------------------------+
```

### Column 1: Repository and Workspace Navigator

This replaces the current left app rail.

What it should show:
- repositories as top-level groups
- workspaces nested under each repository
- one selected workspace globally
- workspace metadata inline

Workspace row should show:
- branch name
- dirty summary
- ahead/behind
- PR badge if linked
- CI or checks state if available
- unread attention dot
- run state
- port count if any

What should live here:
- add repository
- create workspace
- import worktrees
- archive/unarchive
- delete workspace
- pin workspace
- rename workspace
- open in Finder/Xcode/editor

This column should be the operational overview.

### Column 2: Active Workspace Sidebar

This is not a global app sidebar. It is scoped to the selected workspace.

Recommended initial modes:
- `Files`
- `Changes`
- `Ports`

Recommended later modes:
- `Search`

Strong recommendation:
- start with tabbed modes rather than trying to show files and changes side by side

Reason:
- files and changes compete for vertical scanning space
- most users will want one or the other at a time
- tabs keep the column narrow and consistent
- the selected workspace already gives enough context that this can be a focused utility column

Default behavior:
- `Files` is the default mode
- `Changes` should show staged, unstaged, and untracked changes
- clicking a file opens preview in canvas
- double-click promotes to persistent tab
- clicking a diff item opens diff preview in canvas

### Column 3: Workspace Canvas

This is where actual work happens.

Allowed pane kinds:
- editor
- terminal
- diff
- welcome or empty state
- browser later
- chat later

The canvas should:
- preserve split layout per workspace
- restore the last active tabs per workspace
- allow multiple terminals per workspace
- allow editor and diff tabs alongside terminal panes

This is where Devys should lean into its strongest existing primitive: the split system.

## Proposed Primitive Types

These are the primitives Devys should commit to at the architecture level.

### Repository

Repository owns:
- root URL
- display name
- icon or avatar later
- repository settings
- workspace list
- import state
- default branch metadata

Repository settings should include:
- default base branch
- workspace creation defaults
- terminal presets available in this repo
- startup profiles and default `Run` behavior
- static port labels
- setup and teardown behavior later

### Workspace

Workspace owns:
- workspace ID
- repository ID
- branch name
- worktree URL
- branch kind
  - local branch
  - PR workspace
  - imported worktree
- Git metadata
- notification state
- terminal registry
- port registry
- canvas layout snapshot
- sidebar mode and selection
- later: chat session registry

Workspace is the core product primitive.

### Terminal Session

A terminal session belongs to exactly one workspace.

Terminal sessions should support:
- shell
- Claude Code
- Codex
- other preset-driven commands
- run script terminals

Terminals should not be global. They should always resolve to a workspace.

### Terminal Persistence Default

Devys should not require tmux for its core terminal model.

The default persistence architecture should be:
- PTYs are owned by a Devys-managed detached terminal host
- the app attaches UI tabs and panes to those hosted sessions
- workspace restore reconnects to hosted sessions by workspace identity
- terminal persistence works on a clean machine without tmux installed

Why this should stay the default:
- tmux would become an external runtime dependency for a core Devys feature
- tmux panes and windows do not map cleanly to Devys tabs, splits, and workspace ownership
- Devys needs restore behavior to follow repository and workspace identity first, not tmux session topology
- the product should be able to preserve terminals across relaunch without teaching users tmux semantics

tmux can still remain optional later:
- users can launch tmux inside a Devys terminal if they want it
- repository presets can run tmux-based commands for teams that prefer it
- future power-user integrations can treat tmux as an optional execution mode, not as a required shell primitive

Hard rule:
- no shipped Devys feature should require tmux to function
- Devys workspace switching and terminal restore should work without tmux

### File and Diff State

These should be workspace-scoped, not global.

Reason:
- file tree depends on worktree directory
- diff state depends on that workspace's Git state
- preview tabs should not accidentally cross workspace boundaries

### Ports

Ports should be a workspace primitive, not just a process listing.

Each workspace should own:
- detected ports
- optional labels
- open-preview actions later
- kill or stop actions

## Default UX Flows

### Add Repository

Default flow:
- user adds a repository root
- Devys scans git info
- Devys creates or imports the default workspace for the current checked-out branch
- repository appears in navigator

Launch page behavior now also includes:

- recent repositories
- `Restore Previous Session` when persisted state exists

### Create Workspace

Supported creation flows should be:
- new branch from base branch
- existing branch
- pull request
- import existing worktree

Opinion:
- all four should exist
- `New Branch` should be the primary default

Strong recommendation:
- if the current repository already has worktrees on disk, show them in the create flow rather than hiding that capability behind a separate settings screen

### Switch Workspace

Switching workspace should:
- keep repository navigator selection in sync
- swap the active workspace sidebar contents
- restore the workspace canvas layout
- restore last active tab and pane focus
- preserve inactive workspaces without discarding state

This should feel like switching branches in an IDE, not like opening a new project.

### Open File

From `Files` mode:
- single click opens preview tab
- double click opens persistent editor tab
- right click supports reveal, copy path, open in external editor later, add to chat later

### Open Diff

From `Changes` mode:
- single click opens diff preview
- double click opens persistent diff tab
- “Edit Here” should jump to matching file and location later

### Launch Claude Code or Codex

Within the active workspace:
- click a terminal quick action or preset chip
- launch into current workspace only
- default is new terminal tab or split according to preset

Opinion:
- terminals for agents should remain terminal-native
- we should not fake chat around terminal agents unless we are actually building a separate chat product

## Terminal and Agent UX Direction

Devys should be explicit about this:

- terminal agents are first-class now
- in-app chat agents are later

That means the current generation of Devys should optimize for:
- launching Claude Code and Codex quickly
- seeing their state in workspace rows
- receiving notifications when they need attention
- preserving terminal history and layout in each workspace

Recommended defaults:
- every repository gets a default `Shell` preset
- Devys ships built-in quick templates for:
  - `Claude Code`
  - `Codex`
  - later `Gemini CLI`
  - later `OpenCode`
- presets are repository-level, launches are workspace-level

Recommended quick-launch UI:
- a small toolbar above the workspace canvas
- buttons like `Shell`, `Claude`, `Codex`, `Run`
- optional dropdown for advanced presets

This is much closer to Superset's preset model than Devys's current prompt-for-run-command model.

## Agent Chat Later

Agent chat should be treated as a separate pane type, not as the replacement for terminals.

When chat ships later:
- chat sessions should belong to one workspace
- chat panes live in the workspace canvas
- chat should be able to reference files, diffs, and terminals from the same workspace
- approvals, questions, and plan review should happen in chat only if we are building a true chat-native flow

Recommendation:
- do not let “future chat” distort the shell design now
- make the shell workspace-native first
- add chat as another workspace surface later

## Notifications

This is where cmux has the clearest lesson.

Devys should treat notifications as workspace state, not just terminal state.

Recommended model:
- terminal or later chat events create workspace notifications
- navigator shows unread state on workspace row
- status bar can show the active workspace's latest attention state
- a dedicated notifications panel can exist later, but unread routing should work even without it
- global settings can disable terminal activity notifications or agent activity notifications independently

Minimum viable notification UX:
- unread dot on workspace row
- “jump to latest unread workspace”
- terminal sessions can mark a workspace as waiting
- workspace row shows latest waiting source
  - for example `Claude`, `Codex`, `Run`, `Build`

## Port Management

Devys should copy Superset's mental model here:
- ports belong to workspaces
- ports are detected per workspace
- ports should be visible without leaving workspace context

Recommended initial placement:
- a compact ports section in the active workspace sidebar or status bar
- navigator row can show port count

Recommended later behavior:
- click a port to open preview
- right click to copy URL, kill process, or open in browser pane later

Important default:
- do not invent a global cross-workspace port dashboard first
- keep ports workspace-scoped

## Git and Changes UX

The current Devys Git package is already stronger than the shell suggests.

What the new shell should do:
- make `Changes` a first-class workspace sidebar mode
- keep diffs in the main workspace canvas
- keep branch and PR summary in navigator and status bar
- expose PR and history views as workspace tools later, not as unrelated global screens

Recommended split:
- navigator = branch and workspace status
- workspace sidebar = files and changes
- canvas = diff review, editors, terminals

## Command Palette

Supacode is right about this: a native app like this needs a real command palette.

The command palette should be global, but workspace-aware.

It should support:
- switch workspace
- create workspace
- import worktrees
- archive or delete workspace
- open files
- open changes
- launch Claude or Codex
- run preset
- jump to unread workspace
- reveal current workspace in navigator

This becomes the keyboard-native control plane for the shell.

## Strong Product Opinions and Defaults

These are the defaults Devys should adopt.

### 1. One workspace equals one branch and one worktree

No exceptions in the core model.

### 2. The active canvas is single-workspace

No mixing workspaces in one split layout by default.

### 3. The leftmost sidebar is for repositories and workspaces, not apps

This is the biggest shell change.

### 4. Files and changes are workspace modes, not global app sections

They live in the contextual sidebar.

### 5. Terminal agents come before chat agents

Optimize for Claude Code and Codex in terminals first.

### 6. Status belongs in the navigator

Branch, PR, unread, run state, ports, and checks should all be visible in workspace rows.

### 7. Layout is remembered per workspace

Switching workspaces should feel instant and stateful.

### 8. Repositories own defaults, workspaces own runtime state

This cleanly separates config from execution context.

## Proposed Devys vNext Navigation Model

This is the recommended shell structure.

### Global Scope

Global commands:
- add repository
- command palette
- settings
- jump to unread workspace
- global search later

### Repository Scope

Repository actions:
- create workspace
- import worktrees
- open repository settings
- open in Finder
- refresh workspaces

### Workspace Scope

Workspace actions:
- switch to workspace
- pin
- archive
- delete
- open files
- open changes
- launch terminal
- launch Claude
- launch Codex
- reveal ports
- later open chat

### Pane Scope

Pane actions:
- split
- close
- move
- focus
- search within pane

## Recommended Implementation Mapping

This is how the new model should influence current Devys architecture.

### Replace `WindowState.folder`

Current window state is too narrow.

Replace the window-level concept from:
- one folder per window

To:
- repository collection per window
- active repository ID
- active workspace ID

### Move from Folder-Scoped to Workspace-Scoped Stores

These stores should become workspace-scoped:
- Git store
- file tree
- terminal registry
- notification state
- diff selection
- port state later

### Preserve the Existing Split System

The current split primitive is good.

Do not replace it.

Instead:
- make the split controller belong to workspace canvas state
- save and restore layout per workspace

### Keep `TabContent`, but make it workspace-aware

Every tab content item should carry workspace context.

Examples:
- editor in workspace X
- diff in workspace X
- terminal in workspace X
- browser in workspace X later
- chat in workspace X later

## Final Recommendation

Devys should move from:
- folder-first
- app-rail-first
- globally scoped sidebars

To:
- repository-first
- workspace-first
- workspace-scoped sidebars and canvas

The best version of this product is:
- more IDE-native than cmux
- more terminal-native than Superset chat-first flows
- more polished and composable than Supacode's current surface

The next shell should therefore be:
- `Repositories and Workspaces` on the left
- `Files and Changes` in a contextual middle sidebar
- `Workspace Canvas` on the right
- terminals for Claude Code and Codex as first-class workspace surfaces
- chat as a later pane type, not a shell-defining primitive yet
