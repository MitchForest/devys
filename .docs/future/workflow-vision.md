# Workflow Vision

Updated: 2026-04-17

## Purpose

This document defines the target product shape for reusable workflow execution in Devys.

It is intentionally product-focused.
Active sequencing and migration work live in `../plan/implementation-plan.md`.

## Product Stance

- V1 is a graph-backed workflow system, not a hardcoded executor/reviewer phase runner.
- The workflow-definition builder is Canvas-first.
- A workflow definition binds workers, nodes, edges, prompts, and artifact bindings.
- Interactive agent nodes must run in real PTY-backed terminal tabs.
- The terminal tab is the live execution truth for an active attempt.
- The workflow run tab is an inspector and control surface, not a replacement terminal.
- `steering` means the operator clicks into the running terminal and types.
- Steering is not a persisted note, not a special workflow message, and not a dedicated UI panel.
- Agent-to-agent handoff happens after a node attempt completes and Devys traverses an edge.
- The markdown plan file is an artifact binding and progress document, not the workflow topology.
- V1 does not add agent chat as part of workflow execution.

## Primary V1 Use Case

The first workflow Devys should support is:

1. pick a real planning markdown file
2. create or open a Canvas-backed workflow definition
3. add workers such as implementation and review agents
4. connect nodes explicitly on the canvas
5. run a node in a real terminal
6. click into that terminal and type whenever operator steering is needed
7. let Devys move to the next node after the attempt completes
8. append follow-up work back into the bound plan file when the workflow definition requests it

This should feel like a serious operator workflow with explicit flow control, not like a chat toy and not like a hidden fixed loop pretending to be a builder.

## Core Primitives

- A `workflow definition` is a reusable graph of workers, nodes, edges, and artifact bindings.
- A `workflow run` is one execution of that definition.
- A `worker` is a named runnable agent configuration.
- A `node` is one unit of work.
- An `edge` is an explicit handoff path to the next node.
- A `run attempt` is one execution of one node.
- A `terminal session` is the real PTY-backed execution surface for an interactive attempt.
- A `completion signal` tells Devys when an attempt is done.
- An `operator action` is an explicit intervention such as stop, retry, or choose-next-edge.
- An `artifact binding` links the workflow to real files such as plans, prompts, or outputs.

The runtime primitives should not encode business semantics like `executor`, `reviewer`, or `self-review` as core types.
Those belong in shipped templates built on top of the primitives.

## Canvas-First Definition Model

Canvas is the builder primitive users expect for workflow definition.

The builder should let the user:

- place nodes on a canvas
- connect nodes with explicit edges
- attach workers to runnable nodes
- configure prompts and artifact bindings
- label or condition edges where needed

Canvas must not own workflow truth.
Reducer-owned workflow models remain the source of truth, and Canvas renders and edits that state.

That means:

- node position and connector layout are builder metadata
- runtime semantics do not depend on node geometry
- Canvas must round-trip cleanly with the canonical reducer-owned definition model

## Plan File Contract

The plan file is a user-owned markdown file, not a Devys-only document type.

V1 constraints:

- the file may live anywhere and may have any name
- the workflow stores the resolved path, not a hardcoded repo convention
- phase boundaries are explicit markdown headings
- work items are explicit markdown task list items or bullets inside a phase
- unchecked items represent open tickets
- checked items represent completed tickets

Recommended phase shape:

```md
# Refactor Plan

## Phase 1
- [ ] ticket one
- [ ] ticket two

### Follow-Ups
- [ ] added by the workflow

## Phase 2
- [ ] next batch
```

V1 parser rules:

- `##` headings define ordered phases
- if no phase headings exist, the whole file is treated as one phase
- Devys may append follow-up tickets only inside explicit workflow-owned sections
- Devys must not rewrite the whole file or silently invent a new markdown format

The plan file is important, but it is not the workflow graph.
It is an artifact the workflow can read and update.

## Definition Shape

The workflow definition should stay file-backed and explicit.

Suggested shape:

```json
{
  "id": "delivery-loop",
  "name": "Delivery Loop",
  "workers": {
    "implementer": {
      "provider": "claude-code",
      "executionMode": "interactive",
      "promptFile": "prompts/implement.md"
    },
    "reviewer": {
      "provider": "codex",
      "executionMode": "interactive",
      "promptFile": "prompts/review.md"
    }
  },
  "nodes": [
    {
      "id": "implement",
      "kind": "agent",
      "worker": "implementer"
    },
    {
      "id": "review",
      "kind": "agent",
      "worker": "reviewer"
    }
  ],
  "edges": [
    {
      "from": "implement",
      "to": "review"
    },
    {
      "from": "review",
      "to": "implement",
      "when": "rework-needed"
    }
  ],
  "artifacts": {
    "plan": ".docs/plan/refactor.md"
  }
}
```

