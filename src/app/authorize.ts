import { Effect, Schema } from "effect";
import type { Env } from "./env.ts";
import type { Outcome } from "../authority/contract.ts";
import { activeGrant, decide, settleAsk } from "../authority/service.ts";
import type { Scope } from "../identity/contract.ts";
import type { Capability } from "../protocol/capability.ts";
import { workItem } from "../work/service.ts";
import { usableIn } from "./apps.ts";

/**
 * The one authorization path: the app gate, the work item's fence and conditions, then the grant.
 * An `ask` uses an approved decision for this exact request once, or opens one.
 */
export async function authorize(
  env: Pick<Env, "HYPERDRIVE">,
  scope: Scope,
  capability: Capability,
  input: unknown,
  context: { workItemId?: string; conversation?: string } = {},
): Promise<Outcome> {
  const { workItemId, conversation } = context;
  if (!(await usableIn(env.HYPERDRIVE, scope.businessId))(capability.name))
    return {
      outcome: "deny",
      reason: `${capability.name} belongs to an app this business hasn't installed`,
    };
  if (workItemId) {
    const work = await Effect.runPromise(workItem(env.HYPERDRIVE, scope.businessId, workItemId));
    // Completed work stays reachable so a conversation in its thread can reopen it.
    if (!work || work.taken_over_by || work.state === "cancelled")
      return { outcome: "deny", reason: "That work was taken over or cancelled" };
    const conditions = work.conditions[capability.name];
    if (conditions && !withinConditions(capability, conditions, input))
      return {
        outcome: "deny",
        reason: `Outside this work item's conditions for ${capability.name}`,
      };
  }
  const decision = decide(
    await Effect.runPromise(activeGrant(env.HYPERDRIVE, scope, capability.name)),
    capability,
    input,
  );
  if (decision.outcome !== "ask") return decision;
  return Effect.runPromise(
    settleAsk(env.HYPERDRIVE, scope, {
      grantId: decision.grantId,
      capability: capability.name,
      input,
      ...(workItemId ? { workItemId } : {}),
      ...(conversation ? { conversation } : {}),
    }),
  );
}

function withinConditions(capability: Capability, conditions: unknown, input: unknown) {
  if (!capability.constraints) return false;
  try {
    return capability.constraints.allows(
      Schema.decodeUnknownSync(capability.constraints.schema)(conditions),
      input,
    );
  } catch {
    return false;
  }
}
