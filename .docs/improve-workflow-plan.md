# Workflow UX Overhaul — Comprehensive Plan

Status: phases 1–6 shipped (with deferred items noted)
Owner: workflows
Created: 2026-04-17
Last updated: 2026-04-17

## Shipped vs. Deferred

**Shipped this pass:**

- Phase 1: unified workflow tab with Design / Run mode toggle, top toolbar replaces Summary Card, canvas persistent in both modes, right inspector swaps content by mode. Both old `TabContent.workflowDefinition` and `.workflowRun` now render the same `WorkflowTabView`.
- Phase 2: workflow-aware terminal tab titles and icons via `WorkflowTerminalBinding` derived from run attempts, auto-split on Run (workflow left 60 / terminal right 40), new terminals auto-open in the reserved pane as the workflow launches each node.
- Phase 3: compact bottom Run Strip with NOW / NEXT / PLAN / LOG cells replaces the 6-panel scroll; NEXT cell surfaces edge-choice buttons prominently when awaiting operator; Run Inspector in the right rail shows context-sensitive Run Overview / Node Detail / Edge Detail.
- Phase 4: floating `WorkflowStatusCapsule` overlay at top of the workspace — shows when a run is active and the workflow tab is not focused; click focuses the workflow tab; warning tint on awaiting-operator.
- Phase 5: `TextEditorField` primitive in `Packages/UI` replaces four inlined `padding + card bg + border overlay + clip` compositions in workflow views. Worker card gets progressive disclosure (collapsed = name + kind; expandable; Advanced sub-disclosure for model / reasoning / extra args; dangerous permissions isolated in a warning-tinted panel with explainer).
- Phase 6: plan file validation indicator on the toolbar chip (green checkmark / red error / neutral for relative paths).

**Deferred to follow-up passes (not shipped):**

- Canvas node overlays (status halos, checkmarks, traversed edges, hover tail tooltip) — requires Canvas package API for per-node decorations; architectural call.
- Terminal tab context menu "Reveal in Workflow" — requires Split-package tab-bar context menu hook.
- Close-bound-terminal confirmation and interrupt forwarding — requires host/process coordination work.
- `workflow.runLayout` setting (`.splitBeside | .separateTab | .ask`) — default `.splitBeside` is hardcoded.
- New Workflow template gallery (Blank / From Template / Duplicate sheet).
- Canvas undo / redo stack.
- Graceful interrupt escalation (SIGINT → SIGTERM → SIGKILL).
- Prompt variable validation pre-Run.
- Unifying the `TabContent` enum — both old cases still exist and route to the same view; the enum cleanup is safe to land next release.
- Remaining design-system extractions (`StatusChip`, `InspectorSection`, `EmptyPanelState`, `SplitTabHeader`, `Badge`).

The vision below is unchanged; the deferred items remain the target for subsequent work.

---

## North Star

Running a workflow feels like **mission control + live ops**. The workflow tab is the map and command surface; the terminals are the actual work, visible side-by-side and obviously tied to the map. The canvas is never hidden during a run — it is the spine of the feature.

Hitting **Run** opens a split where the workflow tab is on one side and agent terminals stream on the other. The canvas shows which node is live, which are done, what is next. Click a node, jump to its terminal. Click a terminal, see its node highlighted. The user always knows: *what step am I on, what is running, what do I need to decide next*.

The three outcomes to hit, in order of importance:

1. **Never feel lost.** At any moment, three surfaces tell the same story: canvas, run strip, status capsule.
2. **Design and run are one place.** Canvas is persistent across both modes. Switching is a mode toggle, not a tab hop.
3. **Terminals are visibly children of the workflow.** They are labeled, bound, navigable, and die gracefully with their parent run.

---

## Information Architecture

### Unify definition + run into one `workflow` tab

- Replace `TabContent.workflowDefinition(…)` and `.workflowRun(…)` with a single `TabContent.workflow(workspaceID, workflowID)`.
- New `WorkflowTabFeature` reducer owns `displayMode: { design, run }` plus sub-states for each mode.
- Canvas is persistent across modes. Only the overlay layer and right inspector change.
- Legacy tab cases stay one release as read-only shims that auto-migrate on open.

### Canvas as spine

- **Design mode**: canvas full-bleed minus top toolbar and right inspector. The current Summary Card collapses into the toolbar.
- **Run mode**: same canvas with live overlays — status halos, traversed edges, decision prompts attached to nodes. Right inspector shows Run Detail for the selection.

