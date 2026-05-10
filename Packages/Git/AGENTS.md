# Git Package Guide

`Packages/Git` is the git capability package.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/README.md`

## Role

This package owns:

- git status parsing and value models
- narrow git command execution
- file-level stage, unstage, and discard operations
- hunk and patch operations
- diff snapshot loading that composes with `Packages/Diff`

This package does not own:

- app sidebar, tab, or window policy
- confirmation UI
- commit composer UI
- design-system styling
- repository selection workflow

## Working Rules

- Do not depend on archived material under `Packages/_archive`.
- Do not depend on `Apps/mac-client`.
- Keep public API opt-in and minimal.
- Keep destructive UI policy outside this package. The app supplies file discard behavior such as moving files to Trash.
- Prefer explicit git command methods over broad facade APIs.
