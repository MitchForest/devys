You don’t “know reality” perfectly from the docs alone — you define an internal schema that is:

1. **grounded in what the CLIs actually emit today (their streamed events)**
2. **robust to missing/extra fields**
3. **extensible** so new vendors/tools plug in without redesign
4. **verifiable** by capturing real transcripts and building from them

So the right approach is: **spec → adapters → golden logs → evolve**.

Here’s how to do it concretely.

---

## 1) What you can trust about “reality” today

### Codex CLI

Codex `exec --json` emits **typed JSONL events** (thread/turn/item lifecycle, errors) and says those items represent things like command execution, file changes, plan updates, etc. That gives you a stable *shape* to map from.

### Claude Code

Claude’s `--output-format stream-json` emits **NDJSON** and it supports `--input-format stream-json`, plus structured responses with `--json-schema`. That gives you streaming + structure, but you should expect format/version drift and vendor-specific item types.

**Key takeaway:** you can’t treat either as a single canonical schema. You need **adapters**.

---

## 2) Design the schema around *your product*, not their format

Your UI needs to render a small number of “things”:

* a **turn** started/ended
* a **plan** (and updates)
* **messages** (assistant/user/system)
* **tool calls** (including shell commands)
* **file edits** (or at least “files touched” + patch)
* **git operations** (stage/revert/commit)
* **artifacts** (images, tables, diffs, links)
* **errors**
* **prompts for approval** / policy blocks

So your internal schema should be a normalized event log of those concepts.

Think of it like an LSP: vendors adapt to *you*.

---

## 3) The internal event model (v1) — exact spec

### 3.1 Envelope (every event has this)

This is what makes your log durable and mergeable across agents and machines:

```json
{
  "schema_version": 1,
  "event_id": "ulid",
  "timestamp_ms": 1737240000123,
  "workspace_id": "ws_ulid",
  "session_id": "sess_ulid",
  "agent_id": "agent_ulid",
  "turn_id": "turn_ulid",
  "source": {
    "vendor": "codex|claude|internal",
    "vendor_event_type": "string",
    "vendor_raw": { }
  },
  "event": { }
}
```

Rules:

* `vendor_raw` is **optional** but recommended for debuggability.
* `vendor_event_type` records the original type for forensics.
* `turn_id` allows concurrent agents to emit interleaved events safely.
* Canonical JSON schema lives at `agent/schema/event-log.v1.schema.json`; it currently matches implemented event types and expands as new types ship.

### 3.2 Event types (the exact set you commit to for v1)

#### Turn lifecycle

* `turn.started`
* `turn.completed`
* `turn.failed`
* `turn.cancelled`

Payload:

```json
{
  "type": "turn.started",
  "input": {
    "kind": "user_request|handoff|system",
    "text": "string",
    "attachments": [{"type":"path|diff|log|image", "ref":"..."}]
  }
}
```

#### Assistant messages

* `message.emitted`

Payload:

```json
{
  "type": "message.emitted",
  "role": "assistant|user|system",
  "format": "markdown|text",
  "text": "..."
}
```

#### Plan (first-class UI object)

* `plan.created`
* `plan.updated`

Payload:

```json
{
  "type": "plan.updated",
  "plan": {
    "plan_id": "ulid",
    "steps": [
      { "id":"s1", "text":"Run tests", "status":"pending|running|done|skipped|failed" }
    ]
  }
}
```

#### Tool calls (includes command execution)

* `tool.started`
* `tool.progress`
* `tool.completed`
* `tool.failed`

Payload:

```json
{
  "type": "tool.started",
  "tool": {
    "tool_id": "ulid",
    "name": "shell|git|mcp|http|fs|vendor_tool",
    "input": { }
  }
}
```

For shell specifically:

```json
{
  "type": "tool.started",
  "tool": {
    "tool_id": "ulid",
    "name": "shell",
    "input": {
      "cmd": "pnpm test",
      "cwd": "/repo",
      "env_delta": {"NODE_ENV":"test"},
      "pty": false
    }
  }
}
```

And you stream output as:

```json
{
  "type": "tool.progress",
  "tool_id": "ulid",
  "channel": "stdout|stderr",
  "text": "..."
}
```

And completion:

```json
{
  "type": "tool.completed",
  "tool_id": "ulid",
  "result": { "exit_code": 0, "duration_ms": 1234 }
}
```