### Terminals as first-class workflow children

- New `WorkflowBinding { runID, nodeID, attemptID }` attached to terminal state.
- Terminal tab title: `<Node> · <Workflow>`; pill tinted with the workflow accent.
- Terminal tab icon reflects node state (spinner / check / error).
- Context menu: "Reveal in Workflow".
- Closing a bound, still-running terminal asks confirmation and forwards an interrupt to the workflow run.

### Auto-split on Run

- On Run, focus-or-open the workflow tab, split 60/40 with the entry node's terminal on the right.
- Setting `workflow.runLayout` = `.splitBeside | .separateTab | .ask` (default `.splitBeside`). Per-workspace persistence.

---

## The Run Experience

### Canvas overlays

| State | Visual |
|---|---|
| Current node | Accent halo + soft pulse, bold border |
| Completed | Checkmark badge, node surface muted |
| Failed | Error tint border, error badge |
| Awaiting operator | Prompt card attached to the node with outgoing-edge buttons ("Rework" / "Complete" / "Next") |
| Traversed edges | Drawn in accent; untraversed stay neutral |
| Live tail | Hovering a running node pops a tooltip with last ~8 terminal lines |

Edge-choice-on-canvas is the single biggest clarity win. The decision happens where the decision visually belongs. The old "Choose Next" panel is retired.

### Bottom Run Strip (collapsible)

Four compact cells, 120pt tall, below the canvas:

1. **NOW** — current node title, status chip, elapsed time, "Open Terminal" button
2. **NEXT** — single outgoing edge label, or stacked edge buttons when awaiting operator
3. **PLAN** — active phase name, `n of m tickets` progress bar, click to expand tickets
4. **LOG** — last event line with count, click to expand full log

Expand-in-place on demand. Replaces the 6-panel vertical scroll.

### Floating Status Capsule

When a workflow is running and the workflow tab is not focused, the capsule shows:

> `🟢 Review Loop · Implement · 00:42`

Clicking focuses the workflow tab. Warning-tinted when awaiting operator.

### Right inspector in Run mode

Context-sensitive:

- Nothing selected → **Run Overview** (attempts list, branch, started-at, error banner)
- Node selected → **Node Detail** (prompt used, worker, attempts for this node, actions: Re-run, Skip, Open Terminal, Open Prompt)
- Edge selected → **Edge Detail** (label, traversal count this run)

Attempts history and run log live in inspector drawers or strip expansions, not as hero panels.

### Awaiting-operator state — the no-ambiguity rule

When `status == awaitingOperator`:

- Canvas decision prompt attached to current node with outgoing edge buttons
- Run Strip NEXT cell shows the same buttons, larger
- Status capsule turns warning-tinted: `⚠︎ Choose next step`
- Terminal pane footer: "This node finished — pick next in the workflow tab"

Four surfaces, one message. User cannot miss it.

---

## The Design Experience

### Top toolbar (replaces Summary Card)

- Workflow name, inline-editable
- Plan file path with validation dot (green / red), click to open
- Mode toggle: Design | Run
- Secondary menu: Open Plan, Duplicate, Delete
- Primary Run button, always rightmost, high emphasis

### Right inspector (Design)

Four sections with progressive disclosure:

- **Workflow Details** — name, plan file (always visible)
- **Workers** — one card per worker, collapsed to name + kind by default. Expand to edit. "Advanced" sub-disclosure hides model / reasoning / extra args / dangerous toggle.
- **Selected Node / Edge Editor** — replaces Workers when something is selected on canvas (mutually exclusive)

**Dangerous permissions toggle** becomes a warning-tinted section with explainer, separated from harmless fields.

### New Workflow flow

Replaces the silent "create Delivery Loop":

- Lightweight sheet (overlay surface) with three options:
  - **Blank** — start + finish only
  - **From Template** — gallery of 4–6 built-in templates
  - **Duplicate** — pick an existing workflow in this workspace
- Default selected: From Template. Escape / Cancel supported.

---

## Cross-cutting Design System Work

All extractions live in `Packages/UI` and are reusable beyond workflows.

