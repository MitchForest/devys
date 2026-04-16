# Comparison Matrix

Updated: 2026-04-15

This document is research input, not an implementation plan.

Active migration sequencing lives in `../plan/implementation-plan.md`.

Scope:
- Compared active Devys functionality against `cmux`, `superset`, and `supacode`
- Focused on currently shipped or clearly surfaced product behavior
- Weighted active Devys app surfaces higher than archived packages or older experiments

Repos reviewed:
- `cmux`: `.docs/repos/cmux`
- `superset`: `.docs/repos/superset`
- `supacode`: `.docs/repos/supacode`
- `devys`: current repo

## Executive Summary

Devys already has a strong native foundation: split panes, tabs, a custom editor, a Git diff viewer, a terminal surface, worktree-aware state, and a coherent design system. The main parity gaps are not core primitives. They are product layers on top of those primitives.

The biggest missing areas are:
- a real worktree/workspace command center UI
- a real agents/chat/orchestration surface
- a real notifications system for agent attention routing
- a browser and port workflow
- command palette and customizable shortcuts
- terminal presets, setup/teardown/run workflows, and session restore
- richer PR/review flows surfaced in the active app

## Product Matrix

| Area | Devys | cmux | Superset | Supacode | Parity Gap For Devys |
|---|---|---|---|---|---|
| Core product shape | Native macOS IDE shell with editor, terminal, Git, splits | Native macOS terminal and browser orchestrator | Electron desktop app for agent worktree orchestration | Native macOS command center for worktrees and terminal agents | Devys has strong primitives but weaker orchestration UX |
| Primary mental model | Folder/worktree-oriented dev environment | Workspaces, surfaces, panes | Repositories, workspaces, tasks, panes | Repositories, worktrees, terminal tabs/surfaces | Devys needs a clearer top-level object model in the UI |
| Worktree awareness | Present in state/models and status bar; partially surfaced | Strong workspace metadata in sidebar | First-class workspace lifecycle | First-class worktree lifecycle | Devys needs full worktree UX, not just state |
| Git review | Strong diff engine and Git package | Sidebar metadata, less review-heavy than Superset | Rich diff/review workflow | Strong PR/check/status workflow | Devys should surface more of the Git package in active UI |
| Agent orchestration | Placeholder `Agents` rail only | Terminal-first, no heavy in-app chat | Full agent orchestration plus chat | Terminal-first, lightweight agent control | Devys needs to choose between terminal-first and chat-first, then implement it fully |
| Browser | No active browser surface | Built-in browser plus automation | Built-in browser plus DevTools | No built-in browser focus | Devys is behind cmux and Superset here |
| Notifications | Basic terminal notification state exists | Core product strength | Strong notifications and monitoring | Strong notification-driven worktree UX | Devys needs a first-class attention model |
| Command system | Basic run command per repo/worktree | CLI, socket API, custom commands | Presets, scripts, palette, settings | Command palette, shortcuts, scripted actions | Devys needs both quick actions and programmable actions |
| Keyboard UX | Some static shortcuts | Rich app shortcuts | Customizable shortcuts | Strong customizable shortcut system | Devys needs shortcut customization and discovery |

## 1. Repos, Workspaces, and Worktrees

### Devys

What it does now:
- Tracks a single open folder per window
- Maintains worktree state and selection in models and services
- Shows branch, line changes, PR badge, and run status in the bottom status bar
- Has a fairly complete `WorktreesSidebarView` implementation with pinning, archiving, assigned-agent labels, PR badges, terminal rows, and remove/open actions

What is missing in the active app:
- the worktrees sidebar is not wired into the active shell
- no create-worktree flow
- no import-existing-worktrees flow
- no archived-worktrees UI
- no reorder/drag workflow exposed to the user
- no clear repository-level workspace dashboard

Assessment:
- Devys has better-than-it-looks underlying worktree infrastructure
- The main issue is surfacing and completing the flow, not inventing the data model

### cmux

How it works:
- Uses workspaces, tabs/surfaces, and panes as the main control model
- Sidebar treats each workspace as an operational unit
- Each workspace shows metadata like branch, PR, working directory, ports, and latest notification

