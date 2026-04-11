# Agent Adapter Installation

Devys launches upstream ACP adapters as local subprocesses. The app does not install them for you yet, so QA and local development require the adapter executables to already exist on disk.

## Expected executables

- Codex: `codex-acp`
- Claude: `claude-agent-acp`

## Resolution order

Devys resolves adapters in this order:

1. an explicit configured executable path
2. bundled app helpers under `Contents/Helpers` or `Contents/SharedSupport`
3. `PATH`
4. explicit fallback directories for macOS app launches:
`~/.local/bin`, `~/.cargo/bin`, `~/bin`, `/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/usr/local/bin`, `/usr/local/sbin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`

The fallback directories matter because GUI app launches on macOS often do not inherit the same shell `PATH` you see in Terminal.

## Install commands

Install the adapters with npm:

```bash
npm install -g @zed-industries/codex-acp
npm install -g @zed-industries/claude-agent-acp
```

If you use Homebrew Node, the binaries usually land in `/opt/homebrew/bin`. If you use another Node setup, make sure the global npm bin directory is one of the paths above or configure an explicit executable path.

## Underlying CLIs

- Codex ACP expects Codex CLI to be available for authentication and execution.
- Claude Agent ACP vendors its own Claude Code runtime by default, but you can override the executable with `CLAUDE_CODE_EXECUTABLE` if needed.

## Failure diagnostics

If Devys cannot launch an adapter, the app now distinguishes:

- binary not found
- process spawn failed
- initialize failed
- unsupported protocol version
- unsupported capability

The most common local setup failure is:

```text
No Codex ACP adapter was found. Expected `codex-acp` in a configured path, the app bundle helpers, or PATH.
```

or:

```text
No Claude ACP adapter was found. Expected `claude-agent-acp` in a configured path, the app bundle helpers, or PATH.
```

When that happens:

1. verify the executable exists with `command -v codex-acp` or `command -v claude-agent-acp`
2. if it does not, install the missing adapter
3. if it does, verify its directory is one of Devys's search roots
4. relaunch Devys after installation so the next session launch sees the binary
