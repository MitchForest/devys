# ADR 0005: No Shims, No Mirrors

- Status: Accepted
- Date: 2026-04-14

## Context

The easiest way to stage a migration is to wrap legacy stores and keep both the old and new ownership models alive. That is also the fastest way to lock in long-term ambiguity.

## Decision

Devys will not preserve legacy architecture through permanent shims, mirror state, or compatibility layers that remain after a slice is migrated.

## Rules

- A migrated slice gets one source of truth immediately.
- Reducers must not mirror long-lived mutable state from a legacy runtime owner.
- Legacy stores and registries may be used only until their replacement reducer is ready to take ownership.
- New compatibility layers must have a deletion path before they are introduced.
- Review must reject abstractions whose only purpose is preserving the old architecture.

## Consequences

- Migration work may be larger per slice, but the result stays simpler.
- When a reducer replaces a legacy owner, the legacy owner becomes deletion work in the same migration stream, not future cleanup.
