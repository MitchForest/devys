# Devys Docs

Updated: 2026-04-16

## Purpose

This directory is intentionally split into reference docs, plan docs, ADRs, and supporting context.

If a document does not fit one of those roles cleanly, it should be rewritten or deleted instead of allowed to drift.

## Canonical Reference Docs

- `adrs/`
  - immutable governance decisions
- `reference/architecture.md`
  - canonical architecture, ownership, boundary, and modularity reference
- `reference/ui-ux.md`
  - canonical UI and interaction reference
- `reference/legacy-inventory.md`
  - concrete legacy deletion and quarantine inventory that informs migration work

## Canonical Planning Doc

- `plan/implementation-plan.md`
  - the only active migration and execution plan
  - records what is done, what remains, and the ordered next work
  - the required starting point for migration work and phase-status questions

## Supporting Context

- `future/workflow-vision.md`
  - future product direction for reusable workflows
  - not a migration source of truth
- `research/comparison-matrix.md`
  - competitive and repo research input
  - not a build plan
- `repos/`
  - raw upstream repo snapshots and reference material used during research
  - not part of the canonical Devys doc set

## Rules

- Do not create phase-specific working-plan files when the active implementation plan can be updated instead.
- Do not put immutable rules into plan docs. Put them in ADRs or the reference docs.
- Do not leave outdated plans in place once their useful content has been folded forward.
- When a migration slice lands, update `plan/implementation-plan.md` in the same stream.
- If phase status, handoff notes, or next-work instructions appear to conflict elsewhere, `plan/implementation-plan.md` is the source of truth.
