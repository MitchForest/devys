/**
 * Claude Code through the installed, unmodified `claude` CLI in its stream-json mode: one
 * process per running turn. A message written while a turn runs joins that turn (steering);
 * when the turn ends the process exits, and the next message resumes the session by id, as
 * after a host restart or an interrupt. The CLI is used directly rather than the Agent
 * SDK, which carries Anthropic's commercial licence and bundles its own binary; the owner's
 * own login in `CLAUDE_CONFIG_DIR` is used, never an API key from the environment.
 */
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import type { TranscriptEntry } from "../contract.ts";
import type { ProviderAdapter, ProviderEvents } from "./provider.ts";

type Part =
  | { type: "text"; text: string }
  | { type: "tool_use"; id: string; name: string; input: Record<string, unknown> }
  | { type: "tool_result"; tool_use_id: string; content: unknown; is_error?: boolean };

/** A tool call as a transcript step: shell commands, file edits, the to-do plan, the rest by name. */
function toolEntry(name: string, input: Record<string, unknown>): TranscriptEntry {
  if (name === "Bash") return { kind: "command", text: String(input.command ?? "") };
  if (["Edit", "Write", "MultiEdit", "NotebookEdit"].includes(name))
    return { kind: "files", text: String(input.file_path ?? input.notebook_path ?? "") };
  if (name === "TodoWrite")
    return {
      kind: "plan",
      text: ((input.todos as { content?: string; status?: string }[] | undefined) ?? [])
        .map((todo) => `${todo.status === "completed" ? "✓" : "·"} ${todo.content ?? ""}`)
        .join("\n"),
    };
  return { kind: "tool", text: name };
}

/**
 * The steps in a Claude Code session file (`projects/<folder>/<session>.jsonl` in the config
 * directory): prompts, replies and tool calls, each tool's result attached to its call.
 */
export function claudeEntries(jsonl: string): TranscriptEntry[] {
  const entries: TranscriptEntry[] = [];
  const calls = new Map<string, TranscriptEntry>();
  for (const line of jsonl.split("\n")) {
    if (!line.trim()) continue;
    let record: { type?: string; message?: { content?: string | Part[] } };
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }
    if (record.type !== "user" && record.type !== "assistant") continue;
    const content = record.message?.content;
    if (typeof content === "string") {
      entries.push({ kind: record.type === "user" ? "prompt" : "reply", text: content });
      continue;
    }
    for (const part of content ?? []) {
      if (part.type === "text" && part.text.trim())
        entries.push({ kind: record.type === "user" ? "prompt" : "reply", text: part.text });
      else if (part.type === "tool_use") {
        const entry = toolEntry(part.name, part.input);
        calls.set(part.id, entry);
        entries.push(entry);
      } else if (part.type === "tool_result") {
        const call = calls.get(part.tool_use_id);
        if (!call) continue;
        const output = Array.isArray(part.content)
          ? part.content.map((item: { text?: string }) => item.text ?? "").join("\n")
          : String(part.content ?? "");
        if (output) call.detail = output;
        if (part.is_error) call.failed = true;
      }
    }
  }
  return entries;
}

export interface ClaudeOptions {
  /** The Claude config directory holding the owner's login and sessions. */
  configDir: string;
  env: NodeJS.ProcessEnv;
  command?: string;
}

/**
 * Inherited Anthropic and Claude Code settings (API keys, gateway URLs, a parent Claude Code
 * session's variables) would take precedence over, or confuse, the owner's own login.
 */
const inherited = (name: string) => name.startsWith("ANTHROPIC_") || name.startsWith("CLAUDE");

type Line = {
  type?: string;
  subtype?: string;
  session_id?: string;
  result?: string;
  is_error?: boolean;
};

interface Session {
  child: ChildProcessWithoutNullStreams;
  turn: string | null;
  interrupting: boolean;
}

const message = (text: string) =>
  `${JSON.stringify({ type: "user", message: { role: "user", content: text } })}\n`;
const newTurn = (sessionId: string) => `${sessionId}:${Date.now().toString(36)}`;

