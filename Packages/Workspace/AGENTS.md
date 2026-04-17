# Workspace Package Guide

`Packages/Workspace` is a low-level repository, worktree, file-tree, and persistence package.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/architecture.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/legacy-inventory.md`

## Role

This package owns:

- low-level repository, worktree, and workspace models
- file-tree models and watch services
- persistence services for repositories, worktrees, layouts, and settings
- discovery and indexing helpers used by higher layers

This package does not own:

- app shell truth
- window or workflow coordination
- reducer-visible policy for navigation, selection, or presentation

## Current Landmarks

- `Sources/Core/Models/`
  - `Repository`, `Worktree`, `Workspace`, `PanelLayout`, `FileTreeModel`, `AppSettings`, `RepositorySettingsStore`
- `Sources/Core/Services/`
  - persistence services, discovery services, and file-watch infrastructure

## Working Rules

- Keep APIs focused and explicit. This package is infrastructure, not an app-domain coordinator.
- `PanelLayout` and related models are low-level support types, not the canonical source of pane/tab shell truth.
- Watchers, registries, and persistence helpers may exist here only as low-level capabilities behind clear boundaries.
- If a change starts expressing app behavior or user-facing policy, it likely belongs in `Packages/AppFeatures` instead.
- `RepositorySettingsStore` remains a migration-review hotspot; avoid expanding its authority casually.
