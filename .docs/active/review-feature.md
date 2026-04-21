# Devys Review Feature Plan

Status: implementation complete

Updated: 2026-04-20

## Current State

This slice is now active.

The future brief has been replaced with an execution plan grounded in the current codebase.

The repo already has the right high-level seams:

- `Packages/AppFeatures` owns the reducer-backed shell, tabs, workspace selection, workflow state, and dependency clients.
- `Apps/mac-client` already owns host-side workflow execution, artifact persistence, launcher staging, distributed-notification ingress, and terminal startup.
- `Packages/Workspace` already owns repo-scoped launcher settings, but it does not own run state.
- `Packages/Git` already exposes working-tree status, staged and unstaged diffs, commit history, commit diff loading, PR metadata, and PR file loading.

The repo now has a complete first-pass review implementation:

- reducer-owned review models, tab identity, and manual entry flow exist
- review sidebar and review tab surfaces exist in first-pass form
- host-side review run persistence exists outside the repository
- structured local audit execution exists for manual review targets
- review settings UI now exists for enablement, harness selection, model and reasoning overrides, and additional instructions
- review trigger ingress and background-triggered audit execution now exist for host-delivered review requests
- review-on-commit hook installation and settings-driven automatic delivery now exist
- review triggers now use a durable host inbox with startup replay instead of a lossy notification payload path
- pull-request review now exists in the single `Review…` entry flow when PR metadata is available
- review tab artifact access now includes audit prompt, raw output, parsed result, summary, and input snapshot in a compact header menu
- review persistence now treats handled reviews as ephemeral, deleting them from durable storage while retaining only active or still-actionable runs
- review tabs now support rerun, minimal issue actions, and explicit failure-state artifact access
- supported validation entry points are green for the current implementation

## Purpose

Make review a first-class repo-scoped feature in Devys.

The shipped feature should let a user:

- run a review for current changes, staged changes, a commit, or a pull request
- inspect a structured issue list in the shell
- dismiss or accept risk on issues explicitly
- hand an issue off to Claude or Codex through a staged terminal command
- keep the same product model when review execution later moves to a remote host

## Remaining Todo List

No remaining implementation work is tracked in this plan.

If review expands in a later phase, that follow-up work should move to a new active brief instead of reopening this one. Likely future candidates are:

- commit-range and selection targets
- PR-update automation beyond manual PR review
- remote review runners
- auto-launching review processing while Devys is fully closed

### Closed Out In This Pass

- strict-concurrency review-sidebar formatting was fixed so the mac host builds cleanly under Swift 6
- canonical review-run ordering now lives on `ReviewRun`, which keeps reducer and host persistence logic aligned without package-private coupling
- AppFeatures package tests, targeted review host tests, `mac-client` build, and `ios-client` build were rerun successfully

## Product Shape

Review lives in the `Files` sidebar mode, not `Agents`.

The canonical sidebar shape for this feature is:

- `Files`
- `Reviews`
- `Changes`
- `Ports` when present

The review detail surface lives in the existing reducer-owned tab shell as a dedicated review tab.

## Execution Modes

Review should use two explicit execution modes.

### Audit Mode

Audit mode is the canonical review run.

It should be:

- headless
- non-interactive
- structured
- automatable

Purpose:

- inspect a target
- return a stable issue list
- persist artifacts
- drive sidebar and tab state

This is the only review-run mode for the first milestone.

### Investigation Mode

Investigation mode is the follow-up path after a review issue exists.

It should be:

- interactive
- terminal-backed
- staged before execution
- user-editable before pressing Enter

Purpose:

- let the user ask questions
- let the user challenge whether the issue is real
- let the user ask for a fix plan
- let the user continue into implementation if they choose

This is not a second kind of review run. It is an explicit follow-up action from review output.

### What We Are Not Doing First

Do not add an interactive full-review terminal mode in the first milestone.

Reason:

- the first milestone needs one canonical source of review truth
- automation depends on structured headless output
- mixing audit and ad hoc terminal sessions too early makes state ownership muddy

## What We Must Preserve

