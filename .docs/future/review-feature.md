# Devys Review Feature

Status: future design brief

Updated: 2026-04-19

## Purpose

This document defines the target architecture for a first-class review feature in Devys.

The feature should support:

- manual review runs
- automatic review on commit
- review of pull requests and pull request updates
- issue lists grounded in repo conventions, `AGENTS.md`, and canonical docs
- per-issue follow-up actions that open Claude Code or Codex in a terminal with a precise staged prompt
- later execution on a remote Mac mini or other host without changing the client-side product model

This brief is not an active work plan. When this slice becomes active, move it into `../active/` and turn it into the working plan.

This brief is written to fit the current repo doctrine:

- TCA owns app-domain review state, presentation, policy, and intent
- host services execute audits and terminal launches
- `Apps/mac-client` remains a thin host and composition layer
- no mirrored ownership between reducers and host runtimes
- no new app-domain manager or registry becomes the source of truth

## High-Level Goal

Devys should make repository review a first-class activity instead of treating it as an ad hoc chat prompt.

The target experience:

- a user commits code
- Devys can automatically trigger a review audit for that commit
- the audit inspects the diff, repository conventions, relevant `AGENTS.md`, and canonical docs
- the audit returns a structured issue list
- each issue links to the relevant diff and files
- the user can dismiss an issue or ask Devys to investigate it further
- clicking the follow-up action opens Claude Code or Codex in a terminal using the user's configured launcher settings
- the command is staged so the prompt is visible and editable before execution
- the prompt says to deeply investigate the issue, determine whether it is real and worth fixing, and propose a comprehensive fix without coding yet

The same primitives should later power:

- manual review on the current working tree
- staged diff review before commit
- review when opening or updating a pull request
- review on a remote Mac mini or other durable host

## Non-Goals

This slice should not:

- replace repo-scoped agent sessions
- replace repo workflows
- auto-apply code changes from review findings
- introduce a third primary sidebar mode beyond `Files` and `Agents`
- turn `Packages/Git` into an app-domain review owner
- turn `Packages/Workspace` into a stateful review coordinator
- require a durable server or daemon for the first local implementation

## Current Repo Reality

Several useful seams already exist:

- The canonical shell already has exactly two primary sidebar modes, `Files` and `Agents`.
- The current sidebar implementation already supports multiple sections within each primary mode.
- Repository-scoped Claude and Codex launcher configuration already exists, including model, reasoning, permission bypass, and staged-vs-immediate launch behavior.
- Reducer-owned workflow state already exists.
- Host-side workflow execution already writes prompt artifacts and launches Claude or Codex.
- Git and GitHub primitives already expose staged changes, pull request metadata, and pull request files.
- The app already has a narrow cross-process ingress path for external notifications.

These seams are useful, but they are not enough on their own.

What is still missing:

- a reducer-owned review domain
- structured review outputs with issue lists
- review-specific persistence
- review-specific tab content
- a trigger system for commit and pull request review
- a host executor that runs headless audits and captures structured results
- a per-issue follow-up flow that stages investigation prompts in terminals

## Product Model

Review is a first-class repo-scoped feature.

It is not:

- just another workflow
- just another agent session
- just another git sidebar state

Review should be modeled as:

- a review target
- a review run against that target
- a structured list of review issues
- explicit issue lifecycle and follow-up actions

This keeps the mental model simple:

- `Agents` remain live interactive sessions and workflows
- `Files` remains the place where files, diffs, reviews, and commit-adjacent work live

## Shell Placement

The review feature should live in the `Files` sidebar mode, not `Agents`.

Recommended sidebar structure:

- `Files`
- `Reviews`
- `Changes`
- `Ports` when present

Reasoning:

- review is anchored to diffs, commits, pull requests, and changed files
- the user will usually enter review from file changes or commit activity
- keeping reviews in `Files` avoids overloading `Agents` with non-session concepts
- this preserves the current shell doctrine without adding a third primary mode

The `Reviews` section should show:

- active review runs first
- recent completed runs second
- open issue counts and severity summaries
- the current target, such as `Working Tree`, `Staged Changes`, `Commit abc1234`, or `PR #42`

