# ADR 0003: UI Rulebook

- Status: Accepted
- Date: 2026-04-14

## Context

The app currently carries visual inconsistency across colors, spacing, borders, typography, and component shape. That drift is a direct result of feature-local styling decisions.

## Decision

`Packages/UI` is the single design-system source of truth for Devys.

## Rules

- Feature modules must not hard-code colors, spacing, radii, borders, shadows, or typography tokens.
- Repeated visual patterns must become shared components before they are copied across more features.
- Shared UI primitives are the default path for toolbars, sidebars, sheets, forms, badges, rows, panels, and status surfaces.
- Feature code may compose shared primitives, but it may not invent a parallel design system.
- UI review must reject new ad hoc visual primitives in migrated areas.

## Required Shared Surfaces

- typography tokens
- color tokens
- spacing scale
- border and radius tokens
- icon sizing and status treatments
- shared toolbar controls
- shared sidebar structures
- shared list rows
- shared form rows
- shared empty states
- shared modal scaffolds

## Consequences

- UI normalization is part of the architecture migration, not a follow-up cleanup.
- Any missing shared primitive needed by a feature must be added to `Packages/UI` rather than implemented locally.
