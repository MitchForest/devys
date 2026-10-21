import { Effect } from "effect";
import type { Env } from "./env.ts";
import { expireDecisions } from "../authority/service.ts";
import { workChat } from "../channels/work.ts";
import { scopeName } from "../identity/contract.ts";
import { activeEmployee, unavailableEmployees } from "../identity/service.ts";
import type { Commitment } from "../work/contract.ts";
import { dueCommitments, markSubmitted } from "../work/service.ts";
import { postEvent } from "./conversations.ts";

/** The minute tick: unanswered decisions expire, then ready work is handed over. */
export async function minuteTick(env: Env) {
  await Effect.runPromise(expireDecisions(env.HYPERDRIVE)).catch((error: unknown) =>
    console.error("Expiring decisions failed:", error),
  );
  await dispatchDue(env);
}

/**
 * Hands ready work to its employee. The operation id is `<commitment>:<revision>`, so a
 * lost response is simply resubmitted and Pi admits it once. Paused employees wait. One item
 * failing is logged and retried next minute without holding up the others.
 */
export async function dispatchDue(env: Env) {
  const skip = await Effect.runPromise(unavailableEmployees(env.HYPERDRIVE));
  for (const work of await Effect.runPromise(dueCommitments(env.HYPERDRIVE, skip)))
    await handOver(env, work).catch((error: unknown) =>
      console.error(`Dispatching work ${work.id} failed:`, error),
    );
}

async function handOver(env: Env, work: Commitment & { business_id: string }) {
  const scope = { businessId: work.business_id, employeeId: work.owner_employee_id };
  const employee = await Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope));
  if (!employee || employee.paused) return;
  // A hand-off card in the work item's thread and in its project's channel, once per owner.
  const card = {
    clientId: `handoff:${work.id}:${employee.id}`,
    text: `${employee.name} took on "${work.title}".`,
    ref: work.id,
  };
  await postEvent(env, work.business_id, `work:${work.id}`, card);
  if (work.project_id) await postEvent(env, work.business_id, `project:${work.project_id}`, card);
  await env.AGENT.getByName(scopeName(scope)).receive(scope, {
    messageId: `${work.id}:${work.revision}`,
    senderId: "dispatcher",
    chatId: workChat(scope, work.id),
    text: [
      `Work on this commitment (id ${work.id}, revision ${work.revision}): ${work.title}.`,
      work.objective && `Objective: ${work.objective}`,
      work.next_action && `Next action: ${work.next_action}`,
      "When it's done, call commitmentComplete with evidence. If it's blocked, call commitmentUpdate with state waiting or needs_decision and what it waits on.",
    ]
      .filter(Boolean)
      .join("\n"),
  });
  await Effect.runPromise(markSubmitted(env.HYPERDRIVE, work.id, work.revision));
}