- TCA owns review state, navigation, policy, and lifecycle.
- Host services execute audits, persist artifacts, install hooks, and stage follow-up terminal launches.
- `RepositorySettingsStore` remains configuration-only.
- `GitStore` and `GitHubClient` remain git capability providers, not review owners.
- Review does not become a workflow subtype.
- Review does not add a third primary sidebar mode.
- Review artifacts stay out of the repository by default.

## UX Decisions

These are the product defaults unless implementation shows they are wrong.

### User Entry Points

Manual review should have one canonical entry action:

- `Review…`

That action should open a lightweight target picker instead of scattering review buttons across the shell.

The target picker should offer:

- `Unstaged Changes`
- `Staged Changes`
- `Last Commit`
- `Current Branch`

Later targets may add:

- `Commit Range`
- `Pull Request`
- `Selection`

The first milestone should not add additional review actions in `Changes`, commit sheets, or other surfaces unless they route into this same single review-entry flow.

### How Users Know When Review Runs

The user should be able to answer these questions without guessing:

- is automatic review enabled for this repo?
- what triggers are enabled?
- what harness and model will run?
- did this run happen manually or automatically?
- what target did it review?

The UI should make that visible in three places:

1. Repository settings
   The canonical place to enable or disable review triggers and choose harness behavior.

2. Reviews sidebar section
   The summary place to see active and recent runs, including concise trigger labels such as `Manual` or `Post-Commit`.

3. Review tab header
   The inspection place to see target, trigger, harness, model, timestamps, and links to prompt/output artifacts.

### Automatic Review UX

Automatic review on commit is a good feature and should be the first automation path after manual review is stable.

Rules:

- automatic review is repo-scoped
- it is off by default
- enabling it should be explicit in repository review settings
- auto-runs must not steal focus
- auto-runs should appear in `Reviews` immediately with a running state
- completed auto-runs should update issue counts in the sidebar

The feature should feel ambient, not magical.

Automatic review should not add extra primary buttons.

Manual review stays one explicit entry point. Automatic review only changes whether runs appear on their own after a configured trigger.

### Review Settings UX

Repository settings should gain a dedicated `Review` section.

That section should expose:

- `Enable Review`
- `Review On Commit`
- later: `Review Pull Request Updates`
- `Audit Harness`
- `Follow-Up Harness`
- optional `Audit Model Override`
- optional `Follow-Up Model Override`
- optional `Audit Reasoning Override`
- optional `Follow-Up Reasoning Override`
- optional `Additional Review Instructions`

The settings should not expose a parallel full launcher editor.

The review settings should inherit from launcher templates by default and override only the narrow review-specific fields above.

### Default Review Settings

The first implementation should pick explicit defaults instead of hidden fallback behavior:

- review enabled: `true`
- automatic review on commit: `false`
- audit harness: `codex`
- follow-up harness: `codex`
- model override: unset
- reasoning override: unset
- additional review instructions: empty

When overrides are unset, the selected harness uses the corresponding repository launcher template as-is.

### Prompt UX

Prompt handling should stay explicit but narrow.

Audit prompt policy:

- Devys owns the fixed audit scaffold
- Devys injects normalized target context, governing instructions, and repo doctrine references
- repo settings may append `Additional Review Instructions`
- the first version should not expose a raw full-prompt editor

Follow-up prompt policy:

- Devys generates the follow-up prompt from the chosen review issue
- the prompt is written to an artifact file
- the resolved terminal command is staged, not auto-run
- the user can inspect and edit the prompt before running it

The review tab should expose:

- `View Audit Prompt`
- `View Raw Output`
- `View Parsed Result`
- `View Input Snapshot`
- `View Error Output`
- `View Summary`

That keeps prompt behavior inspectable without turning prompt authoring into a feature system of its own.

### Reviews Sidebar UX

The `Reviews` section should show:

- one primary action button: `Review…`
- active runs first
- inactive runs only while they still need attention

Each row should show:

- target label such as `Staged Changes` or `Commit abc1234`
- concise trigger label such as `Manual` or `Post-Commit`
- run status or open-item summary
- timestamp or relative age

Rows should open the review tab. They should not expand into inline detail trees.

