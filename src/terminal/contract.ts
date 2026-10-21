import type { Scope } from "../identity/contract.ts";

/**
 * A terminal session on the trusted Mac host (.docs/COMPONENTS.md#terminal). The host owns the
 * process and its recent output; clients attach, detach and attach again from any device.
 */
export interface TerminalSession {
  id: string;
  title: string;
  cwd: string;
  /** The coding session it resumed, for "Open in Codex/Claude". */
  codingSessionId: string | null;
  cols: number;
  rows: number;
  startedAt: string;
  /** Bytes of output written so far; attach from any offset still kept. */
  offset: number;
  /** The client id that types; others watch. */
  writer: string | null;
  exit: { code: number | null } | null;
}

/** A coding agent's own interactive CLI, resumed on its session id. */
/** The provider is the Code app's (`codex`, `claude`); the host that composes both checks it. */
export type ResumeCommand = { provider: string; session: string };

export interface OpenRequest {
  scope: Scope;
  title: string;
  cwd: string;
  /** Without one, the owner's login shell. */
  resume?: ResumeCommand;
  codingSessionId?: string;
  cols: number;
  rows: number;
}

/** Messages a client sends as text frames; keystrokes travel as binary frames. */
export type ClientMessage =
  | { type: "resize"; cols: number; rows: number }
  | { type: "takeControl" };

/** Messages a client receives as text frames; output travels as binary frames. */
export type ServerMessage =
  | { type: "attached"; session: TerminalSession; client: string; offset: number }
  | { type: "writer"; writer: string | null }
  | { type: "exit"; code: number | null };

export interface Terminals {
  open(request: OpenRequest): Promise<TerminalSession>;
  list(scope: Scope): Promise<TerminalSession[]>;
  close(scope: Scope, id: string): Promise<void>;
  /** Carries one client between a WebSocket and a terminal until either side ends. */
  relay(scope: Scope, socket: WebSocket, input: { id: string; offset: number }): Promise<void>;
}
