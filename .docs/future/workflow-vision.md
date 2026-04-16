# Workflow Vision

Updated: 2026-04-15

## Summary

This document defines future product direction for reusable multi-agent workflows in Devys.

It is not part of the current architecture migration source of truth. Active migration sequencing lives in `../plan/implementation-plan.md`.

The product goal is:

- let a user create explicit reusable workflows for Claude Code and Codex
- bind each workflow run to a dedicated worktree
- run workflows either headlessly or in an interactive modal
- make progress, commits, phases, active step, and terminal output visible at all times
- allow the user to stop, restart, continue, and steer a run without losing context

The implementation goal is:

- ship a useful v1 without building a generic orchestration framework
- use a simple ordered phase pipeline first
- keep the data model stable so later versions can add Canvas-based visualization/editing and agent-authored workflow generation without rewriting the core system

## Product Principles

- Workflow execution is explicit, not magical.
- A workflow is a repeatable phase pipeline, not a freeform graph in v1.
- A workflow run owns one worktree and one branch.
- Prompt files are real files on disk.
- The UI should expose exactly what will run.
- The user should never feel lost in navigation.
- The modal is the control room; the main window remains the workspace.
- Terminals are the execution primitive; structured parsing is an enhancement, not the source of truth.
- The workflow engine should be small, file-backed, and restartable.

## UX Direction

The workflow UI should feel like a native operator console inside Devys, not like a separate low-code builder product.

The current app already has the right high-level structure:

- worktrees and repository state
- PTY-backed terminal tabs
- agent sessions
- modal sheets for focused flows
- workspace-aware status and persistence

We should extend that model, not replace it.

## Core Mental Model

- A workflow definition is a reusable template.
- A workflow run is one execution of that template.
- A workflow run is bound to one worktree.
- A workflow phase is a user-meaningful milestone, usually ending in a commit.
- A workflow step is one executable unit inside a phase.
- A run can be automated, supervised, or mixed.

For your workflow style, the default shape should be:

1. prepare plan context
2. claude implement
3. claude self-audit
4. codex review
5. codex fix
6. quality gate
7. update plan doc
8. commit phase
9. continue to next phase

This is intentionally serial and explicit.

## Sidebar Change

Do not keep Files, Changes, Ports, Agents, and Workflows all crammed into one scrolling sidebar.

Replace the current stacked multi-section sidebar model with top tabs:

- `Files`
- `Agents`

### Files Tab

The Files tab owns repository navigation and code inspection for the active worktree:

- file tree
- git changes / diffs
- later: search and related code-inspection tools if needed

This tab answers:

- what files are here
- what changed
- what should I inspect next

### Agents Tab

The Agents tab owns workflow and execution oversight for the active worktree:

- active workflow runs
- workflow templates relevant to this repository
- active agent sessions
- step status
- progress through phases
- intervention controls

This tab answers:

- what is running
- what phase is active
- what agent is doing work
- what needs attention

This keeps the sidebar legible and preserves the terminal-first feel.

## North Star

Long term, Devys should support three coordinated ways to work with workflows:

1. direct authoring in the modal builder
2. visual overview and editing through Canvas
3. agent-authored workflow creation and editing through a CLI plus repo skill

All three must target the same underlying workflow definition schema.

That means v1 must not hardcode UI-only assumptions into the runtime.

## Current Foundations In The Repo

Devys already has several pieces we should build on directly:

- repository-scoped launcher settings for Claude and Codex
- worktree creation and import flows
- persistent PTY-backed terminal hosting
- worktree-aware runtime ownership
- agent session views with timeline, tool-call display, and stop/retry controls
- modal sheet presentation patterns

Relevant existing surfaces:

- `Apps/mac-client/Sources/mac/Views/Window/ContentView.swift`
- `Apps/mac-client/Sources/mac/Views/Sidebar/UnifiedWorkspaceSidebar.swift`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+LaunchActions.swift`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+TerminalPersistence.swift`
- `Apps/mac-client/Sources/mac/Services/PersistentTerminalHostDaemon.swift`
- `Apps/mac-client/Sources/mac/Views/Window/AgentSessionView.swift`
- `Apps/mac-client/Sources/mac/Models/Agents/AgentSessionModels.swift`
- `Packages/Git/Sources/Git/Services/Worktree/WorkspaceCreationService.swift`
- `Packages/Workspace/Sources/Core/Models/RepositorySettings.swift`
- `Apps/mac-client/Sources/mac/Views/Settings/RepositorySettingsSection.swift`

