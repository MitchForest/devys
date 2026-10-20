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
