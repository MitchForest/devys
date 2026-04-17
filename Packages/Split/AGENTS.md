# Split Package Guide

`Packages/Split` is the split-pane rendering and gesture boundary.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/architecture.md`
- `/Users/mitchwhite/Code/devys/.docs/plan/implementation-plan.md`

## Role

This package owns:

- split view rendering mechanics
- pane/tab interaction mechanics and gesture capture
- public controller and delegate types used by host layers
- geometry queries and drag/drop mechanics

This package does not own:

- canonical pane/tab/layout truth
- workspace restore or persistence policy
- app-domain shell coordination

Reducer-owned shell state in `Packages/AppFeatures` is the canonical source of truth. `Packages/Split` renders and reports gestures against that state.

## Working Rules

- Do not reintroduce controller-owned topology as app-domain truth.
- Ephemeral rendering state is fine; long-lived visible shell authority is not.
- If a change affects reducer-visible layout policy, it likely belongs in `Packages/AppFeatures` first and `Packages/Split` second.
- Shared visual styling should come from `Packages/UI`.
