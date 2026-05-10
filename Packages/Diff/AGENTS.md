# Diff Package Guide

`Packages/Diff` is the diff parsing and rendering capability package.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/README.md`

## Role

This package owns:

- parsed diff value models
- git patch parsing
- diff source snapshot mapping
- Metal-backed unified and split diff rendering
- SwiftUI-facing diff viewer composition primitives

This package does not own:

- repository selection
- git command policy
- status source selection
- app tab, window, or sidebar policy
- workflow coordination

## Working Rules

- Keep app-domain policy outside this package.
- Keep the public API narrow. Public symbols should exist only when another module needs to compose or feed the diff viewer.
- Do not depend on archived material under `Packages/_archive`.
- Prefer explicit dependencies on `Text`, `Syntax`, `Rendering`, and `UI`; do not introduce broad facade packages.
