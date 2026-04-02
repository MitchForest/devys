# mac-server

Local Devys server process that runs on a Mac (Mac mini or MacBook) and exposes the remote runtime API to Devys clients over Tailscale.

Current endpoints:

- `GET /health` returns server metadata JSON.
- `GET /capabilities` returns server runtime capability flags (`tmux`, `claude`, `codex`).
- `GET /stream` returns an `application/x-ndjson` chunked event stream.
- `POST /pairing/challenge` creates a short-lived pairing challenge and setup code.
- `POST /pairing/exchange` exchanges challenge + code for a paired-device token.
- `GET /pairings` lists known pairings.
- `POST /pairings/{id}/rotate` rotates pairing auth token.
- `POST /pairings/{id}/revoke` revokes a pairing.
- `GET /profiles` lists command profiles (`shell`, `cc`, `cx`, custom).
- `POST /profiles` saves a command profile.
- `POST /profiles/validate` validates a command profile payload.
- `POST /profiles/delete` deletes a non-default command profile.
- `GET /sessions` returns current server sessions.
- `POST /sessions` creates a server run session.
- `POST /sessions/{id}/run` starts a process in that session.
- `POST /sessions/{id}/stop` requests process termination.
- `POST /sessions/{id}/terminal/attach` attaches interactive terminal transport (v2).
- `POST /sessions/{id}/terminal/input` sends base64-encoded byte input (v2).
- `POST /sessions/{id}/terminal/resize` resizes attached terminal (v2).
- `GET /sessions/{id}/terminal/events?cursor=<seq>` returns terminal namespace events with cursor resume (v2).

Current runtime note:

- Session execution requires tmux.
- tmux-backed output uses a persistent tmux control-mode stream (`tmux -C`) for low-latency ordered terminal bytes.
- Run sessions are persisted to disk so event cursors and tmux-backed sessions can recover after server restarts.
- Session event buffering is bounded (count + bytes). When a client cursor is older than retained history, endpoints return `409` stale-cursor errors.

Terminal v2 notes:

- Terminal attach/input/resize is tmux-backed and requires tmux availability.
- `terminal/events` cursor query parameter is required and deterministic for reconnect behavior.
- v2 emits byte-oriented `terminal.output` events (`base64`).
- `GET /sessions/{id}/terminal/events` can return `409 terminal_events_cursor_stale` with details for reattach/resync flows.

Data directory:

- Default: `~/Library/Application Support/devys/mac-server/sessions`
- Override with: `DEVYS_MAC_SERVER_DATA_DIR=/path/to/data-root`
- Effective sessions path with override: `/path/to/data-root/sessions`

Run locally:

```bash
swift run --package-path Apps/mac-server mac-server --host 0.0.0.0 --port 8787
```