Handled reviews should leave the sidebar automatically. Dismissing the final issue or staging a fix for the final issue should remove the run from the sidebar without requiring extra cleanup.

The primary button should open the same target picker everywhere it is used.

### Review Tab UX

The review tab should have a simple two-level structure:

- header summary
- issue list with detail

Header summary should show:

- target
- trigger
- audit harness
- resolved model when known
- created and completed times
- rerun action
- compact artifact menu

Issue presentation should show:

- severity
- confidence
- title
- short summary
- rationale
- relevant paths and line references

Issue actions should be:

- `Dismiss`
- follow-up harness selector
- `Fix`

The first version should use a simple single-column or master-detail layout. Do not add multi-pane review workspaces yet.

### Failure UX

If audit parsing fails or execution fails, the run should still be visible and explainable.

The failed review tab should show:

- failure summary
- raw stdout and stderr access
- parse diagnostics when relevant
- rerun action

Failure must never collapse into “no issues found.”

## Codebase Findings

### Shell and Tab Ownership

The reducer already owns the shell in the right place:

- `WindowFeature.State` owns workspace shells and selected tabs.
- `WorkspaceTabContent` is the semantic tab identity boundary.
- relaunch persistence already serializes tab kinds and sidebar selection.

That means review should add:

- a reducer-owned review workspace state map alongside workflow workspace state
- a new review tab case in `WorkspaceTabContent`
- matching relaunch persistence cases
- a dedicated review render path in the host tab view

### Sidebar Composition

The current host sidebar surface already composes files, changes, ports, agents, and workflows.

Important implication:

- adding `Reviews` is a focused shell change, not a new navigation system
- the section belongs in the existing files sidebar stack
- we should not hide review under workflows or chats

### Launcher and Terminal Staging

The existing launcher path already does the hard part:

- repo-scoped Claude and Codex templates live in `RepositorySettings`
- `RepositoryLaunchPlanner` resolves CLI commands
- `launcherCommandRouting` already supports immediate execution or staged terminal input
- hosted terminal startup already supports staged commands and compatibility shell launches

This should be reused for per-issue investigation handoff instead of building a second launcher system.

### Workflow Reuse Boundary

The workflow stack is useful precedent but the wrong product model.

What is worth reusing:

- the dependency-client pattern
- host-side artifact persistence in app support
- command construction and prompt artifact writing patterns
- reducer tests that prove explicit run-state transitions

What must not be reused:

- workflow definitions
- graph nodes and edges
- workflow run semantics
- workflow sidebar placement

### Git and Pull Request Capability

The git layer already exposes enough capability for the first phases:

- working-tree and staged diff data
- commit history plus commit diff loading
- PR metadata and changed-file loading through `gh`

What is still missing is review-specific target normalization and review-context assembly.

### Trigger Ingress

The app already has a narrow cross-process ingress path, but it is attention-specific.

That is a good precedent for:

- `Devys --review-trigger ...`
- a small structured payload
- distributed notification delivery to the running app

It is not a good place to overload review behavior onto workspace attention notifications.

## Scope

### Initial Milestone

The first milestone should ship only the smallest useful slice:

- manual review through one `Review…` entry
- target picker with `Unstaged Changes`, `Staged Changes`, `Last Commit`, and `Current Branch`
- local host execution only
- structured JSON audit result
- reducer-owned review run and issue state
- `Reviews` section in `Files`
- dedicated review tab
- per-run follow-up harness selection with one `Fix` action
- repository review settings for harness selection and future trigger enablement

### Deferred

Do not build these into the first milestone:

- automatic hook triggers
- pull request automation
- durable queued trigger delivery when the app is closed
- remote runner support
- standalone issue tabs
- automatic code changes from review issues

## Data Model Decisions

These decisions should be treated as plan defaults unless implementation proves they are wrong.

### Review State Boundary

Add a new review slice under `Packages/AppFeatures/Sources/AppFeatures/Reviews/`.

Reducer-owned primitives:

- `ReviewTarget`
- `ReviewTrigger`
- `ReviewProfile`
- `ReviewRun`
- `ReviewIssue`
- `ReviewFixDraft`
- `ReviewWorkspaceState`

