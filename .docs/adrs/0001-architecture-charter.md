# ADR 0001: Architecture Charter

- Status: Accepted
- Date: 2026-04-14

## Context

The app currently mixes SwiftUI-owned state, runtime registries, observable stores, notification-driven commands, and service-locator style dependency access. That combination makes ownership ambiguous and the codebase harder to reason about as the feature surface grows.

The migration to TCA is not a library swap. It is a repo-wide architecture reset.

## Decision

Devys adopts the following architecture charter:

- TCA owns all app-domain state, feature logic, navigation state, workflow state, lifecycle policy, and side-effect orchestration.
- SwiftUI views render state and send actions. Views do not coordinate workflows or own business logic.
- App-domain side effects run through explicit dependency clients.
- Reducer state is the canonical source of truth for migrated domains.
- Packages expose the smallest usable public surface. Everything else remains `internal` or `private`.
- The design system is centralized and mandatory for all app UI.
- Strict Swift concurrency is the baseline for app-domain code.

## Non-Negotiable Rules

- One concern has one owner.
- One domain has one source of truth.
- No app-domain `NotificationCenter` command bus.
- No app-domain service locator pattern.
- No permanent migration shims.
- No mirrored ownership between reducers and legacy stores.
- No new singleton or registry introduced for app-domain behavior.
- No hard-coded design primitives in feature code.

## Consequences

- Legacy runtime owners, stores, managers, and registries that currently hold app behavior are migration targets, not permanent architecture.
- New feature work in migrated areas must follow reducer-first ownership.
- Any code that violates these rules is architecture debt and must be treated as such during review.
