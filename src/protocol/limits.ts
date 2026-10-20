/** Private-dogfood bounds. Pi owns retries, compaction, task state, and usage. */
export const defaultLimits = {
  maxDurationMs: 10 * 60_000, // Includes time queued after channel receipt.
  maxCapabilityCalls: 80, // Per Code Mode program; direct tools run sequentially.
  maxCommandMs: 60_000,
  maxOutputBytes: 64_000,
  maxArtifactBytes: 20_000_000,
} as const;

/** Bounds every runner enforces on one command, whatever the caller asked for. */
export const withinCommandLimits = (command: string, timeoutMs: number, maxBytes: number) =>
  command.length <= 64_000 &&
  timeoutMs >= 1_000 &&
  timeoutMs <= 120_000 &&
  maxBytes >= 1_000 &&
  maxBytes <= 1_000_000;
