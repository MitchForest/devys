# Rendering Package Guide

`Packages/Rendering` is the low-level text rendering support package.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/architecture.md`

## Role

This package owns:

- glyph atlas and text rendering pipelines
- Metal buffer and shader support
- low-level layout metrics used by editor and diff rendering
- scrolling/render packet helpers

This package does not own:

- app behavior
- git/editor workflow policy
- feature-level styling decisions

## Working Rules

- Keep APIs narrow and engine-focused.
- Avoid feature-specific abstractions leaking into this package.
- This package is infrastructure for higher-level rendering surfaces, not a UI ownership layer.