The built-in delivery loop can ship as a default template, but the runtime must not require those exact node names or worker roles.

## Files On Disk

Committed definitions should live in the repository:

```text
.devys/workflows/
  delivery-loop/
    workflow.json
    prompts/
      implement.md
      review.md
```

Local run state should stay outside Git, preferably in application support keyed by worktree identity:

```text
~/Library/Application Support/Devys/workflows/
  <worktree-key>/
    runs/
      <run-id>/
        state.json
        events.jsonl
        artifacts/
        attempts/
        terminals/
```

Prompt files are real files on disk and remain directly editable.

## Execution Model

V1 execution should be a small explicit state machine around node attempts.

The minimal flow is:

1. select the next node
2. launch that node in a real terminal if it is interactive
3. while the node is running, the operator may focus the terminal and type
4. when the attempt completes, record the completion signal
5. traverse the next edge if there is one clear path
6. if the next path is ambiguous, pause for operator choice

### Completion And Handoff

For terminal-backed nodes, the default completion signal is simple:

- the process exited

Devys must not rely on vague heuristics like "the model stopped acting."

Handoff rules:

- if exactly one edge is valid, Devys may auto-traverse it
- if multiple edges are valid, Devys must pause and ask the operator to choose
- if no edges are valid, the run pauses or completes explicitly

Structured handoff artifacts may be added later, but they are not required to define the first slice.

### Interactive Mode

Interactive mode is mandatory for v1.

Rules:

- launch the real CLI in a PTY-backed terminal
- keep the terminal tab as the execution truth
- let the operator click into the terminal and type
- mirror lifecycle state and artifacts into the workflow run surface
- allow the user to focus the underlying terminal tab instantly

### Headless Mode

Headless execution can exist later on the same node/run model, but it is not the first slice.

We should not delay the real interactive path in order to design a more generic headless framework.

## Product Surfaces

Devys should be tab-first for workflows.

V1 surfaces:

- Agents sidebar:
  active runs, current node, attention state, quick actions
- workflow definition tab:
  Canvas-backed builder for workers, nodes, edges, and artifact bindings
- workflow run tab:
  current node, run history, artifacts, next-edge state, controls
- terminal tab:
  the real interactive execution surface for the active attempt

Entry points:

- Agents sidebar
- command palette
- titlebar action

V1 should not be modal-first.
Workflows should live naturally in the same split/tab environment as files, diffs, and terminals.

## Architecture Boundaries

This feature must follow the repo’s accepted architecture:

- `Packages/AppFeatures`
  owns workflow definitions, run state, nodes, edges, attempts, completion policy, sidebar summaries, tab identity, and presentation state
- `Apps/mac-client`
  owns host execution, PTY and terminal attachment, file-system side effects, and engine-backed workflow views
- `Packages/UI`
  owns shared workflow chrome and reusable stateless components
- `Packages/Canvas`
  should be promoted or replaced intentionally as the active workflow builder surface, but it must never own workflow truth or runtime policy

Important implementation rule:

- do not route workflow execution through `AgentSessionRuntime` chat behavior

Workflow execution may reuse launchers, terminals, and low-level host infrastructure, but it should remain its own reducer-owned product domain.

## V1 Non-Goals

- hidden fixed executor/reviewer semantics in the runtime type system
- persisted steering-note state or a steering panel
- fake terminal surrogates in place of the real terminal tab
- agent chat as part of workflow execution
- multi-repo workflows
- automatic PR creation
- deployment orchestration
- parallel fan-out and fan-in in the first slice

## Success Criteria

This vision is on track when Devys can do all of the following without hidden magic:

- define workflows on a Canvas-backed builder
- bind a real markdown plan file as an artifact
- run agent nodes in real terminal tabs
- let the operator steer by typing into those terminals
- use terminal exit as the default completion signal for terminal-backed attempts
- move from node to node through explicit edges
- pause for operator choice when the next edge is ambiguous
- append follow-up tickets back into the plan file when the workflow definition requests it
- expose workflow state in reducer-owned tabs and sidebar surfaces

If the product can do that well, then richer edge conditions, quality-gate nodes, and later headless execution can land without rewriting the core model.
