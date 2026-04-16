# ADR 0004: Module Visibility Rulebook

- Status: Accepted
- Date: 2026-04-14

## Context

Wide public surfaces make refactors expensive and hide true ownership. The migration goal is a modular repo with minimal public boundaries and clear internal structure.

## Decision

Visibility is restrictive by default.

## Rules

- `public` is opt-in only.
- Package entry points that are consumed by another module may be `public`.
- Reducers, helper views, mappers, utilities, dependency helpers, and implementation details remain `internal` unless cross-module use is required.
- `private` is preferred for file-local implementation detail.
- New package APIs must justify why the symbol cannot remain `internal`.
- Cross-package feature composition should depend on focused interfaces, not broad convenience exports.

## Consequences

- The migration should shrink public API surfaces over time.
- Review must treat unnecessary `public` as a design bug, not a neutral choice.