1. **`TextEditorField`** — replaces the 4× inlined `padding + card bg + border overlay + clip` composition used in prompt editors, follow-up text, and plan editors. Single component, single source of styling.
2. **`StatusChip`** — generalize `WorkflowRunStatusChip` into UI; reuse for terminal tab icons, status capsule, tab pills.
3. **`InspectorSection`** — disclosure wrapper with caption + content + optional "Advanced" sub-disclosure.
4. **`EmptyPanelState`** — standardized muted-text + icon + optional action, used anywhere a conditional panel would simply vanish.
5. **`SplitTabHeader`** — top toolbar pattern (title + meta + actions) shared across workflow, editor, diff tabs.
6. **`Badge`** — worker IDs, branch names, attempt counts. Monospace, micro font, border-less, optional copy-on-click.

Rule of thumb: no feature-local surface composition. If a feature needs border + card + radius, it goes through a UI primitive.

---

## Behavior & Policy Changes

1. **Canvas undo stack** — TCA actions for canvas mutations accumulate in a bounded ring (100 entries). ⌘Z / ⌘⇧Z bound in design mode only.
2. **Plan file live validation** — on blur and on load, attempt to resolve; show red dot + tooltip with reason if missing or invalid. Do not block Run; warn via dialog.
3. **Run snapshot** — on Run, snapshot the definition into an immutable `WorkflowDefinitionSnapshot`. Design edits mid-run do not mutate the running workflow.
4. **Interrupt handling** — "Stop" sends SIGINT, waits 3s, escalates to SIGTERM, then SIGKILL. Current "just kill" is abrupt.
5. **Prompt variable validation** — flag unbound variables in the inspector pre-Run, not at runtime.

---

## Technical Risks & Unknowns

1. **Live terminal tail for canvas hover** — need read-only access to last-N lines of a terminal buffer without owning it. Likely an `AsyncStream<TerminalFrame>` from `GhosttyTerminal` the workflow subscribes to, buffering only the trailing N. Capability check in the terminal package.
2. **Canvas overlay performance** — on a 30-node workflow, pulsing halos every tick could thrash. Use `TimelineView` at ~4Hz and animate only moving nodes.
3. **Split auto-creation semantics** — if the user has a custom pane layout, forcibly splitting is hostile. Respect `runLayout = .ask` on first run; persist their choice.
4. **Tab binding lifecycle** — if a run is deleted, bound terminals unbind (not close) and lose the workflow prefix.
5. **Migration of existing tabs** — old `.workflowDefinition` / `.workflowRun` tabs open the new unified tab; remove old cases next release.

---

## Phased Implementation

Each phase is independently mergeable and ships visible value.

### Phase 1 — Unified tab + canvas-centric design layout

**Goal:** one workflow tab with a mode toggle, canvas full-bleed in design mode, inspector on the right.

**Changes:**
- Add `TabContent.workflow(workspaceID, workflowID)` case. Keep old cases as migration shims.
- New `WorkflowTabFeature` reducer with `displayMode: { design, run }`. Parent the existing definition/run sub-reducers underneath.
- New `WorkflowTabView` that renders the toolbar, canvas, and mode-specific right inspector.
- Design mode: collapse Summary Card content into the toolbar; canvas fills available space; inspector 360pt on the right.
- Run mode: temporarily renders the existing run panels (stacked) until Phase 3 rebuilds them. Canvas still visible above.
- Sidebar click on a workflow always opens the new unified tab.
- Running workflow opens the unified tab in run mode (instead of the old `.workflowRun` tab).

**Acceptance:**
- No visual regression in design or run compared to today, aside from the new top toolbar and persistent canvas in run mode.
- Old `.workflowDefinition` and `.workflowRun` tab cases open the new tab on click.
- Build green, reducer tests for mode transition pass.

### Phase 2 — Terminal binding + auto-split on Run

**Goal:** terminals are visibly bound to workflow runs, Run opens a split layout.

**Changes:**
- `WorkflowBinding { runID, nodeID, attemptID }` added to terminal tab state (or parallel map keyed by terminal ID).
- Terminal tab rendering honors binding: title prefix, icon by node status, context menu "Reveal in Workflow".
- Workflow execution client attaches binding when spawning terminals.
- Run action auto-splits: if current pane is unsplit, split horizontally 60/40; open entry terminal in right pane.
- Setting `workflow.runLayout` with `.splitBeside` default.
- "Reveal in Workflow" and "Open Terminal" cross-navigation actions wired end-to-end.
- Closing a bound terminal while running prompts confirmation and forwards interrupt.
- Deleting a run unbinds (not closes) its terminals.