Strengths:
- workspace identity is always visible
- fast navigation between parallel contexts
- very strong operational overview

Weaknesses relative to Devys:
- less editor-centric
- less of an IDE and more of an orchestration terminal

### Superset

How it works:
- Repositories contain workspaces
- Each workspace is an isolated git worktree
- New workspace flow supports:
- new branch
- existing branch
- pull request
- import of existing worktrees
- workspaces expose branch state, PR state, CI state, deployment preview, ports, terminals, and panes

Strengths:
- best worktree lifecycle UX of the group
- strongest “parallel isolated tasks” framing
- best prompt-first creation flow

What Devys should borrow:
- a proper new worktree modal
- import-existing-worktrees
- visible ahead/behind status
- visible review/check/deployment state
- workspace-specific actions in one place

### Supacode

How it works:
- Repositories and worktrees are the main structure
- Supports pinned worktrees, archived worktrees, ordering, selection, worktree info watching, and pull request actions
- Stronger than Devys on operational worktree UI and command access

What Devys should borrow:
- archived worktree workflows
- worktree actions through command palette
- more explicit repository-level and worktree-level settings

### Parity conclusion

Devys should add:
- a real worktree sidebar in the live shell
- create/import/archive/delete/reorder flows
- ahead/behind indicators
- repository-level workspace dashboard
- stronger worktree action menus and keyboard flows

## 2. Git Operations and Display

### Devys

What it already has:
- strong Git package architecture
- staged and unstaged file lists
- preview vs permanent diff opening
- Metal-backed diff viewer
- commit UI
- PR list UI
- PR detail UI
- PR create and merge flows
- commit history UI

Important caveat:
- much of this is implemented in the package but not fully surfaced in the active app shell

Current active experience:
- Git sidebar is exposed
- Git diff tabs are exposed
- PR/history/panel workflows are not the main active path today

### cmux

What it emphasizes:
- Git as metadata, not as a full review tool
- branch, PR number, PR status, and related context are surfaced in the sidebar

What it is good at:
- knowing which workspace is doing what
- quick operational awareness

What it is not focused on:
- deep in-app code review and editing

### Superset

What it emphasizes:
- review workflow
- diff browsing
- stage/unstage
- commit
- push/pull
- create PR
- edit-here from diff
- focus mode for review

This is the strongest benchmark for Git review UX.

### Supacode

What it emphasizes:
- PR status, checks, GitHub integration health
- pull request actions from worktree context
- merge strategy settings
- terminal-first but still GitHub-aware

### Parity conclusion

Devys should add or surface:
- PR/history views in the live app
- push/pull sync affordances
- focus mode in review
- edit-here from diff
- more visible PR review/check state in the main shell
- a clearer distinction between file changes, commits, and pull requests

## 3. Notifications and Attention Routing

### Devys

What exists:
- terminal notification store
- unread state tracking for terminal sessions
- worktree UI code that can show unread dots

What is missing:
- dedicated notifications center
- latest unread jump
- richer unread badges/rings
- agent-waiting state as a primary concept
- detailed notification history

### cmux

This is one of cmux's strongest areas.

Key behaviors:
- notification rings around panes
- lit-up workspace tabs for unread items
- latest notification text in the sidebar
- `cmux notify` CLI for hooking agent lifecycle events
- jump-to-latest-unread workflow

It treats agent attention routing as a core product capability.

### Superset

Key behaviors:
- monitors agents and workspaces from one place
- system notification support
- notification-linked workspace monitoring
- status and readiness framing around agent tasks

Less visually iconic than cmux, but more integrated into a broader agent product.

### Supacode

Key behaviors:
- notification indicator count in app state
- notification-related toolbar and popover UI
- worktree notifications integrated into ordering and focus
- system notification settings

### Parity conclusion

Devys should add:
- notifications center
- per-worktree unread counts
- jump-to-latest-unread
- optional pane or tab ring/badge treatment
- CLI-friendly or hook-friendly notification ingestion for Claude Code, Codex, and similar tools

## 4. Layouts, Navigation, and Theming