export function claudeAdapter(options: ClaudeOptions, events: ProviderEvents): ProviderAdapter {
  const sessions = new Map<string, Session>();
  const env = {
    ...Object.fromEntries(Object.entries(options.env).filter(([name]) => !inherited(name))),
    CLAUDE_CONFIG_DIR: options.configDir,
  };

  /**
   * Starts a CLI process with its first message (the CLI says nothing until it has input) and
   * resolves with the session id from its first line. A resumed session keeps its id.
   */
  function open(input: {
    cwd: string;
    text: string;
    instructions?: string;
    resume?: string;
    readOnly: boolean;
  }) {
    const child = spawn(
      options.command ?? "claude",
      [
        "-p",
        "--input-format=stream-json",
        "--output-format=stream-json",
        "--verbose",
        // A review reads and runs read-only tools; a build works on its own in its worktree.
        `--permission-mode=${input.readOnly ? "plan" : "bypassPermissions"}`,
        ...(input.instructions ? ["--append-system-prompt", input.instructions] : []),
        ...(input.resume ? ["--resume", input.resume] : []),
      ],
      { cwd: input.cwd, env, stdio: ["pipe", "pipe", "pipe"] },
    );
    child.stderr.resume();
    child.stdin.write(message(input.text));
    return new Promise<{ sessionId: string; session: Session }>((resolve, reject) => {
      let sessionId: string | undefined;
      let buffer = "";
      child.stdout.setEncoding("utf8");
      child.stdout.on("data", (chunk: string) => {
        buffer += chunk;
        for (let end = buffer.indexOf("\n"); end >= 0; end = buffer.indexOf("\n")) {
          const text = buffer.slice(0, end);
          buffer = buffer.slice(end + 1);
          let line: Line;
          try {
            line = JSON.parse(text) as Line;
          } catch {
            continue;
          }
          if (!sessionId && line.session_id) {
            sessionId = input.resume ?? line.session_id;
            const session: Session = { child, turn: newTurn(sessionId), interrupting: false };
            sessions.set(sessionId, session);
            resolve({ sessionId, session });
          }
          if (line.type === "result" && sessionId) {
            const session = sessions.get(sessionId);
            const turn = session?.turn;
            if (!session || !turn) continue;
            session.turn = null;
            const failed = line.is_error || line.subtype !== "success";
            // On SIGINT the CLI reports the cut-off turn as an execution error.
            const interrupted = failed && session.interrupting;
            session.interrupting = false;
            if (interrupted) {
              events.turnEnded({
                sessionId,
                turnId: turn,
                status: "interrupted",
                reply: null,
                error: null,
              });
              continue;
            }
            // An idle session holds no process; the next message resumes it by id.
            sessions.delete(sessionId);
            session.child.stdin.end();
            events.turnEnded({
              sessionId,
              turnId: turn,
              status: failed ? "failed" : "completed",
              reply: failed ? null : (line.result ?? null),
              error: failed
                ? (line.result ?? line.subtype ?? "Claude Code reported an error")
                : null,
            });
          }
        }
      });
      child.on("exit", () => {
        if (!sessionId) return reject(new Error("Claude Code exited before its session began"));
        const session = sessions.get(sessionId);
        if (session?.child !== child) return;
        sessions.delete(sessionId);
        if (!session.turn) return;
        if (session.interrupting)
          events.turnEnded({
            sessionId,
            turnId: session.turn,
            status: "interrupted",
            reply: null,
            error: null,
          });
        else events.lost([sessionId]);
      });
      child.on("error", reject);
    });
  }

  function say(session: Session, sessionId: string, text: string) {
    const steered = session.turn !== null;
    session.turn ??= newTurn(sessionId);
    session.child.stdin.write(message(text));
    return { turnId: session.turn, steered };
  }

  return {
    async start({ cwd, instructions, prompt, readOnly }) {
      const { sessionId, session } = await open({ cwd, text: prompt, instructions, readOnly });
      return { sessionId, turnId: session.turn! };
    },

    async send({ sessionId, cwd, text, readOnly }) {
      const running = sessions.get(sessionId);
      if (running) return say(running, sessionId, text);
      const { session } = await open({ cwd, text, resume: sessionId, readOnly });
      return { turnId: session.turn!, steered: false };
    },

    async interrupt(sessionId) {
      const session = sessions.get(sessionId);
      if (!session?.turn) return;
      // The CLI ends its turn cleanly on SIGINT; the session resumes on the next message.
      session.interrupting = true;
      session.child.kill("SIGINT");
    },

    async transcript({ sessionId }) {
      // The session's folder is named after its working directory; the id is unique.
      const projects = join(options.configDir, "projects");
      for (const folder of await readdir(projects).catch(() => [] as string[])) {
        const text = await readFile(join(projects, folder, `${sessionId}.jsonl`), "utf8").catch(
          () => undefined,
        );
        if (text !== undefined) return claudeEntries(text);
      }
      return [];
    },

    async close() {
      for (const session of sessions.values()) session.child.kill("SIGTERM");
      sessions.clear();
    },
  };
}
