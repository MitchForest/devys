import type { TranscriptEntry } from "../contract.ts";

/** Keeps a transcript readable: the latest 200 steps, each cut to a few thousand characters. */
export const bounded = (entries: TranscriptEntry[]): TranscriptEntry[] =>
  entries.slice(-200).map((entry) => ({
    ...entry,
    text: entry.text.slice(0, 2000),
    ...(entry.detail !== undefined ? { detail: entry.detail.slice(-4000) } : {}),
  }));

/**
 * Wraps a harness process so it stays in its business (the host's Seatbelt confinement, chosen
 * by `src/host.ts`): the file and arguments to spawn instead of `command args`.
 */
export type Confine = (command: string, args: readonly string[]) => [string, string[]];

/** How the host drives one coding harness. Each adapter maps its native protocol onto this. */
export interface ProviderAdapter {
  /** Opens a session in `cwd` and starts its first turn. */
  start(input: { cwd: string; instructions: string; prompt: string; readOnly: boolean }): Promise<{
    sessionId: string;
    turnId: string;
  }>;
  /** Adds to the running turn when there is one; otherwise starts the next turn. */
  send(input: {
    sessionId: string;
    cwd: string;
    text: string;
    readOnly: boolean;
  }): Promise<{ turnId: string; steered: boolean }>;
  interrupt(sessionId: string): Promise<void>;
  /** The session's steps from the harness's own record, oldest first. */
  transcript(input: { sessionId: string; cwd: string }): Promise<TranscriptEntry[]>;
  /** Stops every process the adapter started. */
  close(): Promise<void>;
}

/** What an adapter reports as its sessions work. */
export interface ProviderEvents {
  turnEnded(event: {
    sessionId: string;
    turnId: string;
    status: "completed" | "interrupted" | "failed";
    reply: string | null;
    error: string | null;
  }): void;
  /** The harness process itself went away; its running turns did not finish. */
  lost(sessionIds: readonly string[]): void;
}