### Devys

What it already does well:
- custom split system
- tabbed panes
- custom design system
- dark/light support
- accent color support
- editor and diff surfaces feel native and purpose-built

Where it is thinner:
- fewer high-level navigation primitives
- no command palette
- no customizable shortcut UI
- worktree and agent navigation are weaker than competitors

### cmux

Key traits:
- vertical tabs
- strong sidebar-led navigation
- split-focused terminal/browser orchestration
- Ghostty config compatibility
- macOS-native feel

### Superset

Key traits:
- dashboard-style orchestration layout
- strong workspace sidebar
- many pane types
- more “application shell” feeling than Devys today

### Supacode

Key traits:
- strong native macOS polish
- command palette integration
- shortcut customizability
- worktree-centric navigation model

### Parity conclusion

Devys should add:
- command palette
- richer sidebar navigation model
- worktree-focused navigation shortcuts
- shortcut customization UI
- stronger information density in sidebar and title/status areas

## 5. Terminals, Claude Code, Codex, and Agent Runtime UX

### Devys

What it has:
- Ghostty-backed terminal surface
- multi-terminal tabs in the general split/tab system
- per-worktree run command support
- hooks for terminal unread state

What it does not yet have:
- presets/templates for common agent launches
- one-click Claude/Codex/Gemini/OpenCode launchers
- auto-apply presets on workspace creation
- search in terminal
- pane rename
- merge tabs or richer terminal tab operations
- session restore and persistent scrollback semantics surfaced as a feature
- command bar above terminal tabs

### cmux

Key traits:
- terminal-first orchestration
- optimized for lots of parallel Claude/Codex sessions
- excellent attention routing
- CLI and socket control over panes and input

### Superset

Key traits:
- terminal-first agent support plus higher-level orchestration
- presets with templates for Claude, Codex, Gemini, and others
- setup/teardown/run workflows
- persistent sessions
- agent-specific launch behavior

### Supacode

Key traits:
- native terminal manager is a central feature
- search actions are wired through app state
- run/setup/blocking script handling is integrated
- notification and focus state are tightly coupled to terminal state

### Parity conclusion

Devys should add:
- terminal presets/templates
- one-click launchers for Claude Code, Codex, Gemini, OpenCode, and others
- preset bar or command strip
- terminal search
- pane rename and better tab operations
- session restore/persistence story
- better per-worktree terminal ownership

## 6. Port Management and Service Preview

### Devys

Current state:
- no active built-in port management UI
- no browser pane
- no service preview workflow

### cmux

Key traits:
- ports are surfaced in workspace metadata
- browser can be opened next to terminals
- remote and SSH-aware browser routing is a major feature

### Superset

Key traits:
- explicit ports UI
- ports grouped by workspace
- click port to open in-app browser
- static port config file for known services
- deployment preview and open-preview actions when available

### Supacode

Current focus:
- less browser-and-port-centric than cmux and Superset
- more focused on repository/worktree and terminal workflows

### Parity conclusion

Devys should add:
- detected ports panel
- workspace-associated ports
- click-to-open service preview
- optional static port labels/config
- eventually, deployment preview affordances

## 7. Commands, Automation, and Quick Actions

### Devys

What exists:
- run command per repository/worktree via a prompt
- some keyboard commands around file/worktree navigation

What is missing:
- command palette
- reusable command presets
- setup/teardown/run scripts
- automation endpoints
- custom project commands

### cmux

Key traits:
- custom commands in config
- command-palette launching
- CLI and socket API
- browser automation commands

### Superset

Key traits:
- terminal presets
- setup/teardown/run scripts
- local overrides
- per-project automation model
- MCP server

### Supacode

Key traits:
- strong command palette
- many worktree and update commands routed through the palette
- shortcut-backed actions

### Parity conclusion

Devys should add:
- command palette first
- reusable command presets second
- repo-level setup/teardown/run config third
- programmable API or automation surface later

## 8. Agent Chat, Separate From Terminal UI

### Devys

Current active state:
- no active in-app agent chat product
- `Agents` is still a placeholder sidebar

