That tweet’s core idea is: **agents can generate more code than humans can read**, so the human’s job shifts “up a level” to **understanding intent + system impact** via **visual and structured representations** (ERDs, flowcharts, maps), not raw diffs. The LinkedIn version of the post explicitly describes a tool generating a **database diagram automatically** to visualize a proposed change in a Laravel app. ([LinkedIn][1])

## The insight to implement in Devys

Treat “visualizations” as **first-class review artifacts**, alongside diffs and logs.

Instead of “agent wrote code → human reads code,” make the loop:

1. agent changes code
2. Devys generates/updates *representations* (DB graph, dependency graph, flow map, etc.)
3. human reviews those representations + the diff
4. human approves/reverts/stages

## How you implement this (practical architecture)

### 1) Create a Visualization IR (intermediate representation)

You don’t want 10 one-off visualizers. Define one internal graph-ish model:

* **Nodes**: tables, files, modules, endpoints, jobs, queues, services
* **Edges**: “depends on”, “calls”, “writes to”, “migrates”, “publishes event”, etc.
* **Metadata**: source locations (file:line), ownership, “changed by agent X”, timestamps

This IR is what you diff, cache, and render.

### 2) Extract structure from the codebase (two ways)

You can generate the IR via:

**A) Deterministic extractors (preferred whenever possible)**

* Parse DB schema from migrations / schema files / ORM models (Laravel, Rails, Prisma, SQL, Supabase migrations, etc.)
* Parse route maps, module graphs, imports, package deps
* Tree-sitter + language tooling for syntax-level indexing

**B) Agent-assisted extraction (useful for messy systems)**

* Ask Claude/Codex to summarize flows or identify subsystems
* But: require citations to code locations (“this edge comes from file X line Y”)

This lets you cover both “hard truth” and “semantic mapping.”

### 3) Render using Mermaid first, then upgrade to tldraw / xyflow when you need interactivity

* **Mermaid** is perfect for “diagram as code” because it renders from a text definition and fits diffs/versioning well. ([mermaid.js.org][2])
* **tldraw** is an infinite-canvas whiteboard SDK for React—great for a “systems map” where humans can annotate, rearrange, and discuss. ([GitHub][3])
* **xyflow / React Flow** is ideal for node-based UIs with draggable nodes, inspectors, and custom edge types—great for dependency graphs, call graphs, workflows. ([GitHub][4])

**Implementation tactic:** embed these in a **WebView panel** inside Devys (a dedicated “Visual Review” pane). You don’t need to rewrite diagram rendering in Rust; just ship a local web bundle.

### 4) Make diagrams clickable and “round-trip”

To make this actually useful for review:

* Clicking a node opens the relevant file/definition in your file tree/editor
* Clicking an edge shows “evidence” (where it came from)
* You can ask an agent: “Explain this edge” or “What changed here?”

Then: **persist artifacts**:

* `devys/diagrams/db.mmd` (Mermaid text)
* `devys/diagrams/system.tldr.json` (tldraw doc)
* `devys/diagrams/flows.reactflow.json`

Now diagram changes are reviewable in Git like code.

### 5) Diff *representations*, not just code

This is the killer feature for agent-generated code:

When an agent submits changes, Devys auto-generates:

* “DB graph before vs after”
* “Route map before vs after”
* “Module dependency deltas”
* “New tables/endpoints/background jobs”

Then the human can review:

* “What *structurally* changed?” in 30 seconds
* and only then drill into diffs

That’s exactly what the tweet is gesturing at.

## What this would look like in your UI/UX (concretely)

Add a “Review Workspace” layout:

* Left: file tree + changed files
* Center: diff viewer
* Right: “Visual Review” tabs:

  * DB diagram
  * System map
  * Flow chart
  * Dependency graph

Plus a “Generate visuals” button (or automatic on agent completion).

## Why this fits Devys specifically

Because Devys is already positioned as:

* a place where agents execute
* humans supervise
* and output becomes *artifacts*

Visual artifacts are just a higher-level artifact type.

---

If you want next, I can propose a **v1 visualization set** that’s realistically buildable and high impact:

1. DB ERD (Laravel/Rails/Prisma/Supabase)
2. Changed-files dependency mini-graph (imports/calls)
3. “Request → handler → DB” flow map for a feature branch

## Current IR + Sample Artifact

The initial visualization IR lives in `agent/src/visualize.rs`, and a sample graph is stored at `fixtures/visuals/sample-graph.json` with the generated Mermaid at `fixtures/visuals/sample-graph.mmd`.

…and the exact extraction approach for Laravel migrations/models (since the tweet example was Laravel).

[1]: https://www.linkedin.com/posts/peterjthomson_claude-and-codex-can-generate-so-much-code-activity-7418959497013923840-WwsV?utm_source=chatgpt.com "Claude and Codex can generate so much code, so quickly ..."
[2]: https://mermaid.js.org/?utm_source=chatgpt.com "Mermaid | Diagramming and charting tool"
[3]: https://github.com/tldraw/tldraw?utm_source=chatgpt.com "tldraw/tldraw: very good whiteboard infinite canvas SDK"
[4]: https://github.com/xyflow/xyflow?utm_source=chatgpt.com "xyflow/xyflow: React Flow | Svelte Flow"
