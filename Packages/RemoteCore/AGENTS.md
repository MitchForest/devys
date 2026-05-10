# RemoteCore Package Guide

`Packages/RemoteCore` owns value models and naming helpers for remote repositories and worktrees.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/README.md`

## Role

This package owns:

- remote repository authority identities
- remote worktree value models
- remote session naming helpers

This package does not own:

- SSH transport execution
- app drawer, tab, or window policy
- repository selection workflows
- UI terminology such as rails, sidebars, or product chrome

## Working Rules

- Keep this package transport-neutral and UI-neutral.
- Public symbols must be remote capability value contracts with a cross-package consumer.
- Do not preserve legacy shell or product-chrome terminology in public API names.
