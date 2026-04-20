# Devys Docs

Updated: 2026-04-19

## Purpose

This directory is split by document role.

If a document does not fit one role cleanly, rewrite it or delete it.

## Directory Roles

### `reference/`

Canonical, stable repo reference material.

This is where architecture rules, UI system rules, shipped product contracts, and other durable guidance belong.

Current canonical reference docs include:

- `reference/architecture.md`
- `reference/ui-ux.md`
- `reference/legacy-inventory.md`
- `reference/terminal-runtime.md`

### `active/`

Active work plans only.

Rules:

- `active/` may contain multiple active plans.
- A plan belongs here only while the work is active or queued next.
- When a future brief becomes active, move it here and turn it into the working plan.
- When a plan closes, delete it or promote its durable outcomes into `reference/`.

### `future/`

Inactive design briefs and future-looking product ideas.

Rules:

- These docs do not override `reference/`.
- These docs are not execution source of truth.
- If work actually starts, move the doc into `active/` instead of copying it into some generic catch-all plan.

### `research/`

Investigation notes, comparisons, reverse engineering, and other exploratory material.

Rules:

- Research is input, not doctrine.
- Research is not a plan.
- If research becomes stable guidance, rewrite it into `reference/`.

## Repo Rules

- Do not create ADR files. Put accepted doctrine directly into the relevant `reference/` doc.
- Do not leave closed plans in `active/`.
- Do not keep active work in `future/`.
- Do not leave plan history or phase diaries inside `reference/`.
- Keep cross-references current when docs move.
- Prefer one clear doc over multiple overlapping versions.

## Current State

Look in `active/` for active work.

If `active/` only contains `README.md`, no active plan is currently declared.