#### File changes (must support review/stage/revert)

* `fs.change_detected` (lightweight: “files touched”)
* `fs.patch_proposed` (the important one)
* `fs.patch_applied`
* `fs.patch_reverted`

Payload (proposed patch):

```json
{
  "type": "fs.patch_proposed",
  "patch": {
    "patch_id": "ulid",
    "summary": "Fix auth redirect loop",
    "files": [
      {
        "path": "src/auth.ts",
        "change_type": "modify|add|delete|rename",
        "diff_unified": "string",
        "language": "ts"
      }
    ]
  }
}
```

Your UX depends on `diff_unified`. If a vendor doesn’t provide it, your adapter must synthesize it from the filesystem (see below).

#### Git events (UI-owned safety layer)

* `git.status`
* `git.stage`
* `git.unstage`
* `git.commit`
* `git.revert`
* `git.checkout`
* `git.merge`
* `git.conflict`

Payload example:

```json
{
  "type": "git.stage",
  "op_id": "ulid",
  "files": [{"path":"src/auth.ts","hunks":[1,2]}],
  "result": "ok|error",
  "error": null
}
```

#### Approvals / gates

* `approval.requested`
* `approval.resolved`

Payload:

```json
{
  "type": "approval.requested",
  "approval": {
    "approval_id": "ulid",
    "kind": "run_command|write_files|network_access|dangerous",
    "reason": "Needs to install deps",
    "details": { }
  }
}
```

This is essential because some vendors will “ask permission” in their own UX; you need to represent it explicitly in yours.

#### Artifacts (multi-modal outputs)

* `artifact.created`

Payload:

```json
{
  "type": "artifact.created",
  "artifact": {
    "artifact_id": "ulid",
    "kind": "diff|image|table|report|link",
    "title": "Test results",
    "content": { }
  }
}
```

---

## 4) How to map Claude/Codex to this schema (without guessing)

### 4.1 Adapters, not parsers

You build:

* `codex_adapter` that reads JSONL lines, emits internal events
* `claude_adapter` that reads NDJSON lines, emits internal events

Each adapter does:

* **best-effort mapping** for known vendor event types
* **pass-through** unknowns into `source.vendor_raw`
* **synthesis** for critical missing data (diffs, status)

### 4.2 “Reality check” via Golden Logs (this is the missing piece)

To avoid guessing, you create a small corpus of real sessions:

* Run 20–50 representative tasks with each tool:

  * “refactor file X”
  * “fix failing test”
  * “add feature w/ migrations”
  * “review diff and request changes”
* Capture raw streams:

  * Codex: `codex exec --json ... > codex_task.jsonl`
  * Claude: `claude -p --output-format stream-json ... > claude_task.ndjson`
* Store them as **golden fixtures** in your repo.
* Write adapter unit tests:

  * input: vendor stream fixture
  * output: internal events fixture
* Anytime vendor output changes, tests fail and you update mapping.

This is how you “know reality.”

---

## 5) Handling the biggest uncertainty: diffs

Even if Codex sometimes emits “file changed” without an explicit patch, you can still guarantee the UX.

**Rule:** your app always computes diffs itself as the final authority.

Implementation approach:

* Maintain a workspace snapshot per turn:

  * before turn: record `git status`, `git diff` baseline
  * after turn: compute `git diff` or filesystem diff
* Emit your own `fs.patch_proposed` based on real changes
* Treat vendor file events as hints, not ground truth

This also prevents “agent says it changed X” when it didn’t.

---

## 6) Versioning & extensibility (don’t paint yourself into a corner)

* Version the internal schema (`schema_version`)
* Keep schema files versioned (ex: `agent/schema/event-log.v1.schema.json`) and add a new file for breaking changes.
* Keep `source.vendor_raw` available for debugging and future remapping
* Make `event.event` an enum in Rust with `#[serde(tag="type")]`
* Never require a vendor-specific field to render your core UX

  * if missing → synthesize from OS (diff, git status, logs)

---

## 7) What you need from me / next deliverable

If you want, I can produce next:

* a **formal JSON Schema** for the internal event envelope + each event type
* Rust types (`enum Event { ... }`) + serde tags
* an adapter outline for Codex + Claude
* and a minimal list of “golden log” tasks to record in week 1

But the core answer is:
You define the schema from your UX needs, then you **prove it against reality** by capturing real streams and building adapters with golden tests.
