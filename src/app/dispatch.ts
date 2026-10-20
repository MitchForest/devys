import { Effect } from "effect";
import type { Env } from "../../infra/api.ts";
import { workChat } from "../channels/work.ts";
import { scopeName } from "../identity/contract.ts";
import { activeEmployee } from "../identity/service.ts";
import { dueCommitments, markSubmitted } from "../work/service.ts";
import { spaces } from "../work/spaces.ts";
import { postEvent } from "./conversations.ts";

/**
 * Hands ready work to its employee. The operation id is `<commitment>:<revision>`, so a
 * lost response is simply resubmitted and Pi admits it once. Paused employees wait.
 */
export async function dispatchDue(env: Env) {
  for (const work of await Effect.runPromise(dueCommitments(env.HYPERDRIVE))) {
    const scope = { businessId: work.business_id, employeeId: work.owner_employee_id };
    const employee = await Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope));
    if (!employee || employee.paused) continue;
    // A hand-off card in the work item's thread and in every space that shows it, once per owner.
    const card = {
      clientId: `handoff:${work.id}:${employee.id}`,
      text: `${employee.name} took on "${work.title}".`,
      ref: work.id,
    };
    await postEvent(env, work.business_id, `work:${work.id}`, card);
    for (const space of await Effect.runPromise(spaces(env.HYPERDRIVE, work.business_id)))
      if (space.items.some((item) => item.kind === "commitment" && item.ref === work.id))
        await postEvent(env, work.business_id, `space:${space.id}`, {
          ...card,
          clientId: `${card.clientId}:${space.id}`,
        });
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
}
