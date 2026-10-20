/**
 * Codex through `codex app-server`: JSON-RPC lines over stdio, one process for the host,
 * started on first use. Threads persist in the Codex home, so a thread the current process
 * has not loaded is resumed before its next turn. Message shapes come from the protocol
 * generated for the pinned Codex (`codex-protocol/`, `bun run codex:protocol`).
 */
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import type { InitializeParams } from "./codex-protocol/InitializeParams";
import type { ItemCompletedNotification } from "./codex-protocol/v2/ItemCompletedNotification";
import type { ThreadResumeParams } from "./codex-protocol/v2/ThreadResumeParams";
import type { ThreadStartParams } from "./codex-protocol/v2/ThreadStartParams";
import type { ThreadStartResponse } from "./codex-protocol/v2/ThreadStartResponse";
import type { TurnCompletedNotification } from "./codex-protocol/v2/TurnCompletedNotification";
import type { TurnInterruptParams } from "./codex-protocol/v2/TurnInterruptParams";
import type { TurnStartedNotification } from "./codex-protocol/v2/TurnStartedNotification";
import type { TurnStartParams } from "./codex-protocol/v2/TurnStartParams";
import type { TurnStartResponse } from "./codex-protocol/v2/TurnStartResponse";
import type { TurnSteerParams } from "./codex-protocol/v2/TurnSteerParams";
import type { TurnSteerResponse } from "./codex-protocol/v2/TurnSteerResponse";
import type { ProviderAdapter, ProviderEvents } from "./provider.ts";

type Message = {
  id?: number | string;
  method?: string;
  params?: unknown;
  result?: unknown;
  error?: { message?: string };
};

export interface CodexOptions {
  /** The Codex home holding the owner's login and sessions. */
  home: string;
  env: NodeJS.ProcessEnv;
  command?: string;
}

export function codexAdapter(options: CodexOptions, events: ProviderEvents): ProviderAdapter {
  let server: Promise<Connection> | undefined;
  /** The running turn and latest reply of each thread this process has loaded. */
  const threads = new Map<string, { turn: string | null; reply: string | null }>();

  interface Connection {
    child: ChildProcessWithoutNullStreams;
    call<T>(method: string, params: unknown): Promise<T>;
  }

  function connect(): Promise<Connection> {
    server ??= (async () => {
      const child = spawn(options.command ?? "codex", ["app-server"], {
        env: { ...options.env, CODEX_HOME: options.home },
        stdio: ["pipe", "pipe", "pipe"],
      });
      let next = 0;
      const waiting = new Map<
        number,
        { resolve(value: unknown): void; reject(error: Error): void }
      >();
      const write = (message: Message) => child.stdin.write(`${JSON.stringify(message)}\n`);
      const call = <T>(method: string, params: unknown) =>
        new Promise<T>((resolve, reject) => {
          const id = ++next;
          waiting.set(id, { resolve: resolve as (value: unknown) => void, reject });
          write({ id, method, params });
        });
      let buffer = "";
      child.stdout.setEncoding("utf8");
      child.stdout.on("data", (chunk: string) => {
        buffer += chunk;
        for (let end = buffer.indexOf("\n"); end >= 0; end = buffer.indexOf("\n")) {
          const line = buffer.slice(0, end);
          buffer = buffer.slice(end + 1);
          if (!line.trim()) continue;
          let message: Message;
          try {
            message = JSON.parse(line) as Message;
          } catch {
            continue;
          }
          if (message.method === undefined) {
            const pending = waiting.get(Number(message.id));
            waiting.delete(Number(message.id));
            if (message.error) pending?.reject(new Error(message.error.message ?? "Codex error"));
            else pending?.resolve(message.result);
          } else if (message.id !== undefined) {
            // Sessions run without approvals; anything Codex still asks is declined.
            write({ id: message.id, result: { decision: "decline" } });
          } else notify(message.method, message.params);
        }
      });
      child.stderr.resume();
      child.on("exit", () => {
        server = undefined;
        for (const pending of waiting.values()) pending.reject(new Error("Codex exited"));
        waiting.clear();
        const running = [...threads].filter(([, thread]) => thread.turn).map(([id]) => id);
        threads.clear();
        if (running.length) events.lost(running);
      });
      await call("initialize", {
        clientInfo: { name: "devys", title: "Devys", version: "1" },
        capabilities: null,
      } satisfies InitializeParams);
      write({ method: "initialized", params: {} });
      return { child, call };
    })().catch((error: unknown) => {
      server = undefined;
      throw error;
    });
    return server;
  }

  function notify(method: string, params: unknown) {
    if (method === "turn/started") {
      const { threadId, turn } = params as TurnStartedNotification;
      threads.set(threadId, { reply: null, ...threads.get(threadId), turn: turn.id });
    } else if (method === "item/completed") {
      const { threadId, item } = params as ItemCompletedNotification;
      if (item.type === "agentMessage" && item.text)
        threads.set(threadId, { turn: null, ...threads.get(threadId), reply: item.text });
    } else if (method === "turn/completed") {
      const { threadId, turn } = params as TurnCompletedNotification;
      const thread = threads.get(threadId);
      threads.set(threadId, { turn: null, reply: thread?.reply ?? null });
      if (turn.status === "inProgress") return;
      events.turnEnded({
        sessionId: threadId,
        turnId: turn.id,
        status: turn.status,
        reply: thread?.reply ?? null,
        error: turn.error?.message ?? null,
      });
    }
  }

  const sandbox = (readOnly: boolean) => (readOnly ? "read-only" : "danger-full-access");

  async function startTurn(connection: Connection, threadId: string, text: string) {
    const { turn } = await connection.call<TurnStartResponse>("turn/start", {
      threadId,
      input: [{ type: "text", text, text_elements: [] }],
    } as TurnStartParams);
    threads.set(threadId, { reply: null, ...threads.get(threadId), turn: turn.id });
    return turn.id;
  }

  return {
    async start({ cwd, instructions, prompt, readOnly }) {
      const connection = await connect();
      const { thread } = await connection.call<ThreadStartResponse>("thread/start", {
        cwd,
        approvalPolicy: "never",
        sandbox: sandbox(readOnly),
        developerInstructions: instructions,
      } satisfies ThreadStartParams);
      threads.set(thread.id, { turn: null, reply: null });
      return { sessionId: thread.id, turnId: await startTurn(connection, thread.id, prompt) };
    },

    async send({ sessionId, cwd, text, readOnly }) {
      const connection = await connect();
      const loaded = threads.get(sessionId);
      if (loaded?.turn) {
        const { turnId } = await connection.call<TurnSteerResponse>("turn/steer", {
          threadId: sessionId,
          expectedTurnId: loaded.turn,
          input: [{ type: "text", text, text_elements: [] }],
        } as TurnSteerParams);
        return { turnId, steered: true };
      }
      if (!loaded) {
        await connection.call("thread/resume", {
          threadId: sessionId,
          cwd,
          approvalPolicy: "never",
          sandbox: sandbox(readOnly),
        } as ThreadResumeParams);
        threads.set(sessionId, { turn: null, reply: null });
      }
      return { turnId: await startTurn(connection, sessionId, text), steered: false };
    },

    async interrupt(sessionId) {
      const turn = threads.get(sessionId)?.turn;
      if (!turn || !server) return;
      await (
        await connect()
      ).call("turn/interrupt", { threadId: sessionId, turnId: turn } satisfies TurnInterruptParams);
    },

    async close() {
      const connection = await server?.catch(() => undefined);
      connection?.child.kill("SIGTERM");
    },
  };
}
