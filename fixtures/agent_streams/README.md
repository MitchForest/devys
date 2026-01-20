# Agent Stream Capture

This directory stores raw JSONL/NDJSON streams captured from Codex and Claude.
Use the prompts in `fixtures/agent_streams/prompts/` and write outputs into
`fixtures/agent_streams/raw/`.

## Where to run

Run all commands from the repo root:

cd /Users/mitchwhite/Code/devys

## Reset fixture workspace between runs

scripts/reset_fixture_workspace.sh

## Codex capture (JSONL)

Run each task separately and reset between runs:

codex exec --json --full-auto -C /Users/mitchwhite/Code/devys - < fixtures/agent_streams/prompts/task-01-read.txt > fixtures/agent_streams/raw/codex/task-01-read.jsonl
scripts/reset_fixture_workspace.sh

codex exec --json --full-auto -C /Users/mitchwhite/Code/devys - < fixtures/agent_streams/prompts/task-02-edit.txt > fixtures/agent_streams/raw/codex/task-02-edit.jsonl
scripts/reset_fixture_workspace.sh

codex exec --json --full-auto -C /Users/mitchwhite/Code/devys - < fixtures/agent_streams/prompts/task-03-create-rename.txt > fixtures/agent_streams/raw/codex/task-03-create-rename.jsonl
scripts/reset_fixture_workspace.sh

codex exec --json --full-auto -C /Users/mitchwhite/Code/devys - < fixtures/agent_streams/prompts/task-04-error.txt > fixtures/agent_streams/raw/codex/task-04-error.jsonl
scripts/reset_fixture_workspace.sh

## Claude capture (NDJSON)

Run each task separately and reset between runs:

claude --print --output-format stream-json --verbose --permission-mode acceptEdits --no-session-persistence "$(cat fixtures/agent_streams/prompts/task-01-read.txt)" > fixtures/agent_streams/raw/claude/task-01-read.ndjson
scripts/reset_fixture_workspace.sh

claude --print --output-format stream-json --verbose --permission-mode acceptEdits --no-session-persistence "$(cat fixtures/agent_streams/prompts/task-02-edit.txt)" > fixtures/agent_streams/raw/claude/task-02-edit.ndjson
scripts/reset_fixture_workspace.sh

claude --print --output-format stream-json --verbose --permission-mode acceptEdits --no-session-persistence "$(cat fixtures/agent_streams/prompts/task-03-create-rename.txt)" > fixtures/agent_streams/raw/claude/task-03-create-rename.ndjson
scripts/reset_fixture_workspace.sh

claude --print --output-format stream-json --verbose --permission-mode acceptEdits --no-session-persistence "$(cat fixtures/agent_streams/prompts/task-04-error.txt)" > fixtures/agent_streams/raw/claude/task-04-error.ndjson
scripts/reset_fixture_workspace.sh

## Notes

- The fixture workspace is tracked, so diffs show up in git.
- If you want approval events, rerun one task without --full-auto (Codex) or
  with --permission-mode default (Claude) and capture that stream separately.

## Normalize to internal JSONL

Use the `agent` CLI to translate raw vendor streams into internal events:

cargo run -p agent --bin normalize -- --vendor codex --input fixtures/agent_streams/raw/codex/task-02-edit.jsonl --output fixtures/agent_streams/normalized/codex/task-02-edit.jsonl
cargo run -p agent --bin normalize -- --vendor claude --input fixtures/agent_streams/raw/claude/task-02-edit.ndjson --output fixtures/agent_streams/normalized/claude/task-02-edit.ndjson