Window-owned integration points:

- `reviewWorkspacesByID: [Workspace.ID: ReviewWorkspaceState]`
- review actions and effects in `WindowFeature+Reviews.swift`
- review tab support in `WorkspaceTabContent`

### Settings Shape

Add a narrow nested value to `RepositorySettings`:

- `review: ReviewSettings`

`ReviewSettings` should contain only:

- enabled triggers
- preferred audit harness
- preferred follow-up harness
- optional audit model override
- optional follow-up model override
- optional reasoning overrides
- optional dangerous-permissions overrides when they truly differ from launcher defaults
- optional additional review instructions text

It must not contain:

- review runs
- issue state
- artifact paths
- review history

### Runner Location

Model runner location explicitly from the start:

- `localHost`
- `remoteHost`
- `macMini`

Only `localHost` needs implementation in the first milestone.

## Execution Plan

Update ticket status in this document as work lands.

### Recommended First Pass Order

Build the first milestone in this order:

1. `RVW-01` review domain
2. `RVW-04` review persistence
3. `RVW-05` review context builder
4. `RVW-06` headless audit executor
5. `RVW-02` shell integration
6. `RVW-03` files sidebar review section
7. `RVW-07` review tab UI
8. `RVW-08` investigation handoff

Reason:

- the audit path needs to be real before the shell can present believable review state
- shell work is much easier once the run and artifact model is concrete
- staged follow-up launch should reuse real review issues, not placeholders

### RVW-01 Review Domain

Status: completed

Create the reducer-owned review model and state in `Packages/AppFeatures`.

Deliverables:

- review models with explicit IDs and statuses
- `ReviewWorkspaceState`
- reducer actions for load, create run, update run, dismiss issue, accept risk, and prepare follow-up
- dependency client interfaces for execution, persistence, and trigger ingress
- reducer tests for run lifecycle and issue state transitions

Progress:

- reducer-owned review models, workspace state, and dependency clients have been added
- run lifecycle and issue transition coverage exists in `WindowFeatureReviewTests` and `ReviewModelsTests`
- reducer-owned review state, lifecycle, issue transitions, and coverage are in place

### RVW-02 Shell Integration

Status: completed

Integrate review into the reducer-owned shell.

Deliverables:

- `WorkspaceTabContent.reviewRun(workspaceID:runID:)`
- review tab metadata and semantic identity support
- relaunch persistence support for review tabs
- review workspace state accessors in `WindowFeature.State`
- one reducer-owned `Review…` entry flow
- target-picker presentation and reducer state
- command-palette and sidebar wiring that both route into the same review-entry flow

Progress:

- reducer-owned `Review…` entry flow, target picker state, review tab identity, and review workspace loading are wired
- shell integration, relaunch support, and reducer-owned entry flow are implemented and validated

### RVW-03 Files Sidebar Review Section

Status: completed

Add a dedicated `Reviews` section under `Files`.

Deliverables:

- sidebar summary rows for active and recent runs
- one primary `Review…` action
- status and open-item summaries in the section
- concise trigger labels
- explicit open-rerun actions
- no review content under the `Agents` sidebar

Progress:

- the `Reviews` section and primary `Review…` action exist
- the `Reviews` section now behaves as an attention queue with active runs first, actionable completed runs second, and automatic removal once a run no longer needs attention

### RVW-04 Review Persistence

Status: completed

Add host-side persistence in app support.

Deliverables:

- `ReviewStorageLocations`
- `ReviewPersistenceStore`
- artifact directory layout for run metadata, parsed results, raw output, and follow-up prompts
- load recent runs for a workspace
- prune strategy with explicit retention policy

The storage pattern should mirror workflow runtime storage, not repo-local workflow definition storage.

Progress:

- `ReviewStorageLocations` and `ReviewPersistenceStore` exist
- runs, issues, and artifacts now persist under app support outside the repository
- handled reviews are deleted from durable storage so stale review history does not accumulate across restarts

### RVW-05 Review Context Builder

Status: completed