Important nuance:
- archived code suggests previous or parallel exploration of chat and agent infrastructure
- none of that currently defines the active product

### cmux

Approach:
- mostly terminal-first
- does not try to replace the agent with a heavy in-app chat UI
- browser automation is the main non-terminal agent surface

### Superset

Approach:
- strongest in-app chat product of the group
- separate chat pane
- model/provider selection
- MCP-aware chat controls
- uploads and mentions
- approval and question states
- subagent-related messaging
- direct connection between agent sessions and workspace panes

### Supacode

Approach:
- much lighter on separate chat UI
- primarily terminal-and-worktree-oriented

### Parity conclusion

Devys needs a product decision:

Option A:
- stay terminal-first like cmux/supacode
- focus on orchestration, notifications, presets, and browser

Option B:
- build a true agent-chat product like Superset
- add chat pane, provider/model controls, MCP, approvals, attachments, and session management

Right now Devys is between these two models and needs to commit to one.

## 9. Browser and File Preview

### Devys

What exists:
- editor and diff surfaces
- no active browser pane
- no active file-preview pane separate from editor

### cmux

What it adds:
- browser split pane
- scriptable browser actions
- shared cookie/session import from existing browsers
- remote-aware browser behavior

### Superset

What it adds:
- in-app browser tab
- address bar
- history/autocomplete
- DevTools
- file pane and file preview separate from terminal/chat

### Supacode

What it adds:
- not a core browser product

### Parity conclusion

Devys should add:
- built-in browser
- file preview/file tree interactions beyond just opening editor tabs
- later, browser automation only if Devys wants to compete directly with cmux

## 10. Settings, Shortcuts, Updates, and Integration

### Devys

Current state:
- appearance settings
- explorer settings
- basic app settings surface

Missing:
- keyboard shortcut editor
- import/export shortcuts
- GitHub integration settings
- PR merge strategy settings
- worktree copy ignored/untracked settings
- update channel/update preferences
- provider/API-key settings

### cmux

Has:
- keyboard shortcut coverage
- browser-related settings
- update channel and auto-update behavior
- strong Ghostty compatibility

### Superset

Has:
- terminal presets settings
- provider settings
- API key workflows
- MCP setup
- browser and editor integration settings

### Supacode

Has:
- GitHub settings
- notifications settings
- keyboard shortcut settings
- updates settings
- worktree and repository settings
- merge strategy settings

### Parity conclusion

Devys should add:
- keyboard shortcut settings
- GitHub/settings health surface
- update settings
- worktree/repository behavior settings
- if chat ships, provider and API-key configuration

## Recommended Priority Order

### Tier 1: Highest leverage

- Wire `WorktreesSidebarView` into the active shell
- Add create/import/archive/delete worktree flows
- Add command palette
- Add notifications center and latest-unread navigation
- Surface PR/history views already implemented in the Git package

### Tier 2: Core product shape

- Add terminal presets and templates for Claude Code, Codex, Gemini, and OpenCode
- Add setup/teardown/run script support
- Add customizable keyboard shortcuts
- Add richer worktree metadata in the sidebar

### Tier 3: Strategic differentiators

- Add built-in browser and ports panel
- Add service preview workflows
- Decide whether Devys is terminal-first or chat-plus-terminal
- If chat-first or hybrid, build the real agents pane

### Tier 4: Advanced parity

- Add automation surface or CLI/API
- Add browser automation if desired
- Add deeper GitHub/PR/deployment integrations
- Add session restore and more advanced terminal persistence

## Recommended Product Direction

If Devys wants the shortest path to parity while staying coherent with its current strengths, the best route is:

1. Lean into the native IDE foundation
2. Fully ship worktree orchestration and Git review
3. Add a serious terminal agent workflow
4. Add notifications and command palette
5. Then decide whether to extend toward:
- `cmux`: terminal/browser automation orchestration
- `superset`: full chat-orchestrated agent workspace platform

The current codebase is closer to becoming a strong native worktree IDE than a full Superset-style chat platform. That makes worktree UX, Git UX, notifications, presets, and browser/ports the most natural next steps.