The archived Canvas package is a good future fit for visualization and editing, but it should not be on the critical path for workflow v1.

## Data Model

Define a stable, file-backed workflow domain model.

### WorkflowDefinition

A reusable template that lives in the repository or local Devys metadata.

Suggested shape:

```json
{
  "id": "phase-delivery",
  "name": "Phase Delivery",
  "description": "Claude implements, Codex reviews, Codex fixes, then quality gates and commit.",
  "version": 1,
  "defaultMode": "interactive",
  "plan": {
    "source": ".docs/plan.md"
  },
  "phases": [
    {
      "id": "phase-1",
      "name": "Phase 1",
      "commitStrategy": "one_commit",
      "steps": [
        {
          "id": "claude-implement",
          "kind": "agent",
          "runner": "claude",
          "promptFile": "prompts/claude-implement.md",
          "mode": "supervised"
        }
      ]
    }
  ]
}
```

### WorkflowPhase

- stable id
- name
- optional description
- commit policy
- completion policy
- ordered steps

### WorkflowStep

Supported v1 step kinds:

- `agent`
- `quality_gate`
- `doc_update`
- `commit`
- `pause`

Supported v1 runners:

- `claude`
- `codex`
- `shell`
- `internal`

Supported v1 execution modes:

- `headless`
- `supervised`
- `manual`

### WorkflowRun

Runtime state for one execution:

- workflow id and version
- run id
- repository id
- worktree id / path
- branch
- phase index
- step index
- status
- started / updated timestamps
- active process metadata
- active session metadata
- commit log
- artifact paths
- operator notes

### WorkflowArtifact

Named outputs produced by steps:

- review findings
- fix plan
- quality gate result
- commit message
- updated plan snapshot
- logs

Artifacts must be addressable by later steps.

## Files On Disk

Use simple, inspectable files.

### Committed Workflow Definitions

Recommended repo location:

```text
.devys/workflows/
  phase-delivery/
    workflow.json
    prompts/
      claude-implement.md
      claude-audit.md
      codex-review.md
      codex-fix.md
      commit.md
```

Why committed:

- reusable across runs
- reviewable in Git
- easy to diff
- easy for future agents to create and edit

### Local Run State

Recommended local location:

```text
.devys/runs/
  <run-id>/
    state.json
    events/
    artifacts/
    terminals/
```

This should be gitignored.

### Prompt Files

Every prompt should be editable as a real file, not just inline UI state.

The modal editor can edit the file contents directly, but the source of truth stays on disk.

## Worktree Model

One workflow run should map to one worktree.

Why:

- matches your working style
- keeps branch and diff state explicit
- keeps commits scoped
- makes run status naturally worktree-aware in the UI
- aligns with existing Devys workspace/worktree architecture

Rules:

- starting a workflow can create a new worktree or bind to an existing one
- one active run per worktree in v1
- runs store the exact worktree path and branch
- deleting a run does not automatically delete the worktree unless the user explicitly asks

## Execution Model

The workflow engine should be a small serial state machine.

### Runner Loop

For each step:

1. load run state
2. resolve step inputs
3. launch the step
4. stream and persist events
5. collect artifacts
6. mark step success / failure / interrupted
7. advance only when the step completion policy passes

### Headless Steps

Used when the user wants unattended execution.

- Claude headless steps run via CLI print mode with structured output capture
- Codex headless steps run via CLI JSONL output capture
- shell steps run through a managed command execution path

### Supervised Steps

Used when the user wants live terminal oversight and the ability to intervene.

- launch the real CLI in a PTY-backed terminal tab
- mirror terminal output inside the workflow modal
- allow stop, restart, and operator message injection

### Manual Steps

Used for intentional pauses:

- waiting for human review
- waiting for external validation
- waiting for a deployment or merge

## Intervention Model

The user must be able to intervene without breaking the run model.

Supported controls:

