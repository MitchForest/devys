/**
 * Terminal sessions on the trusted Mac host (local mode; .docs/COMPONENTS.md#terminal). Each is
 * a PTY running the owner's login shell (or a coding agent's own CLI resumed on its session) in
 * a folder. The host keeps the last 2 MB of output by byte offset, so a client can attach from
 * where it left off; one client types at a time. Sessions end with their process, or with the
 * host: a restart ends them and nothing is revived.
 */
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { OpenRequest, ResumeCommand, ServerMessage, TerminalSession } from "../contract.ts";
import { HostRefusal, type HostRoutes } from "../../protocol/host.ts";

const exec = promisify(execFile);
const keptBytes = 2_000_000;

/** The PTY the host runs a session in; Bun's built-in terminal in production. */
export interface Pty {
  readonly pid: number;
  write(data: Uint8Array): void;
  resize(cols: number, rows: number): void;
  kill(): void;
  readonly exited: Promise<number | null>;
}

export type SpawnPty = (input: {
  argv: string[];
  cwd: string;
  env: Record<string, string | undefined>;
  cols: number;
  rows: number;
  data: (bytes: Uint8Array) => void;
}) => Pty;

export interface TerminalsHostOptions {
  spawn: SpawnPty;
  env: Record<string, string | undefined>;
  shell: string;
  /** How a coding agent's CLI is started on its session, with the owner's own login. */
  resume: (command: ResumeCommand) => { argv: string[]; env: Record<string, string | undefined> };
  /** How long an exited session stays listed with its output, so a device can still see how it ended. */
  exitedKeptMs?: number;
}

/** Output frames: a type byte, a 4-byte length, then the payload (bytes, or JSON). */
const frame = (type: 0 | 1, payload: Uint8Array) => {
  const out = new Uint8Array(5 + payload.length);
  out[0] = type;
  new DataView(out.buffer).setUint32(1, payload.length);
  out.set(payload, 5);
  return out;
};
const event = (message: ServerMessage) =>
  frame(1, new TextEncoder().encode(JSON.stringify(message)));

interface Live {
  session: TerminalSession;
  businessId: string;
  pty: Pty;
  /** The most recent output; `start` is the offset of its first byte. */
  kept: Uint8Array[];
  keptBytes: number;
  start: number;
  listeners: Set<(chunk: Uint8Array) => void>;
}

