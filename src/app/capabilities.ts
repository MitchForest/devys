import type { Env } from "./env.ts";
import type { MemoryFactory } from "../memory/contract.ts";
import { memoryFor } from "./memory.ts";
import { modeOf } from "./mode.ts";
import { browserCapabilities } from "../browser/capabilities.ts";
import { coordinates, teamCapabilities } from "./team.ts";
import { memoryCapabilities } from "../memory/capabilities.ts";
import { driveCapabilities } from "../connections/capabilities.ts";
import { workspaceCapabilities } from "../workspace/capabilities.ts";
import { artifactCapabilities } from "../apps/documents/capabilities.ts";
import { conversationCapabilities, postEvent } from "./conversations.ts";
import { conversationKey } from "../conversations/contract.ts";
import { publicCapabilities } from "../egress/capabilities.ts";
import { workCapabilities } from "../work/capabilities.ts";
import { activeEmployee } from "../identity/service.ts";
import { Effect } from "effect";
import { codingCapabilities } from "../apps/code/capabilities.ts";
import { codingIncomplete, codingDependencies } from "./coding.ts";
import type { Capability } from "../protocol/capability.ts";
import { appSkills } from "./apps.ts";
import { keepable } from "./projects.ts";
/** Composition only: implementations and SQL belong to their domains. */
export function capabilities(
  env: Env,
  memory: MemoryFactory = (owner) => memoryFor(env, owner),
): Capability[] {
  const runner = modeOf(env).runner();
  const catalog = [
    ...driveCapabilities(env),
    ...publicCapabilities(env),
    ...memoryCapabilities(memory),
    ...conversationCapabilities(env),
    ...workspaceCapabilities(runner, (businessId) => appSkills(env.HYPERDRIVE, businessId)),
    ...artifactCapabilities(env, runner, async (invocation, card) => {
      // The card goes where the employee is answering; a page made elsewhere goes to its DM.
      const key = conversationKey(invocation.conversation ?? `direct:${invocation.employeeId}`);
      if (key) await postEvent(env, invocation.businessId, key, card);
    }),
    ...codingCapabilities(codingDependencies(env)),
    ...browserCapabilities(modeOf(env).browser),
    ...workCapabilities(
      env.HYPERDRIVE,
      async (businessId, employeeId) =>
        Boolean(
          await Effect.runPromise(activeEmployee(env.HYPERDRIVE, { businessId, employeeId })),
        ),
      (businessId, ref) => keepable(env, businessId, ref),
      (businessId, work) => codingIncomplete(env, businessId, work),
      (businessId, employeeId) => coordinates(env, { businessId, employeeId }),
    ),
  ];
  return [...catalog, ...teamCapabilities(env, () => capabilities(env, memory))];
}
