/**
 * browser-harness-js's `Session` over Chrome's DevTools pipe (`--remote-debugging-pipe`: the
 * child's fd 3 receives commands, fd 4 sends replies and events, each message JSON ending in a
 * NUL byte) instead of a WebSocket, so a business's Chrome listens on no port any other process
 * could reach. `Session` only speaks WebSocket; this adapter stands in for its socket through
 * two private members, `ws` (anything with `readyState`, `send`, `close`) and `onMessage(raw)`,
 * as the harness's own `sdk/session.test.ts` does. Checked against the pinned commit
 * 2d9a5ed37ed11f31b2622cd69c4b55f979cb905f; recheck when the pin moves.
 */
import type { Readable, Writable } from "node:stream";
import { Session } from "browser-harness-js/sdk/session.ts";

interface SessionInternals {
  ws: { readyState: number; send(raw: string): void; close(): void };
  onMessage(raw: string): void;
  pending: Map<number, { reject(error: unknown): void }>;
}

/** A connected `Session` on a Chrome started with `--remote-debugging-pipe`. */
export function pipeSession(toChrome: Writable, fromChrome: Readable): Session {
  const session = new Session();
  const internals = session as unknown as SessionInternals;
  const socket = {
    readyState: WebSocket.OPEN as number,
    send: (raw: string) => void toChrome.write(`${raw}\0`),
    close: () => {
      if (socket.readyState === WebSocket.CLOSED) return;
      socket.readyState = WebSocket.CLOSED;
      toChrome.end();
      for (const [, pending] of internals.pending) pending.reject(new Error("CDP pipe closed"));
      internals.pending.clear();
    },
  };
  internals.ws = socket;
  let buffered = "";
  fromChrome.setEncoding("utf8");
  fromChrome.on("data", (chunk: string) => {
    buffered += chunk;
    let end: number;
    while ((end = buffered.indexOf("\0")) >= 0) {
      const message = buffered.slice(0, end);
      buffered = buffered.slice(end + 1);
      internals.onMessage(message);
    }
  });
  fromChrome.on("close", socket.close);
  toChrome.on("error", socket.close);
  return session;
}
