# Docs Guide

This file applies to everything under `.docs/`.

Keep `CLAUDE.md` as a sibling symlink to `AGENTS.md` in any `.docs` directory that has guide files. Edit `AGENTS.md`, not `CLAUDE.md`.

## Directory Ownership

- `reference/`
  - stable canonical reference material only
- `active/`
  - active work plans only
- `future/`
  - inactive design briefs and future ideas only
- `research/`
  - investigation notes only

## Working Rules

- Do not create ADR files in this repo.
- Put durable doctrine directly into the relevant `reference/` doc.
- Put active work in `active/`, not in `future/` and not in a generic catch-all plan.
- When a future brief becomes active, move it into `active/`.
- When a plan closes, delete it or promote its durable outcome into `reference/`.
- Do not leave phase-by-phase history logs inside `reference/`; rewrite those docs so they describe the current state.
- Do not let `research/` or `future/` silently become canonical. Rewrite them first if they need to become reference.
- Prefer deleting stale docs over preserving multiple conflicting versions.
