/**
 * Codex through `codex app-server`: JSON-RPC lines over stdio, started on first use. The host
 * makes one adapter per business, and it runs one process for builds and one for reviews, each
 * under the host's confinement for that business. Codex's own Seatbelt sandbox cannot start
 * inside another Seatbelt profile, so threads run with Codex's sandbox off and the review
 * process's confinement is what keeps a review from writing. Threads persist in the Codex
 * home, so a thread the current process has not loaded is resumed before its next turn. Message shapes come from the protocol
 * generated for the pinned Codex (`codex-protocol/`, `bun run codex:protocol`).
 */
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import type { InitializeParams } from "./codex-protocol/InitializeParams";
import type { ItemCompletedNotification } from "./codex-protocol/v2/ItemCompletedNotification";
import type { ThreadItem } from "./codex-protocol/v2/ThreadItem";
import type { ThreadReadParams } from "./codex-protocol/v2/ThreadReadParams";
import type { ThreadReadResponse } from "./codex-protocol/v2/ThreadReadResponse";
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
import type { TranscriptEntry } from "../contract.ts";
import type { Confine, ProviderAdapter, ProviderEvents } from "./provider.ts";

/** A command without the shell wrapper Codex runs it in (`/bin/zsh -lc "…"`). */
export function unwrapped(command: string) {
  const inner = /^\/bin\/(?:ba|z)?sh -lc (["'])([\s\S]*)\1$/.exec(command.trim())?.[2];
  return inner === undefined ? command : inner.replace(/\\(["\\$`])/g, "$1");
}

/** One Codex thread item as a transcript step; items with nothing to show are skipped. */
function codexEntry(item: ThreadItem): TranscriptEntry[] {
  switch (item.type) {
    case "userMessage":
      return [
        {
          kind: "prompt",
          text: item.content
            .flatMap((part) => (part.type === "text" ? [part.text] : []))
            .join("\n"),
        },
      ];
    case "agentMessage":
      return item.text ? [{ kind: "reply", text: item.text }] : [];
    case "plan":
      return [{ kind: "plan", text: item.text }];
    case "commandExecution":
      return [
        {
          kind: "command",
          text: unwrapped(item.command),
          ...(item.aggregatedOutput ? { detail: item.aggregatedOutput } : {}),
          ...(item.exitCode !== null && item.exitCode !== 0 ? { failed: true } : {}),
        },
      ];
    case "fileChange":
      return [{ kind: "files", text: item.changes.map((change) => change.path).join(", ") }];
    case "mcpToolCall":
      return [
        {
          kind: "tool",
          text: `${item.server}.${item.tool}`,
          ...(item.error ? { failed: true } : {}),
        },
      ];
    default:
      return [];
  }
}

type Message = {
  id?: number | string;
  method?: string;
  params?: unknown;
  result?: unknown;
  error?: { message?: string };
};

interface CodexOptions {
  /** The Codex home holding the owner's login and sessions. */
  home: string;
  env: NodeJS.ProcessEnv;
  command?: string;
  /** Keeps the build (false) or review (true) process in its business. */
  /** Holds the process for its business (Seatbelt on the Mac host). */
  confine: (readOnly: boolean) => Confine;
}

export function codexAdapter(options: CodexOptions, events: ProviderEvents): ProviderAdapter {
  /** The build (false) and review (true) processes. */
  const servers = new Map<boolean, Promise<Connection>>();
  /** The running turn, latest reply and process of each thread a process has loaded. */
  const threads = new Map<
    string,
    { turn: string | null; reply: string | null; readOnly: boolean }
  >();
  /** What Codex asked approval for and Devys declined, per thread, said with the turn's end. */
  const declined = new Map<string, string[]>();

  interface Connection {
    child: ChildProcessWithoutNullStreams;
    call<T>(method: string, params: unknown): Promise<T>;
  }

  function connect(readOnly: boolean): Promise<Connection> {
    const existing = servers.get(readOnly);
    if (existing) return existing;
    const server = (async () => {
      const child = spawn(
        ...options.confine(readOnly)(options.command ?? "codex", ["app-server"]),
        {
          env: { ...options.env, CODEX_HOME: options.home },
          stdio: ["pipe", "pipe", "pipe"],
        },
      );
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
            // Sessions run without approvals; anything Codex still asks is declined, and said.
            write({ id: message.id, result: { decision: "decline" } });
            const asked = (message.params ?? {}) as {
              threadId?: string;
              command?: string;
              reason?: string;
            };
            if (asked.threadId)
              declined.set(asked.threadId, [
                ...(declined.get(asked.threadId) ?? []),
                asked.command ?? asked.reason ?? message.method,
              ]);
          } else notify(readOnly, message.method, message.params);
        }
      });
      child.stderr.resume();
      child.on("exit", () => {
        if (servers.get(readOnly) === server) servers.delete(readOnly);
        for (const pending of waiting.values()) pending.reject(new Error("Codex exited"));
        waiting.clear();
        const gone = [...threads].filter(([, thread]) => thread.readOnly === readOnly);
        for (const [id] of gone) threads.delete(id);
        const running = gone.filter(([, thread]) => thread.turn).map(([id]) => id);
        if (running.length) events.lost(running);
      });
      await call("initialize", {
        clientInfo: { name: "devys", title: "Devys", version: "1" },
        capabilities: null,
      } satisfies InitializeParams);
      write({ method: "initialized", params: {} });
      return { child, call };
    })().catch((error: unknown) => {
      if (servers.get(readOnly) === server) servers.delete(readOnly);
      throw error;
    });
    servers.set(readOnly, server);
    return server;
  }

  function notify(readOnly: boolean, method: string, params: unknown) {
    if (method === "turn/started") {
      const { threadId, turn } = params as TurnStartedNotification;
      threads.set(threadId, { reply: null, ...threads.get(threadId), turn: turn.id, readOnly });
    } else if (method === "item/completed") {
      const { threadId, item } = params as ItemCompletedNotification;
      if (item.type === "agentMessage" && item.text)
        threads.set(threadId, { turn: null, ...threads.get(threadId), reply: item.text, readOnly });
    } else if (method === "turn/completed") {
      const { threadId, turn } = params as TurnCompletedNotification;
      const thread = threads.get(threadId);
      threads.set(threadId, { turn: null, reply: thread?.reply ?? null, readOnly });
      if (turn.status === "inProgress") return;
      const refused = declined.get(threadId) ?? [];
      declined.delete(threadId);
      const note = refused.length
        ? `Devys declined what Codex asked to approve (sessions run without approvals): ${refused.join("; ").slice(0, 500)}`
        : "";
      events.turnEnded({
        sessionId: threadId,
        turnId: turn.id,
        status: turn.status,
        reply: [thread?.reply, note].filter(Boolean).join("\n\n") || null,
        error: turn.error?.message ?? null,
      });
    }
  }

  // Codex's own sandbox stays off: the host's confinement holds the process (see above).
  const sandbox = "danger-full-access";

  async function startTurn(
    connection: Connection,
    threadId: string,
    text: string,
    readOnly: boolean,
  ) {
    const { turn } = await connection.call<TurnStartResponse>("turn/start", {
      threadId,
      input: [{ type: "text", text, text_elements: [] }],
    } as TurnStartParams);
    threads.set(threadId, { reply: null, ...threads.get(threadId), turn: turn.id, readOnly });
    return turn.id;
  }

  return {
    async start({ cwd, instructions, prompt, readOnly }) {
      const connection = await connect(readOnly);
      const { thread } = await connection.call<ThreadStartResponse>("thread/start", {
        cwd,
        approvalPolicy: "never",
        sandbox,
        developerInstructions: instructions,
      } satisfies ThreadStartParams);
      threads.set(thread.id, { turn: null, reply: null, readOnly });
      return {
        sessionId: thread.id,
        turnId: await startTurn(connection, thread.id, prompt, readOnly),
      };
    },

    async send({ sessionId, cwd, text, readOnly }) {
      const connection = await connect(readOnly);
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
          sandbox,
        } as ThreadResumeParams);
        threads.set(sessionId, { turn: null, reply: null, readOnly });
      }
      return { turnId: await startTurn(connection, sessionId, text, readOnly), steered: false };
    },

    async interrupt(sessionId) {
      const thread = threads.get(sessionId);
      if (!thread?.turn || !servers.has(thread.readOnly)) return;
      await (
        await connect(thread.readOnly)
      ).call("turn/interrupt", {
        threadId: sessionId,
        turnId: thread.turn,
      } satisfies TurnInterruptParams);
    },

    async transcript({ sessionId }) {
      // Any process reads a thread from the Codex home; the one holding it, if any.
      const { thread } = await (
        await connect(threads.get(sessionId)?.readOnly ?? false)
      ).call<ThreadReadResponse>("thread/read", {
        threadId: sessionId,
        includeTurns: true,
      } satisfies ThreadReadParams);
      return thread.turns.flatMap((turn) => turn.items.flatMap(codexEntry));
    },

    async close() {
      for (const server of servers.values())
        (await server.catch(() => undefined))?.child.kill("SIGTERM");
    },
  };
}