- `Stop`
- `Restart Step`
- `Continue`
- `Retry Last Prompt`
- `Steer`
- `Open Terminal`
- `Open Worktree`
- `Open Diff`
- `Mark Complete`
- `Mark Failed`

### Stop

Stops the current executing step and records the run as interrupted.

### Restart Step

Re-executes the current step from its persisted boundary.

### Continue

Advances from the current state once the current step is complete or manually approved.

### Steer

Adds operator input to the active supervised session or appends a steering note for the next headless resume.

### Resume After App Restart

The workflow engine must rehydrate:

- active run state
- associated worktree
- active terminal if still alive
- associated artifacts
- current phase / step cursor

## UI Surfaces

## 1. Entry Points

Add workflow entry points in three places:

- titlebar action
- Agents sidebar tab
- command palette

The titlebar action opens the workflow modal.

## 2. Agents Sidebar Tab

The Agents tab should be split into two clear blocks:

- `Workflows`
- `Agent Sessions`

### Workflows Block

Show:

- active run cards
- current phase
- current step
- status badge
- elapsed time
- latest commit
- quick actions

Quick actions:

- open run
- resume
- stop
- open worktree

### Agent Sessions Block

Show:

- currently open agent sessions in this worktree
- session type
- busy / idle / attention-needed state

This keeps workflows and ad hoc agent sessions related but distinct.

## 3. Workflow Modal

The modal is the primary workflow surface.

It should support two modes:

- builder / editor
- run monitor / control

### Modal Shell

Three-column layout:

- left: workflow templates and recent runs
- center: definition or run timeline
- right: inspector

The modal should stay anchored and persistent. Closing it should never cancel a run.

### Builder Mode

Left column:

- templates
- duplicate
- rename
- create new

Center column:

- ordered phases
- ordered steps inside each phase
- add / remove / reorder

Right inspector:

- step type
- runner
- model
- launcher / harness profile
- execution mode
- prompt file
- prompt preview / editor
- artifact expectations
- completion behavior

### Run Mode

Left column:

- active runs
- paused runs
- recent completed runs

Center column:

- current phase and step ladder
- live transcript or terminal view
- artifact list
- commit history for this run

Right inspector:

- step prompt
- run state
- worktree / branch
- intervention controls
- execution metadata

## 4. Worktree Status

Workflow state must also be visible outside the modal.

Add lightweight workflow status to:

- navigator worktree rows
- status bar when a workflow-owned worktree is active

Suggested visible fields:

- workflow name
- phase
- active step
- running / paused / blocked / failed / complete

## V1 Scope

V1 should solve the real workflow problem without visual graph editing.

### V1 Includes

- workflow definition schema
- committed workflow definitions and prompt files
- local run state and artifact storage
- one workflow run per worktree
- ordered phases and steps
- Files | Agents sidebar tab split
- workflow modal builder/editor
- workflow run monitor
- headless and supervised step execution
- explicit stop / restart / continue / steer controls
- phase-level commits
- run progress in sidebar and navigator
- rehydration after app restart

### V1 Default Workflow Preset

Ship one opinionated starter template:

- phase-based delivery workflow
- Claude implement
- Claude self-audit
- Codex review
- Codex fix
- tests / lint / typecheck
- update plan doc
- commit phase

This should work immediately and demonstrate the system.

### V1 Non-Goals

- generic DAG editing
- arbitrary conditional branching
- parallel fan-out / fan-in execution
- visual canvas editing
- remote collaboration
- multi-repo workflows
- automatic PR creation
- automatic deployment orchestration

## V1 Implementation Plan

### Phase 1: Domain And Persistence

- add workflow definition models
- add workflow run models
- add file-backed workflow store
- add run-state persistence
- add artifact store
- add migration/version field support from day one

Suggested files:

- `Apps/mac-client/Sources/mac/Models/Workflows/...`
- `Apps/mac-client/Sources/mac/Services/Workflows/...`

### Phase 2: Sidebar Restructure

- replace the current unified stacked sidebar with top tabs: `Files | Agents`
- move file tree and diff/change surfaces under `Files`
- move agent sessions and workflow surfaces under `Agents`
- preserve worktree awareness and current active workspace behavior

### Phase 3: Modal Builder