The full review surface should open in the existing split/tab shell as a dedicated review tab.

The sidebar is a summary and launch surface. The tab is the main inspection surface.

## Core Design Principles

- `Packages/AppFeatures` owns review state, run metadata, issue metadata, lifecycle, and navigation.
- `Apps/mac-client` owns audit execution, terminal staging, hook ingestion, and low-level process handling.
- `Packages/Git` remains the source of git and pull request capability, not app review policy.
- `Packages/Workspace` remains the source of repo-scoped configuration and launcher templates, not run state.
- Structured outputs are mandatory. Free-form markdown-only audit responses are not enough.
- Review issues must be explicit, inspectable, and dismissible.
- Follow-up investigation should be explicit and user-visible. No hidden background coding.
- The first implementation should be local-first but must preserve a path to remote host execution later.

## Feature Primitives

The feature should be built around a small set of explicit primitives.

### Review Target

`ReviewTarget` identifies what is being audited.

Target kinds:

- `workingTree`
- `stagedChanges`
- `commit`
- `commitRange`
- `pullRequest`
- `selection`

Expected fields:

- stable target ID
- repository ID
- workspace ID when local and open in the shell
- repository root URL
- display title
- comparison refs or commit SHAs when relevant
- pull request number and metadata when relevant
- selected paths when relevant

### Review Trigger

`ReviewTrigger` records why the run happened.

Trigger kinds:

- `manual`
- `postCommitHook`
- `pullRequestCommand`
- `pullRequestHook`
- `workspaceOpen`
- `scheduled`
- `remoteHost`

Expected fields:

- trigger ID
- source
- timestamp
- whether the run was user-visible or background-triggered

### Review Profile

`ReviewProfile` describes how the audit and follow-up should run.

Fields:

- audit harness: `claude` or `codex`
- follow-up harness: `claude` or `codex`
- audit model override
- follow-up model override
- audit reasoning level
- follow-up reasoning level
- dangerous-permissions flags for both paths
- audit runner location
- follow-up launch behavior
- enabled triggers

The review feature should reuse the existing launcher templates as the base command source.

Review-specific settings should remain narrow and explicit. They should not duplicate the entire launcher model unless a real divergence appears.

### Review Run

`ReviewRun` is the canonical reducer-owned record of one audit.

Fields:

- run ID
- target
- trigger
- profile ID or resolved profile snapshot
- status
- created, started, and completed timestamps
- artifact paths
- summary counts
- issue IDs
- last error message when failed

Statuses:

- `queued`
- `preparing`
- `running`
- `completed`
- `failed`
- `cancelled`

### Review Issue

`ReviewIssue` is the canonical unit shown to the user.

Fields:

- issue ID
- run ID
- severity
- confidence
- title
- summary
- rationale
- relevant file paths
- relevant hunks or line references when available
- rule or convention source references
- dedupe key
- status

Issue statuses:

- `open`
- `dismissed`
- `acceptedRisk`
- `followUpPrepared`
- `resolved`

### Review Artifact Set

Each run should have explicit artifacts.

Artifacts:

- normalized review input snapshot
- prompt artifact
- raw stdout artifact
- raw stderr artifact
- parsed JSON artifact
- rendered summary artifact when useful
- follow-up prompt artifacts for issue investigation

Run artifacts should live in app support, not in the repository by default.

### Review Fix Draft

The user-facing "Fix" action should actually be an investigation handoff first.

`ReviewFixDraft` should capture:

- issue ID
- selected harness
- resolved command preview
- prompt artifact path
- terminal launch mode

Default prompt behavior:

- explain the issue
- include the relevant files and diff references
- ask the model to determine whether the issue is real
- ask whether it is worth fixing
- ask for a comprehensive and precise fix plan
- explicitly say not to code yet

## Recommended Data Model Boundary

Review state should live in `Packages/AppFeatures`.

Recommended package areas:

- `Packages/AppFeatures/Sources/AppFeatures/Reviews/`
- `Packages/AppFeatures/Sources/AppFeatures/SharedDependencies/ReviewExecutionClient.swift`
- `Packages/AppFeatures/Sources/AppFeatures/SharedDependencies/ReviewPersistenceClient.swift`
- `Packages/AppFeatures/Sources/AppFeatures/SharedDependencies/ReviewTriggerIngressClient.swift`
- `Packages/AppFeatures/Sources/AppFeatures/Window/WindowFeature+Reviews.swift`

Host execution should live in `Apps/mac-client`.

Recommended host areas:

- `Apps/mac-client/Sources/mac/Services/Reviews/ReviewAuditController.swift`
- `Apps/mac-client/Sources/mac/Services/Reviews/ReviewPersistenceStore.swift`
- `Apps/mac-client/Sources/mac/Services/Reviews/ReviewTriggerMonitor.swift`
- `Apps/mac-client/Sources/mac/Services/Reviews/ReviewPromptComposer.swift`

Git capability should stay in `Packages/Git`.

Likely additions:

- narrow helpers for commit-range diff capture
- pull request file loading already exists and should be reused
- no review policy should move into `GitStore`

Repository settings should stay in `Packages/Workspace`, but only for narrow repo-scoped review configuration.

Likely additions to `RepositorySettings`:

- review trigger preferences
- preferred review harness selection
- preferred follow-up harness selection
- optional profile overrides

Review runs, issues, and lifecycle must not live in `RepositorySettingsStore`.

## Why This Should Not Be Built As A Workflow

The existing workflow system is useful, but it is not the right product model for review.

Workflows are built around:

- definitions
- graph nodes
- graph edges
- long-lived run attempts
- workflow plan updates

Review is built around:

- a target
- an audit pass
- a structured issue list
- per-issue follow-up actions

The workflow runner is still useful as inspiration and may contribute shared helpers later, but review should remain its own feature slice.

The review feature may eventually reuse extracted lower-level prompt-launch helpers from workflow execution. It should not reuse workflow definitions, nodes, or run semantics directly.

## Review Execution Architecture

The review feature needs two distinct execution paths.

### 1. Audit Execution

Purpose:

- run a headless audit
- capture structured output
- parse issues
- persist artifacts

This path should not depend on an interactive terminal.

Default behavior:

- build normalized input context
- compose a strict review prompt
- invoke Claude or Codex in non-interactive mode
- require structured JSON output
- parse and persist result
- update reducer state with issues

This needs a new host-side executor. The current workflow executor only knows how to launch terminals and observe their exit state.

### 2. Follow-Up Investigation Execution

Purpose:

- let the user select one issue
- launch Claude or Codex in a terminal
- stage a precise prompt for user confirmation and editing

Default behavior:

- resolve the selected launcher command from repository settings
- append the investigation prompt artifact
- open a terminal tab
- stage the command instead of auto-running it

This path should reuse the existing terminal staging behavior already supported by launcher resolution.

## Review Input Context Builder

The review audit is only as good as its input context.

The feature needs an explicit `ReviewContextBuilder` that gathers:

- target diff data
- relevant file list
- pull request metadata when applicable
- governing `AGENTS.md` chain for affected files
- canonical docs relevant to repo-wide rules
- review profile information

For changed files, the builder should collect:

- root `AGENTS.md`
- any deeper `AGENTS.md` that govern touched files
- canonical docs that express repo doctrine

The builder should not blindly dump large files into prompts.

Preferred behavior:

- collect references and relevant excerpts
- include file paths and exact rule sources
- cap context size
- prioritize directly governing instructions over broad background docs

## Structured Output Contract

The audit command should return structured JSON with a stable schema.

Minimum shape:

```json
{
  "summary": {
    "overall_risk": "medium",
    "issue_count": 3
  },
  "issues": [
    {
      "severity": "major",
      "confidence": "high",
      "title": "Review title",
      "summary": "Short explanation",
      "rationale": "Why this matters",
      "paths": ["Packages/AppFeatures/Sources/AppFeatures/Window/Example.swift"],
      "lines": [
        { "path": "Packages/AppFeatures/Sources/AppFeatures/Window/Example.swift", "line": 42 }
      ],
      "sources": ["AGENTS.md", ".docs/reference/architecture.md"],
      "dedupe_key": "example-key"
    }
  ]
}
```

