# Text Package Guide

`Packages/Text` owns text document, range, snapshot, and edit primitives.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/README.md`

## Role

This package owns:

- text document handles
- immutable document snapshots
- text positions, ranges, slices, and edit transactions

This package does not own:

- editor tabs
- file save/reveal policy
- syntax parsing
- renderer state
- app workflow state

## Working Rules

- Keep this package UI-free and app-domain-free.
- Public symbols must be core text model contracts used by editor, syntax, or tests.
- Do not add convenience APIs that hide mutation or side effects.