- add a workflow modal shell
- add template list
- add create / duplicate / rename / delete
- add phase and step editing
- add prompt file editing
- add harness profile and model selection

### Phase 4: Runtime Engine

- implement serial step execution
- implement run cursoring
- implement headless step execution
- implement supervised PTY-backed step execution
- persist event logs and artifacts

### Phase 5: Run Monitor

- add active run list
- add live step state
- add terminal mirroring
- add artifact inspector
- add commit log inspector

### Phase 6: Intervention And Recovery

- stop
- restart step
- continue
- steer
- recover active runs on relaunch

### Phase 7: Quality And Presets

- add starter workflow templates
- add validation and guardrails
- add tests for persistence, execution state, and sidebar state

## V2: Canvas Visualization And Editing

V2 should use the archived Canvas work to visualize and edit workflows.

Important constraint:

Canvas is not the source of truth.

The same workflow definition schema from v1 remains canonical. Canvas becomes another editor and visualization layer over that schema.

### V2 Goals

- visualize workflows as phase/step graphs
- edit workflow structure spatially
- make long workflows easier to reason about
- preserve a modal context so the user never feels dropped into a separate app mode

### V2 UI Shape

Inside the workflow modal, add a view switch:

- `List`
- `Canvas`

List remains the explicit editor.
Canvas becomes the visual editor and overview.

### V2 Canvas Behaviors

- phase groups
- step nodes
- dependency connectors
- quick add
- drag to reorder
- inspector-driven editing
- zoom / pan / focus current phase
- run overlay showing active step and completed phases

### V2 Constraints

- no workflow logic should live only in node position or edge state
- Canvas edits must round-trip cleanly to the list editor
- Canvas should remain optional, not required

## V3: Agent-Authored Workflow Creation And Editing

Later, Devys should support a CLI plus a repo skill that lets an agent create or edit workflows for the user.

This is the long-term "describe it, let an agent build it, then adjust it in the UI" path.

### V3 Goals

- let the user describe a workflow in natural language
- let an agent generate the workflow definition and prompt files
- let the user inspect and edit the result in the modal builder
- let an agent later refactor or update a workflow safely

### V3 Deliverables

- a Devys CLI command for workflow creation / editing
- a `SKILL.md` contract for workflow authoring
- stable prompt and definition templates
- validation and preview before write

### Example Future Commands

```bash
devys workflow create "build me a claude->codex phase workflow for large refactors"
devys workflow edit phase-delivery --add-step "security review with codex"
devys workflow validate phase-delivery
```

### Why This Matters

If the workflow format is file-backed, explicit, and stable in v1:

- agents can generate workflows safely
- workflows stay reviewable in Git
- users can still edit prompts and models manually
- Canvas can visualize the same definition later

## Future Extensions After V3

- conditional step transitions
- branch templates per workflow
- reusable step libraries
- shared org-level workflow packs
- richer review step primitives
- PR creation and merge helpers
- deployment-aware workflow gates

## Risks

### Risk: Over-engineering Early

Mitigation:

- v1 is phase pipeline only
- no generic graph runtime
- no speculative orchestration DSL

### Risk: Splitting Reality Between PTY And Structured Events

Mitigation:

- terminal output is the execution truth
- structured logs are supplementary
- every step still persists explicit status and artifacts

### Risk: Workflow Definitions Drift From How You Actually Work

Mitigation:

- ship one strongly opinionated starter template first
- optimize for your actual phase loop before generalizing

### Risk: Canvas Forces Premature Graph Semantics

Mitigation:

- keep Canvas in v2
- keep list editor canonical

## Design Rules

- prefer explicit labels over abstract metaphors
- keep controls close to the currently active step
- never hide worktree ownership
- always show phase and step together
- keep prompt editing one click away
- keep the modal anchored and resumable
- avoid deep nested navigation

## Recommended First Slice

If building incrementally, the first useful slice should be:

1. file-backed workflow definition
2. Files | Agents sidebar split
3. workflow modal with list editor
4. one starter workflow template
5. create run on a worktree
6. supervised Claude step in a terminal
7. supervised Codex step in a terminal
8. manual quality gate step
9. commit-phase step
10. persisted run state and sidebar progress

That gets a real end-to-end workflow into the product quickly and keeps the architecture aligned with the long-term plan.
