# Git Package Guide

`Packages/Git` provides git capability code and git-adjacent UI, not app-domain ownership.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/architecture.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/ui-ux.md`

## Role

This package owns:

- `git` and `gh` client wrappers
- git metadata parsing and refresh logic
- worktree helpers and watchers
- diff parsing and rendering helpers
- git-focused SwiftUI surfaces such as sidebars, diffs, commit flows, and PR views

This package does not own:

- global app workflow policy
- repository/workspace shell ownership
- singleton registry authority

## Working Rules

- `GitStore` instances are explicit host-owned objects. Do not reintroduce global registries or singleton access patterns.
- Keep git logic focused on git operations, metadata, and rendering support. App-level coordination belongs above this package.
- Shared styling should come from `Packages/UI`; do not invent package-local design primitives here.
- Watchers and refresh helpers may remain as low-level capabilities, but UI-visible policy should not migrate into them.
