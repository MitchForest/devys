import { ROOT_SESSION, type PiHarness } from "agents/harness/pi";
import type { LifecycleJob, LifecycleJobs } from "agents/lifecycle";
import type { EntryId } from "@earendil-works/pi-durable";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { Effect } from "effect";
import type { Memory, Observation } from "../memory/contract.ts";
import { catchUpMemory } from "./memory.ts";
import { conversationOf, type Sessions } from "./sessions.ts";

const retryAfter = 30_000;

/**
 * Keeps business memory caught up with the employee's Pi sessions in a background job that
 * yields to any input, and supplies the memory each turn travels with.
 */
export function memoryUpkeep(deps: {
  storage: DurableObjectStorage;
  jobs: LifecycleJobs;
  harness: PiHarness;
  sessions: Sessions;
  memory: (signal?: AbortSignal) => Memory;
  /** Whether the employee and its business are still active. */
  active: () => Promise<boolean>;
}) {
  let running: AbortController | undefined;
  let namespace: string | undefined;

  /** This object's own prefix for observation ids, so another object's entry ids never collide. */
  const sourceNamespace = async () => {
    namespace ??= await deps.storage.transaction(async (tx) => {
      const existing = await tx.get<string>("memorySourceNamespace");
      if (existing) return existing;
      const value = crypto.randomUUID();
      await tx.put("memorySourceNamespace", value);
      return value;
    });
    return namespace;
  };

  const schedule = (time = Date.now() + retryAfter, failures = 0) =>
    deps.jobs.push({
      id: "memory",
      fn: "memory",
      payload: { failures },
      time,
      retry: { maxAttempts: 1 },
      singleflight: true,
      hungTimeoutSeconds: 120,
    });

  /** One catch-up and consolidation pass; work always goes first. */
  async function maintain() {
    if (!(await deps.active())) return;
    if ((await deps.harness.pending()).some((item) => item.status === "running"))
      return { rescheduleAt: Date.now() + retryAfter };
    const controller = new AbortController();
    running = controller;
    try {
      const memory = deps.memory(controller.signal);
      const pi = await deps.harness.pi();
      const sessions = [ROOT_SESSION, ...(await deps.sessions.all()).values()];
      // Pi allocates entry ids across every conversation, so one cursor orders all sessions.
      const more = await catchUpMemory(
        memory,
        (min, max, limit) =>
          pi.commit(async (tx) => {
            const entries = [];
            for (const session of sessions) {
              const page = await tx.scanEntries(
                {
                  conversationId: conversationOf(session),
                  minEntryId: min as EntryId,
                  ...(max === undefined ? {} : { maxEntryId: max as EntryId }),
                },
                limit,
              );
              entries.push(...page.items);
            }
            return entries.sort((a, b) => Number(b.id) - Number(a.id)).slice(0, limit);
          }, BACKGROUND_CONTEXT),
        await sourceNamespace(),
      );
      const result = await Effect.runPromise(memory.maintain({ maxSources: 4 }));
      await schedule(Date.now() + (more || result.more ? retryAfter : 24 * 60 * 60 * 1000));
      return;
    } catch (error) {
      if (controller.signal.aborted) return { rescheduleAt: Date.now() + retryAfter };
      throw error;
    } finally {
      if (running === controller) running = undefined;
    }
  }

  /** A failed pass is retried twice, five and ten minutes later; the next input re-arms it. */
  async function failed(job: LifecycleJob) {
    const failures =
      typeof job.payload === "object" &&
      job.payload !== null &&
      "failures" in job.payload &&
      typeof job.payload.failures === "number"
        ? job.payload.failures + 1
        : 1;
    console.warn(
      failures >= 3
        ? "Memory maintenance paused after three failed passes; pending observations retained until the next input"
        : "Memory maintenance unavailable; pending observations retained for retry",
    );
    if (failures < 3) await schedule(Date.now() + failures * 5 * 60 * 1000, failures);
  }

  /** Stops a running pass so an input never waits behind it; the pass is rescheduled. */
  const yieldToWork = () => running?.abort();

  /** Business memory relevant to this turn's text. */
  async function context(query: string) {
    try {
      const result = await Effect.runPromise(deps.memory().context({ query, maxChars: 4000 }));
      return result.text;
    } catch {
      return "Business memory is temporarily unavailable. Do not claim to recall or save unsupported information.";
    }
  }

  /**
   * Records evidence for a tool's citation; memory being down never stops work. A missed
   * observation is caught up later, and only observed evidence is cited.
   */
  async function observe(evidence: Observation[]) {
    if (!evidence.length) return false;
    return Effect.runPromise(deps.memory().observe(evidence)).then(
      () => true,
      (error: unknown) => {
        console.warn("Devys memory observation failed", error);
        return false;
      },
    );
  }

  return { sourceNamespace, schedule, maintain, failed, yieldToWork, context, observe };
}

export type MemoryUpkeep = ReturnType<typeof memoryUpkeep>;
