# Syntax Package Guide

`Packages/Syntax` is the syntax and tree-sitter capability package.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/architecture.md`

## Role

This package owns:

- tree-sitter and syntax support targets
- grammar, theme, and highlight infrastructure
- low-level parsing and language-detection helpers
- supporting wrappers used by editor and diff rendering

This package does not own:

- app-domain coordination
- window, tab, or workflow policy
- feature-specific UI behavior

## Working Rules

- Keep syntax/runtime concerns here and app behavior outside.
- Vendor and parser targets are low-level implementation details; avoid layering app abstractions over them.
- If a change is about how the app presents syntax information, separate the app policy from the syntax capability itself.