The executor should persist:

- the raw model output
- the parsed result
- parse failure diagnostics when the output is invalid

If parsing fails:

- mark the run as failed
- keep the raw output visible in the review tab
- do not silently downgrade to an unstructured success state

## Trigger Model

The trigger system should be explicit and narrow.

### Manual Triggers

Manual entry points:

- command palette action such as `Review Current Changes`
- button in the `Reviews` sidebar section
- action in the `Changes` section
- action from commit and pull request sheets
- action from a review tab to rerun

### Local Hook Triggers

For commit automation, Devys should support installing a repository-scoped git hook.

Recommended first target:

- `post-commit`

The hook should:

- capture the new commit SHA
- capture the previous SHA when available
- send a small trigger payload to Devys
- return quickly

The hook should not:

- run the full audit itself
- contain business logic
- parse model output

### Pull Request Triggers

The feature should support:

- manual `Review PR` action
- automatic review when a tracked PR is updated later

The trigger payload should carry:

- PR number
- repository root
- head and base refs when known

### Remote Trigger Compatibility

Future remote execution should use the same logical trigger shape.

The client should not care whether the trigger came from:

- a local git hook
- a local manual action
- a remote host
- a Mac mini scheduler

## Trigger Ingress Design

The current notification ingress path only carries attention payloads. Review needs a separate ingress path.

Recommended primitive:

- `ReviewTriggerIngressClient`

Recommended local CLI entrypoint:

- `Devys --review-trigger ...`

Responsibilities:

- decode a small trigger payload
- post it to the running app when available
- optionally persist it into a small local queue when the app is not yet listening

The queue requirement should be deferred if needed, but the API shape should leave room for it.

The review trigger path should not be overloaded onto workspace attention notifications. Attention notifications are for user-visible status pings, not structured review requests.

## Review Persistence

Review persistence needs two layers.

### Configuration Persistence

Repo-scoped settings live with repository settings:

- enabled triggers
- preferred audit harness
- preferred follow-up harness
- optional model and reasoning overrides

### Run Persistence

Run state and artifacts live in app support:

- run metadata
- issue snapshots
- prompt artifacts
- raw outputs
- parsed outputs

This keeps generated review data out of the repository by default and avoids noisy working-tree changes.

The persistence store should support:

- load recent runs for a workspace
- save and update a run
- load issue artifacts
- prune old runs

## Review Tab Model

The feature should add dedicated review tab content rather than overloading workflow or diff tabs.

Recommended new tab cases:

- `reviewRun(workspaceID: Workspace.ID, runID: UUID)`

Optional later:

- `reviewIssue(workspaceID: Workspace.ID, issueID: UUID)`

The review tab should show:

- run header
- target summary
- trigger source
- run status
- issue list with severity and confidence
- raw output and parse diagnostics when needed
- issue inspector content
- actions to open diff, open file, dismiss, or investigate

## Issue Interaction Model

Each issue should support explicit actions.

Core actions:

- `Open Diff`
- `Open File`
- `Dismiss`
- `Mark Accepted Risk`
- `Investigate In Codex`
- `Investigate In Claude`

The investigation action should:

- generate a follow-up prompt artifact
- resolve the appropriate launcher command
- open a terminal tab in the same workspace
- stage the command so the user presses Enter

Default investigation prompt should include:

- issue title and summary
- rationale and severity
- relevant files and lines
- review target summary
- instructions to verify whether the issue is real
- instructions to decide whether it is worth fixing
- instructions to propose a comprehensive and precise fix
- explicit instruction not to code yet

## Configuration Strategy

The feature should reuse the existing repo launcher settings instead of creating a parallel launcher system.

Recommended shape:

- launcher templates remain the source of truth for base Claude and Codex commands
- review settings select which launcher to use for audit and follow-up
- review settings may override model or reasoning only when necessary

This keeps the configuration simple and prevents duplicated command-building logic.

The current workflow executor already knows some Claude and Codex command shapes, but the review feature should prefer extracting shared command-building helpers only if real duplication appears.

## Local Versus Remote Runner Model

