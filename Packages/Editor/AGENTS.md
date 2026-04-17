# Editor Package Guide

`Packages/Editor` is the editor engine package.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/architecture.md`

## Role

This package owns:

- document models and editing operations
- editor rendering integration
- editor-specific configuration and input handling
- syntax/rendering integration with `Syntax`, `Text`, and `Rendering`

This package does not own:

- tab policy
- workspace or window coordination
- app-level session orchestration

## Current Structure

- `Sources/Editor/Models/Document/`
  - editor document types and search/editing support
- `Sources/Editor/Models/Layout/`
  - line buffering and display support
- `Sources/Editor/Views/Metal/`
  - Metal-backed editor host
- `Sources/Editor/Views/SwiftUI/`
  - SwiftUI-facing editor wrappers

## Working Rules

- Keep engine and document behavior here; keep app-domain policy outside.
- If a change is really about tab identity, dirty-close policy, or reducer-visible workflow, it belongs in higher layers.
- Prefer explicit dependencies on `Text`, `Syntax`, and `Rendering`; do not document or reintroduce old package names.
