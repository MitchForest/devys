import type { PiHarness } from "agents/harness/pi";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import {
  AssistantEntry,
  type Cursor,
  type EntryId,
  type EntryRecord,
  type SubmissionRecord,
} from "@earendil-works/pi-durable";
import type { ToolCall } from "@earendil-works/pi-ai";
import type { Worked } from "../conversations/contract.ts";
import type { Capability } from "../protocol/capability.ts";
import { conversationOf } from "./sessions.ts";

/** The most entries one turn is read back through: a long browser run stays well within it. */
const turnLimit = 1_000;

/**
 * The owner's words for what an employee does, from Pi's record of its turns: each capability's
 * own phrase, never a command, path, id or tool name. Remote apps' capabilities are looked up
 * only when a turn used one.
 */
export function activity(contracts: readonly Capability[], remote: () => Promise<Capability[]>) {
  const builtIn = new Map(contracts.map((contract) => [contract.name, contract]));

  /** The phrase for each call, in order. */
  async function phrases(calls: readonly ToolCall[]) {
    const names = calls.flatMap(namesIn);
    const known = names.every((name) => builtIn.has(name) || name === "describe_capabilities")
      ? builtIn
      : new Map([...builtIn, ...(await remote()).map((each) => [each.name, each] as const)]);
    return calls.map((call) => {
      if (call.name === "describe_capabilities") return "Looking through its apps";
      if (call.name !== "execute")
        return known.get(call.name)?.activity(call.arguments) ?? "Working";
      // A program: the first capability it calls says what it is for.
      const first = namesIn(call)
        .map((name) => known.get(name))
        .find(Boolean);
      return first?.activity() ?? "Working";
    });
  }

  /** What the employee is doing in its turn now: the call it's making, or thinking. */
  async function doing(entries: readonly EntryRecord[]) {
    const latest = entries.at(-1);
    const calls = AssistantEntry.is(latest) ? callsOf(latest) : [];
    return calls.length ? (await phrases(calls)).at(-1)! : "Thinking";
  }

  /**
   * The steps a finished turn took, a run of the same phrase counted once, and how long it took
   * from the input to its last entry.
   */
  async function worked(entries: readonly EntryRecord[]): Promise<{ steps: string[]; ms: number }> {
    const all = await phrases(entries.flatMap((entry) => callsOf(entry)));
    const steps = all.filter((phrase, index) => phrase !== all[index - 1]);
    const times = entries.map(timeOf).filter((time) => time !== undefined);
    return { steps, ms: times.length ? Math.max(0, times.at(-1)! - times[0]!) : 0 };
  }

  return { doing, worked };
}

/** A turn's summary for the reply that ends it, when it did anything beyond thinking. */
export const workedOf = ({ steps, ms }: { steps: string[]; ms: number }): Worked | undefined =>
  steps.length ? { ms, steps: steps.length } : undefined;

/**
 * Pi's entries for a turn and the follow-up asking for its reply (when there is one), oldest
 * first: from its input to its answer, or to now while it runs. `newest` reads only that many of
 * the latest.
 */
export async function turnEntries(
  harness: PiHarness,
  session: string,
  operationIds: readonly string[],
  newest = turnLimit,
) {
  const pi = await harness.pi();
  const conversationId = conversationOf(session);
  const submissions = (
    await Promise.all(
      operationIds.map((id) =>
        pi.commit((tx) => tx.submissionByRequest(conversationId, id), BACKGROUND_CONTEXT),
      ),
    )
  ).filter((submission): submission is SubmissionRecord => submission !== undefined);
  const first = submissions[0]?.entry;
  if (first === undefined) return [];
  const last = submissions.at(-1)!;
  const end = last.status === "done" ? last.answer : undefined;
  const entries: EntryRecord[] = [];
  let cursor: Cursor | undefined;
  do {
    const after = cursor;
    const page = await pi.commit(
      (tx) =>
        tx.scanEntries(
          { conversationId, minEntryId: first, ...(end === undefined ? {} : { maxEntryId: end }) },
          Math.min(200, newest - entries.length),
          after,
        ),
      BACKGROUND_CONTEXT,
    );
    entries.push(...page.items);
    cursor = page.next;
  } while (cursor !== undefined && entries.length < newest);
  return entries.toSorted((a, b) => Number(a.id as EntryId) - Number(b.id as EntryId));
}

const callsOf = (entry: EntryRecord): ToolCall[] => {
  const message = AssistantEntry.is(entry) ? entry.model?.[0] : undefined;
  return message?.role === "assistant"
    ? message.content.filter((part): part is ToolCall => part.type === "toolCall")
    : [];
};

/** The capabilities a call uses: its own name, or those a program calls as `codemode.<name>`. */
const namesIn = (call: ToolCall) =>
  call.name === "execute"
    ? [...String(call.arguments.code ?? "").matchAll(/codemode\.(\w+)\s*\(/g)].map((m) => m[1]!)
    : [call.name];

const timeOf = (entry: EntryRecord) => {
  const message = entry.model?.[0];
  return message && "timestamp" in message ? message.timestamp : undefined;
};