**Acceptance:**
- Clicking Run opens workflow + entry terminal side-by-side by default.
- Terminal tab pill shows node + workflow name; icon reflects status.
- Right-click → Reveal in Workflow jumps and highlights the node on canvas.

### Phase 3 — Canvas overlays + Run Strip

**Goal:** the canvas feels alive during a run; the 6-panel scroll is replaced by a compact run strip.

**Changes:**
- Overlay layer on `WorkflowCanvasView` for status halos, checkmarks, traversed edges.
- Node hover tooltip with last ~8 terminal lines (subscribes to terminal tail stream).
- Edge-choice-on-canvas prompt card when `awaitingOperator`; old "Choose Next" panel deleted.
- New bottom Run Strip (NOW / NEXT / PLAN / LOG) replacing the vertical panel stack.
- Each strip cell is expandable in-place.
- Right inspector Run Detail views (Overview / Node / Edge).
- `TimelineView` cadence for pulse animations.

**Acceptance:**
- Canvas visually shows which node is running, completed, failed.
- Awaiting-operator decision is made on the canvas.
- Run Strip replaces the old stacked panels; attempts and log are accessible via expansion.

### Phase 4 — Ambient awareness

**Goal:** the user knows workflow state even when the workflow tab is not focused.

**Changes:**
- Floating Status Capsule (design system surface) wired to active runs.
- Capsule tint reflects status; warning tint on awaiting-operator.
- Click capsule → focus the workflow tab and expand Run Strip NEXT cell if awaiting.
- Subtle audio / visual cue on entering `awaitingOperator` (configurable, off by default).
- Status across capsule, canvas, strip, and inspector stays consistent.

**Acceptance:**
- Switching to another tab still surfaces workflow state via capsule.
- Awaiting-operator is unmissable from any tab.

### Phase 5 — Design system extractions

**Goal:** no feature-local surface composition; shared primitives everywhere.

**Changes:**
- Build `TextEditorField`, `StatusChip`, `InspectorSection`, `EmptyPanelState`, `SplitTabHeader`, `Badge` in `Packages/UI`.
- Sweep all workflow views to use them. Remove inlined `.padding + .background + .overlay` compositions.
- Worker card: progressive disclosure (collapsed = name + kind; expanded with optional Advanced).
- Dangerous permissions toggle: warning-tinted section with explainer.
- Inspector sections gain the disclosure wrapper.
- Empty states on every conditional panel.

**Acceptance:**
- Zero `.background(theme.card).overlay(...stroke).clipShape(...)` patterns in feature code.
- Worker cards default to compact, expand on demand.
- Dangerous toggle visually flagged.

### Phase 6 — Polish & templates

**Goal:** onboarding flow, undo, validation, interrupt handling.

**Changes:**
- New Workflow sheet with Blank / From Template / Duplicate.
- Template gallery: Delivery Loop, Code Review, Multi-Agent Pipeline, Single Agent Run, Parallel Research (content TBD per gallery review).
- Canvas undo / redo with bounded action ring.
- Plan file live validation dot + tooltip.
- Graceful interrupt: SIGINT → 3s → SIGTERM → SIGKILL.
- Prompt variable validation in worker/node inspector pre-Run.
- Empty-state pass across all conditional surfaces.

**Acceptance:**
- New Workflow sheet appears; templates spawn a valid definition.
- ⌘Z / ⌘⇧Z work on canvas.
- Invalid plan file surfaces inline, not only at Run.
- Unbound prompt variables visible pre-Run.

---

## Sequencing Notes

- Phase 1 → Phase 2 → Phase 3 is the critical path. Everything else builds on the unified tab, terminal binding, and canvas overlays.
- Phase 5 can run in parallel with Phase 3 once the primitives are defined, but land the primitives first.
- Phase 4 depends on Phase 3 (capsule needs run state feeds that Phase 3 solidifies).
- Phase 6 is closeout polish — safe to land last.

---

## Done Means

- A user creates a workflow, edits on a canvas, hits Run, and sees the workflow canvas on the left with the entry agent's terminal streaming on the right.
- As nodes complete, the canvas updates in place; the terminal pane shifts to the next active node.
- When a decision is needed, the canvas makes it obvious and the user clicks the edge on the canvas to proceed.
- At any point, even in another tab, the floating capsule reflects state and can be clicked to return.
- No feature-local surface composition remains in workflow code.
- The design-system primitives built here are used by other features (editor, diff, terminal) within one release.