Build the explicit input normalizer for audits.

Deliverables:

- target normalization for `stagedChanges`
- diff summary and changed-file capture
- governing `AGENTS.md` chain resolution for changed files
- canonical-doc inclusion rules
- size-capped prompt context assembly

The builder must prefer explicit excerpts and references over dumping full docs.

Progress:

- manual targets currently supported are `unstagedChanges`, `stagedChanges`, `lastCommit`, `currentBranch`, and `pullRequest`
- the builder captures changed files, diff stat, diff patch, governing `AGENTS.md`, and canonical docs with size caps
- pull-request review context now includes explicit branch and base metadata alongside the local diff against the PR base branch
- the shipped builder covers all current targets and the final branch/base metadata needed for PR review

### RVW-06 Headless Audit Executor

Status: completed

Add a host-side review executor that runs non-interactively and returns structured JSON.

Deliverables:

- `ReviewAuditController`
- strict prompt composition for audit mode
- Claude and Codex command resolution for headless runs
- raw stdout and stderr capture
- parsed JSON persistence
- parse-failure diagnostics surfaced as failed runs

The executor must not silently treat malformed output as success.

Progress:

- `ReviewAuditController` exists and resolves Claude and Codex headless commands
- stdout, stderr, parsed JSON, and summary artifacts are persisted
- malformed output currently becomes an explicit failed run with captured artifacts
- executor validation is complete on the supported package and app entry points

### RVW-07 Review Tab UI

Status: completed

Add a dedicated review tab surface.

Deliverables:

- run header and target summary
- header metadata for trigger, harness, model, and timestamps
- issue list grouped or sorted by severity
- issue detail panel or inline inspector
- explicit failed-state surface with raw output access
- compact artifact access menu
- actions for dismiss, follow-up harness selection, and fix

Keep the first version simple. Do not add multi-pane inspector complexity unless the basic layout is clearly insufficient.

Progress:

- the dedicated review tab exists and renders the first-pass run and issue surface
- the run header now exposes target, trigger, harness, model, timestamps, and compact persisted artifact access
- issue cards now use the minimal `Dismiss | Fix` flow with a per-run harness selector
- rerun, severity-first issue ordering, failure-state artifact access, and active-item filtering are all implemented

### RVW-08 Investigation Handoff

Status: completed

Add per-issue follow-up launch behavior using existing launcher infrastructure.

Deliverables:

- per-run follow-up harness selection
- one `Fix` action that uses the selected harness
- follow-up prompt artifact generation
- launcher resolution through `RepositoryLaunchPlanner`
- staged terminal command launch in the same workspace

The default prompt must tell the model to verify the issue, decide whether it is worth fixing, and propose a precise fix plan without coding yet.

Progress:

- review issue fix actions already generate staged follow-up launches for the currently selected harness
- prompt artifacts are now persisted and inspectable from the review tab
- follow-up prompt generation, artifact persistence, staged terminal launch preparation, and explicit follow-up status transitions are implemented

### RVW-09 Review Settings

Status: completed

Add narrow repo-scoped review settings and settings UI.

Deliverables:

- `ReviewSettings` in `RepositorySettings`
- repository settings editor controls for trigger preferences
- repository settings editor controls for audit and follow-up harness choice
- repository settings editor controls for optional model and reasoning overrides
- repository settings editor control for additional review instructions
- clear fallback rules to launcher templates
- explicit default values with no hidden dynamic harness selection

Avoid copying the full launcher editor into a second review-specific settings system.

Progress:

- repository settings now expose review enablement, audit and follow-up harness selection, model and reasoning overrides, and additional instructions
- review settings persistence coverage now includes explicit override decoding and repository-store round trips
- `reviewOnCommit` now drives repo-scoped post-commit hook installation and removal through host lifecycle sync

### RVW-10 Trigger Ingress

Status: completed

Add a dedicated review trigger path.

Deliverables:

- `ReviewTriggerIngressClient`
- `Devys --review-trigger ...`
- host-side distributed notification bridge or equivalent local ingress
- reducer observation startup for review triggers

This must stay separate from workspace attention notifications.

Progress:

- `ReviewTriggerIngressClient` now feeds reducer-owned review trigger observation alongside workspace operational observation
- `Devys --review-trigger ...` now accepts structured review target and trigger arguments and posts a dedicated distributed notification
- the mac host now bridges review trigger notifications into the local notification center and decodes them into `ReviewTriggerRequest`
- reducer trigger handling now creates background review runs without stealing focus and only allows settings-enabled automation paths
- focused host tests cover payload decoding and reducer tests cover background run creation from trigger ingress

### RVW-11 Post-Commit Automation

Status: completed

Add the first local automation path after manual review is stable.

Deliverables:

- repository-scoped hook installation for `post-commit`
- small trigger payload with commit SHAs and repo root
- manual enablement through review settings

The hook should only notify Devys. It must not run the audit itself.

This should be the first automation milestone after the manual MVP, not a distant later feature.

Progress:

- repo-scoped `post-commit` hook installation now exists through `ReviewTriggerHooks`
- the managed hook only notifies Devys and never runs the audit itself
- existing user `post-commit` hooks are backed up once and restored when review-on-commit is disabled
- host lifecycle sync now installs, updates, and removes managed hooks from repository review settings
- targeted host tests now cover managed hook creation, script contents, and backup-restore behavior

### RVW-12 Pull Request Review

Status: completed

Add PR review support after manual staged-change review is stable.

Deliverables:

- `Pull Request` as a target in the single `Review…` picker when the current workspace has mapped PR metadata
- PR target normalization using existing workspace PR metadata plus local git base-branch diffing
- PR file and metadata inclusion in review context
- normal rerun behavior for persisted PR review targets without a second PR-specific entry flow

Progress:

- the manual `Review…` flow now exposes `Pull Request` only when the selected workspace already has mapped PR metadata
- reducer launch logic now builds PR review targets from the tracked PR number, title, head branch, and base branch
- host audit execution now diffs `HEAD` against the PR base branch locally and records explicit branch and base metadata in the review snapshot
- reducer coverage now verifies PR target availability and PR review launch construction
- host coverage now verifies PR review execution against the tracked base branch context

### RVW-13 Closeout

Status: completed

Finish with explicit verification and cleanup.

Deliverables:

- reducer and host tests for the new review boundaries
- deletion of any temporary review shims
- doc updates if durable doctrine changes
- final validation using supported scheme and package entry points

Progress:

- AppFeatures package tests are passing
- targeted `mac-clientTests/ReviewAuditControllerTests` are passing
- targeted `mac-clientTests/ReviewTriggerHooksTests` are passing
- targeted `mac-clientTests/ReviewTriggerIngressTests` are passing
- `xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' build` is passing after the final Swift 6 and host-review cleanup
- `xcodebuild -scheme ios-client -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` is passing after the final closeout sweep

## Acceptance Criteria

This plan is not complete until all of the following are true:

- review runs and issues are reducer-owned
- the sidebar and tab shell present review as a first-class feature under `Files`
- audit execution is host-owned and non-interactive
- structured JSON output is required and validated
- malformed audit output produces an explicit failed run
- per-issue investigation launches reuse existing launcher resolution and staged terminal behavior
- review configuration is repo-scoped and narrow
- review artifacts are stored outside the repository by default
- no review manager, registry, or service locator becomes the app-domain owner

## Validation

Every implemented slice should validate with the supported repo entry points:

- `swift test` in touched packages
- `xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -scheme ios-client -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Add targeted tests for:

- reducer run lifecycle
- issue dismissal and accepted-risk transitions
- audit command construction
- follow-up command staging
- context-builder instruction resolution
- trigger decoding
- review tab empty, running, completed, and failed states

## Open Questions

These stay open for implementation scoping, not architecture expansion:

- Should a review run load only recent history by default, and if so how many runs?
- Should the first review tab use a single-column detail layout or a split issue inspector?
- What is the initial artifact retention window in app support?
- Does the first trigger ingress need durable queueing when Devys is not running, or is best-effort delivery enough for MVP?
- Should a completed follow-up investigation link back to its originating issue in the first version, or can that wait?
