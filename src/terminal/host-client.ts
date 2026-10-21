import type { Scope } from "../identity/contract.ts";
import { hostDown, hostFailure, Unavailable } from "../protocol/host.ts";
import type { ClientMessage, Terminals } from "./contract.ts";

type Host = { url: string; token: string };

async function call<T>(host: Host, path: string, body: Record<string, unknown>): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`${host.url}/terminals/${path}`, {
      method: "POST",
      headers: { authorization: `Bearer ${host.token}`, "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    throw hostDown("terminals are");
  }
  if (!response.ok) throw await hostFailure(response);
  return (await response.json()) as T;
}

/** Terminals on the trusted Mac host (local mode), always naming the business they serve. */
export function hostTerminals(host: Host, scope: Scope): Terminals {
  return {
    open: (request) => call(host, "open", { scope, request }),
    list: () => call(host, "list", { scope }),
    close: async (_scope, id) => {
      await call(host, "close", { scope, id });
    },
    relay: (_scope, socket, input) => relayTerminal(host, scope, socket, input),
  };
}

/** Cloud mode has no terminals yet. */
export function unavailableTerminals(): Terminals {
  const refuse = () => Promise.reject(new Unavailable("Terminals run in local mode only."));
  return { open: refuse, list: refuse, close: refuse, relay: refuse };
}

/**
 * Carries one client between a WebSocket and a host terminal: host frames out (output as
 * binary, events as text), keystrokes and control messages in. Closing either side ends it.
 */
async function relayTerminal(
  host: Host,
  scope: Scope,
  socket: WebSocket,
  input: { id: string; offset: number },
) {
  const client = crypto.randomUUID();
  const ask = (path: string, body: Record<string, unknown>) =>
    call(host, path, { scope, id: input.id, client, ...body }).catch((error: unknown) => {
      socket.send(
        JSON.stringify({
          type: "error",
          message: error instanceof Error ? error.message : "Refused",
        }),
      );
    });
  const response = await fetch(
    `${host.url}/terminals/stream?${new URLSearchParams({
      id: input.id,
      business: scope.businessId,
      offset: String(input.offset),
      client,
    })}`,
    { headers: { authorization: `Bearer ${host.token}` } },
  );
  // A session the host no longer has ended, for example when the host restarted.
  if (response.status === 404) {
    socket.send(JSON.stringify({ type: "exit", code: null }));
    socket.close(1000, "Terminal ended");
    return;
  }
  if (!response.ok || !response.body) {
    socket.close(1011, (await response.text()).slice(0, 120) || "Terminal unavailable");
    return;
  }
  const reader = response.body.getReader();
  // Messages are handled one at a time so keystrokes reach the shell in the order typed.
  let queue = Promise.resolve();
  socket.addEventListener("message", (message) => {
    queue = queue.then(async () => {
      if (typeof message.data === "string") {
        const parsed = JSON.parse(message.data) as ClientMessage;
        if (parsed.type === "resize") await ask("resize", { cols: parsed.cols, rows: parsed.rows });
        else if (parsed.type === "takeControl") await ask("control", {});
        return;
      }
      // Binary frames arrive as an ArrayBuffer or a Blob depending on the runtime.
      const data = message.data as ArrayBuffer | Blob;
      const bytes = new Uint8Array(data instanceof Blob ? await data.arrayBuffer() : data);
      let binary = "";
      for (const byte of bytes) binary += String.fromCharCode(byte);
      await ask("write", { data: btoa(binary) });
    });
  });
  // Cancelling the stream may not reach the host at once, so the keyboard is released explicitly.
  socket.addEventListener("close", () => {
    void reader.cancel();
    void call(host, "release", { scope, id: input.id, client }).catch(() => undefined);
  });
  // Host frames: a type byte, a 4-byte length, then the payload.
  let pending = new Uint8Array(0);
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    const joined = new Uint8Array(pending.length + value.length);
    joined.set(pending);
    joined.set(value, pending.length);
    let at = 0;
    while (joined.length - at >= 5) {
      const length = new DataView(joined.buffer, joined.byteOffset + at + 1, 4).getUint32(0);
      if (joined.length - at - 5 < length) break;
      const payload = joined.subarray(at + 5, at + 5 + length);
      if (joined[at] === 0) socket.send(payload.slice());
      else socket.send(new TextDecoder().decode(payload));
      at += 5 + length;
    }
    pending = joined.slice(at);
  }
  socket.close(1000, "Terminal ended");
}
