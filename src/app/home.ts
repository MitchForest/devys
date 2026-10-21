import { Effect } from "effect";
import type { Env } from "./env.ts";
import { pendingDecisions } from "../authority/service.ts";
import { postMessage, readAt } from "../conversations/service.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { employeesOf } from "../identity/service.ts";
import type { Commitment } from "../work/contract.ts";
import { commitments } from "../work/service.ts";

const hour = 3_600_000;
/** Waiting this long without a change, or past its due date, waiting work is stuck. */
const stuckAfter = 24 * hour;
/** The owner gets a briefing when they return after this long. */
const awayFor = 8 * hour;

const stuck = (item: Commitment, now: number) =>
  item.state === "waiting" &&
  ((item.due_at !== null && Date.parse(item.due_at) < now) ||
    Date.parse(item.updated_at) < now - stuckAfter);

/** A work item as Home shows it, with what a client needs to open its thread. */
const card = (item: Commitment) => ({
  id: item.id,
  title: item.title,
  employeeId: item.owner_employee_id,
  projectId: item.project_id,
  conversation: `work:${item.id}`,
  state: item.state,
  waitCondition: item.wait_condition,
  dueAt: item.due_at,
  updatedAt: item.updated_at,
});

/** `"A", "B" and 3 more`. */
function titles(items: readonly Commitment[]) {
  const shown = items.slice(0, 5).map((item) => `"${item.title}"`);
  return items.length > 5 ? `${shown.join(", ")} and ${items.length - 5} more` : shown.join(", ");
}

/**
 * Operations' briefing, composed from records: what got done, started and became stuck since
 * the owner last read their direct chat. Nothing when nothing happened.
 */
export function briefing(work: readonly Commitment[], since: string, now: number) {
  const after = (at: string | null) => at !== null && at > since;
  const done = work.filter((item) => item.state === "completed" && after(item.updated_at));
  const moving = work.filter((item) => item.state === "in_progress" && after(item.updated_at));
  const blocked = work.filter(
    (item) =>
      stuck(item, now) &&
      (after(item.updated_at) || (after(item.due_at) && Date.parse(item.due_at!) < now)),
  );
  // Spending is not recorded yet, so the briefing has no cost line.
  const lines = [
    done.length && `Done: ${titles(done)}.`,
    moving.length && `Moving: ${titles(moving)}.`,
    blocked.length && `Stuck: ${titles(blocked)}.`,
  ].filter(Boolean);
  return lines.length ? ["While you were away:", ...lines].join("\n") : undefined;
}

/**
 * The owner's Home: what needs them and the business at a glance. Opening it after a while
 * away posts Operations' briefing in their direct chat, once per return; it wakes nobody.
 */
export async function homeRoute(
  env: Env,
  access: { person: Person; business: Business; trusted: boolean },
) {
  const { person, business, trusted } = access;
  const [decisions, work, employees] = await Promise.all([
    Effect.runPromise(pendingDecisions(env.HYPERDRIVE, business.id)),
    Effect.runPromise(commitments(env.HYPERDRIVE, business.id)),
    Effect.runPromise(employeesOf(env.HYPERDRIVE, business.id)),
  ]);
  const now = Date.now();
  const workOf = (id: string | null) => work.find((item) => item.id === id);
  const asked = new Set(decisions.map((decision) => decision.commitment_id));
  const needsYou = [
    ...decisions.map((decision) => {
      const item = workOf(decision.commitment_id);
      return {
        kind: "decision" as const,
        id: decision.id,
        title: item?.title ?? decision.capability,
        employeeId: decision.employee_id,
        conversation: decision.conversation,
        workId: decision.commitment_id,
        projectId: item?.project_id ?? null,
        at: decision.requested_at,
        capability: decision.capability,
        input: decision.input,
        expiresAt: decision.expires_at,
      };
    }),
    // Work waiting on the owner's decision, unless a request above already stands for it.
    ...work
      .filter((item) => item.state === "needs_decision" && !asked.has(item.id))
      .map((item) => ({
        kind: "work" as const,
        ...card(item),
        workId: item.id,
        at: item.updated_at,
      })),
  ];
  const operations = employees.find((employee) => employee.template === "operations");
  const key = operations ? (`direct:${operations.id}` as const) : undefined;
  const since = key
    ? await Effect.runPromise(readAt(env.HYPERDRIVE, business.id, key, `person:${person.id}`))
    : undefined;
  // Only a same-origin or signed-in-device request writes it, as with every other write.
  const text =
    trusted && since && now - Date.parse(since) > awayFor ? briefing(work, since, now) : undefined;
  const posted =
    key && text
      ? await Effect.runPromise(
          // Stored, not delivered: no employee turn starts. One per last-read hour.
          postMessage(env.HYPERDRIVE, business.id, key, {
            author: `employee:${operations!.id}`,
            text,
            clientId: `briefing:${since!.slice(0, 13).replace("T", "-")}`,
          }),
        )
      : undefined;
  return Response.json({
    needsYou,
    glance: {
      moving: work.filter((item) => item.state === "in_progress").map(card),
      stuck: work.filter((item) => stuck(item, now)).map(card),
      spentCents: null,
    },
    since: since ?? null,
    briefing: posted?.message ?? null,
  });
}