export function terminalsHost(
  options: TerminalsHostOptions,
): HostRoutes & { ttys(): Promise<string[]> } {
  const sessions = new Map<string, Live>();

  const broadcast = (live: Live, chunk: Uint8Array) => {
    for (const listener of live.listeners) listener(chunk);
  };

  function open(request: OpenRequest): TerminalSession {
    const id = crypto.randomUUID();
    const command = request.resume
      ? options.resume(request.resume)
      : { argv: [options.shell, "-l"], env: options.env };
    const session: TerminalSession = {
      id,
      title: request.title.slice(0, 120),
      cwd: request.cwd,
      assignmentId: request.assignmentId ?? null,
      cols: request.cols,
      rows: request.rows,
      startedAt: new Date().toISOString(),
      offset: 0,
      writer: null,
      exit: null,
    };
    const live: Live = {
      session,
      businessId: request.scope.businessId,
      kept: [],
      keptBytes: 0,
      start: 0,
      listeners: new Set(),
      pty: undefined as unknown as Pty,
    };
    live.pty = options.spawn({
      argv: command.argv,
      cwd: request.cwd,
      env: { ...command.env, TERM: "xterm-256color", COLORTERM: "truecolor" },
      cols: request.cols,
      rows: request.rows,
      data: (bytes) => {
        const copy = bytes.slice();
        live.kept.push(copy);
        live.keptBytes += copy.length;
        session.offset += copy.length;
        while (live.keptBytes > keptBytes && live.kept.length > 1) {
          const dropped = live.kept.shift()!;
          live.keptBytes -= dropped.length;
          live.start += dropped.length;
        }
        broadcast(live, frame(0, copy));
      },
    });
    void live.pty.exited.then((code) => {
      session.exit = { code };
      broadcast(live, event({ type: "exit", code }));
      for (const listener of live.listeners) listener(new Uint8Array(0));
      setTimeout(
        () => {
          if (sessions.get(id) === live) sessions.delete(id);
        },
        options.exitedKeptMs ?? 10 * 60_000,
      ).unref?.();
    });
    sessions.set(id, live);
    return session;
  }

  function liveOf(input: Record<string, unknown> | URLSearchParams) {
    const get = (key: string) => (input instanceof URLSearchParams ? input.get(key) : input[key]);
    const scope = (
      input instanceof URLSearchParams ? { businessId: input.get("business") } : input.scope
    ) as { businessId?: string } | undefined;
    const live = sessions.get(String(get("id")));
    if (!live || live.businessId !== scope?.businessId)
      throw new HostRefusal(404, "No such terminal");
    return live;
  }

  const setWriter = (live: Live, writer: string | null) => {
    live.session.writer = writer;
    broadcast(live, event({ type: "writer", writer }));
  };

  return {
    prefix: "/terminals/",
    async handle(path, input) {
      switch (path) {
        case "/terminals/open": {
          const request = input.request as OpenRequest;
          if (!request?.cwd?.startsWith("/") || !(request.cols > 0) || !(request.rows > 0))
            throw new HostRefusal(400, "Open a terminal in an absolute folder with a size");
          return open(request);
        }
        case "/terminals/list": {
          const businessId = (input.scope as { businessId?: string } | undefined)?.businessId;
          return [...sessions.values()]
            .filter((live) => live.businessId === businessId)
            .map((live) => live.session);
        }
        case "/terminals/write": {
          const live = liveOf(input);
          if (live.session.writer !== input.client)
            throw new HostRefusal(409, "Another device is typing; take control first");
          live.pty.write(Uint8Array.from(Buffer.from(String(input.data), "base64")));
          return { written: true };
        }
        case "/terminals/resize": {
          const live = liveOf(input);
          if (live.session.writer !== input.client) return { resized: false };
          const cols = Number(input.cols);
          const rows = Number(input.rows);
          if (!(cols > 0 && cols < 1000 && rows > 0 && rows < 1000))
            throw new HostRefusal(400, "Bad size");
          live.pty.resize(cols, rows);
          Object.assign(live.session, { cols, rows });
          return { resized: true };
        }
        case "/terminals/control": {
          const live = liveOf(input);
          setWriter(live, String(input.client));
          return { writer: live.session.writer };
        }
        case "/terminals/release": {
          const live = liveOf(input);
          if (live.session.writer === input.client) setWriter(live, null);
          return { writer: live.session.writer };
        }
        case "/terminals/close": {
          const live = liveOf(input);
          live.pty.kill();
          sessions.delete(live.session.id);
          return { closed: true };
        }
        default:
          throw new HostRefusal(404, "Not found");
      }
    },
    /**
     * Streams a session from an offset: what is still kept, then live output, as frames. The
     * first frame says where it started; a client that asks for more than was kept starts at
     * the oldest byte still held.
     */
    stream(path, url, write, closed) {
      if (path !== "/terminals/stream") return false;
      const live = liveOf(url.searchParams);
      const client = url.searchParams.get("client") ?? crypto.randomUUID();
      const asked = Number(url.searchParams.get("offset") ?? 0);
      const from = Math.min(Math.max(asked, live.start), live.session.offset);
      // The first device to attach types; others watch until they take control.
      if (live.session.writer === null && !live.session.exit) live.session.writer = client;
      write(event({ type: "attached", session: live.session, client, offset: from }));
      let position = live.start;
      for (const chunk of live.kept) {
        const end = position + chunk.length;
        if (end > from) write(frame(0, chunk.subarray(Math.max(0, from - position))));
        position = end;
      }
      if (live.session.exit) {
        write(event({ type: "exit", code: live.session.exit.code }));
        return true;
      }
      const listener = (chunk: Uint8Array) => (chunk.length ? write(chunk) : write(null));
      live.listeners.add(listener);
      closed.then(() => {
        live.listeners.delete(listener);
        if (live.session.writer === client) setWriter(live, null);
      });
      return "open";
    },
    async ttys() {
      const pids = [...sessions.values()]
        .filter((live) => !live.session.exit)
        .map((live) => live.pty.pid);
      if (!pids.length) return [];
      const { stdout } = await exec("ps", ["-o", "tty=", "-p", pids.join(",")]).catch(() => ({
        stdout: "",
      }));
      return stdout
        .split("\n")
        .map((line) => line.trim())
        .filter((tty) => tty && tty !== "??");
    },
    async close() {
      for (const live of sessions.values()) live.pty.kill();
      sessions.clear();
    },
  };
}

/** Bun's built-in PTY, which the host process runs on. */
export const bunPty: SpawnPty = ({ argv, cwd, env, cols, rows, data }) => {
  const bun = (globalThis as { Bun?: BunSpawn }).Bun;
  if (!bun) throw new Error("Terminals need the host to run on Bun");
  const process = bun.spawn(argv, {
    cwd,
    env,
    terminal: { cols, rows, data: (_terminal: unknown, bytes: Uint8Array) => data(bytes) },
  });
  return {
    pid: process.pid,
    write: (bytes) => process.terminal.write(bytes),
    resize: (c, r) => process.terminal.resize(c, r),
    kill: () => process.kill(),
    exited: process.exited.then(() => process.exitCode),
  };
};

interface BunSpawn {
  spawn(
    argv: string[],
    options: {
      cwd: string;
      env: Record<string, string | undefined>;
      terminal: {
        cols: number;
        rows: number;
        data: (terminal: unknown, bytes: Uint8Array) => void;
      };
    },
  ): {
    pid: number;
    exitCode: number | null;
    exited: Promise<number>;
    kill(): void;
    terminal: { write(bytes: Uint8Array): void; resize(cols: number, rows: number): void };
  };
}
