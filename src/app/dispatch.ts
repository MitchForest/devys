import { Effect } from "effect";
import type { Env } from "./env.ts";
import { ref } from "../protocol/ref.ts";
import { expireDecisions } from "../authority/service.ts";
import { workChat } from "../channels/work.ts";
import { scopeName } from "../identity/contract.ts";
import { activeEmployee, pausedEmployees } from "../identity/service.ts";
import type { WorkItem } from "../work/contract.ts";
import { readyWorkItems, markSubmitted, wakeFollowUps } from "../work/service.ts";
import { postEvent } from "./conversations.ts";
import { dispatchRoutines } from "./routines.ts";

/**
 * The minute tick: unanswered decisions expire, follow-ups whose time came become ready, ready
 * work is handed over, and due routines run. Wiring only: Pi's idempotent submit by operation
 * id is the dedupe, so a repeated tick changes nothing.
 */
export async function minuteTick(env: Env) {
  await Effect.runPromise(expireDecisions(env.HYPERDRIVE)).catch((error: unknown) =>
    console.error("Expiring decisions failed:", error),
  );
  await Effect.runPromise(wakeFollowUps(env.HYPERDRIVE)).catch((error: unknown) =>
    console.error("Waking follow-ups failed:", error),
  );
  await dispatchReady(env);
  await dispatchRoutines(env).catch((error: unknown) =>
    console.error("Running routines failed:", error),
  );
}

/**
 * Hands ready work to its employee. The operation id is `<workItem>:<revision>`, so a
 * lost response is simply resubmitted and Pi admits it once. Paused employees wait. One item
 * failing is logged and retried next minute without holding up the others.
 */
export async function dispatchReady(env: Env) {
  const paused = await Effect.runPromise(pausedEmployees(env.HYPERDRIVE));
  for (const work of await Effect.runPromise(readyWorkItems(env.HYPERDRIVE, paused)))
    await handOver(env, work).catch((error: unknown) =>
      console.error(`Dispatching work ${work.id} failed:`, error),
    );
}

async function handOver(env: Env, work: WorkItem & { business_id: string }) {
  const scope = { businessId: work.business_id, employeeId: work.owner_employee_id };
  const employee = await Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope));
  if (!employee || employee.paused) return;
  // A hand-off card in the work item's thread and in its project's channel, once per owner.
  const card = {
    clientId: `handoff:${work.id}:${employee.id}`,
    text: `${employee.name} took on "${work.title}".`,
    ref: ref("work", "item", work.id),
  };
  await postEvent(env, work.business_id, `work:${work.id}`, card);
  if (work.project_id) await postEvent(env, work.business_id, `project:${work.project_id}`, card);
  await env.AGENT.getByName(scopeName(scope)).receive(scope, {
    messageId: `${work.id}:${work.revision}`,
    senderId: "dispatcher",
    chatId: workChat(scope, work.id),
    text: [
      `Work on this work item (${ref("work", "item", work.id)}, revision ${work.revision}): ${work.title}.`,
      work.objective && `Objective: ${work.objective}`,
      work.next_action && `Next action: ${work.next_action}`,
      work.wait_condition && `It was waiting on: ${work.wait_condition}`,
      "When it's done, call workComplete with evidence. If it's blocked, call workUpdate with state waiting or needs_decision and what it waits on.",
    ]
      .filter(Boolean)
      .join("\n"),
  });
  await Effect.runPromise(markSubmitted(env.HYPERDRIVE, work.id, work.revision));
}