The feature should separate review request semantics from runner location.

Recommended enum:

- `localHost`
- `remoteHost`
- `macMini`

The client-side reducer model should stay the same across all runner locations.

What changes by runner:

- where the audit command executes
- how repository files are accessed
- which launcher binary is used
- how artifacts are returned

What must not change by runner:

- review target semantics
- issue schema
- run status model
- sidebar and tab model
- per-issue follow-up action model

This is the critical primitive that lets local review and future Mac mini review share one feature instead of splitting into separate architectures.

## Recommended Build Order

This is the recommended implementation order, not the canonical execution plan.

1. Add the reducer-owned review domain in `Packages/AppFeatures`.
   Include models, state, actions, and dependency clients.

2. Add host-side review persistence and audit execution in `Apps/mac-client`.
   Start with local headless execution only.

3. Add dedicated review tabs and a `Reviews` section in the `Files` sidebar.
   Keep the surface summary-first in the sidebar and detail-first in tabs.

4. Add manual review entry points.
   Support `workingTree`, `stagedChanges`, and explicit commit review first.

5. Add per-issue investigation handoff.
   Reuse launcher resolution and staged terminal command behavior.

6. Add repository-scoped review settings.
   Keep this narrow and avoid putting run state into repository settings.

7. Add local `post-commit` trigger installation and trigger ingress.
   Support auto-review on commit.

8. Add pull request review entry points.
   Use existing GitHub metadata and PR file loading.

9. Add remote runner support later.
   Reuse the same trigger, run, issue, and artifact model.

## Suggested Initial Milestone

The smallest useful first milestone is:

- manual review of `stagedChanges`
- local headless audit execution
- structured issue list
- review tab
- `Investigate In Codex` and `Investigate In Claude` actions that stage the command in a terminal

This delivers the essential product behavior without requiring hooks, pull request automation, or remote execution.

## Testing Strategy

The feature should ship with explicit tests at each boundary.

Reducer tests:

- creating review runs
- state transitions for run success and failure
- issue dismissal and accepted-risk state changes
- opening review tabs from sidebar actions

Execution tests:

- command building for audit mode
- command building for staged follow-up mode
- structured output parsing
- parse failure handling

Context-builder tests:

- changed-file `AGENTS.md` chain resolution
- canonical doc inclusion rules
- diff and pull request target normalization

Ingress tests:

- manual trigger decoding
- commit hook payload decoding
- pull request trigger decoding

UI tests:

- sidebar section rendering
- review tab empty, loading, completed, and failed states
- issue actions opening the correct surfaces

## Verification Entry Points

Any work that lands from this brief should use the repo-supported verification paths:

- `xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -scheme ios-client -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- `swift test` in touched packages

Avoid unsupported `xcodebuild -target ...` verification for the reasons already documented in the repo guide.

## Open Questions

These questions should be resolved during implementation scoping, not by expanding architecture prematurely.

- Should review settings live directly in `RepositorySettings` or in a dedicated nested `ReviewSettings` value inside it?
- Should the first local hook path queue triggers durably when the app is not running, or is best-effort delivery acceptable for MVP?
- Should the review tab support a secondary issue-inspector pane on day one, or is a single-column issue list and detail layout enough?
- How aggressively should old review artifacts be pruned?
- Should a successful follow-up investigation automatically link its terminal session back to the originating issue?

## Summary

The review feature should be built as a dedicated repo-scoped feature, not as a workflow extension and not as an ad hoc chat pattern.

Its core primitives are:

- review targets
- review triggers
- review profiles
- review runs
- review issues
- follow-up investigation drafts
- explicit artifact persistence

Its shell home should be:

- `Files` sidebar mode
- a new `Reviews` section above `Changes`
- dedicated review tabs in the existing pane/tab shell

Its architecture should be:

- reducer-owned state and policy in `Packages/AppFeatures`
- host-owned audit execution and terminal staging in `Apps/mac-client`
- launcher reuse through existing repository settings
- git and pull request capability reuse through `Packages/Git`

That yields a simple and explicit system that can start local and later grow into automated pull request review on a Mac mini without changing the product model.
