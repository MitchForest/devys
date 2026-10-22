import type { Env } from "./env.ts";
import type { MemoryFactory } from "../memory/contract.ts";
import { memoryFor } from "./memory.ts";
import { modeOf } from "./mode.ts";
import { browserCapabilities } from "../browser/capabilities.ts";
import { hiring } from "./team.ts";
import { coordinates } from "../identity/team.ts";
import { appSearchCapabilities, teamCapabilities } from "../identity/capabilities.ts";
import { memoryCapabilities } from "../memory/capabilities.ts";
import { googleConnection } from "../connections/google.ts";
import { workspaceCapabilities } from "../workspace/capabilities.ts";
import { artifactCapabilities, driveCapabilities } from "../apps/documents/capabilities.ts";
import { postEvent } from "./conversations.ts";
import { conversationCapabilities } from "../conversations/capabilities.ts";
import { conversationKey } from "../conversations/contract.ts";
import { publicCapabilities } from "../egress/capabilities.ts";
import { workCapabilities } from "../work/capabilities.ts";
import { activeEmployee, employeesOf } from "../identity/service.ts";
import { Effect } from "effect";
import { codingCapabilities } from "../apps/code/capabilities.ts";
import { codingIncomplete, codingDependencies } from "./coding.ts";
import type { Capability } from "../protocol/capability.ts";
import { appCatalog, appSkills, builtInDirectory } from "./apps.ts";
import { keepable } from "./projects.ts";
import { artifactUrl } from "./artifacts.ts";
import { askOwnerConnecting, searchApps } from "./remote-apps.ts";
import { connectionVault, filling } from "./vault.ts";
/** Composition only: implementations and SQL belong to their domains. */
export function capabilities(
  env: Env,
  memory: MemoryFactory = (owner) => memoryFor(env, owner),
): Capability[] {
  const runner = modeOf(env).runner();
  const catalog = [
    ...driveCapabilities({
      db: env.HYPERDRIVE,
      connection: googleConnection(env, connectionVault(env)),
    }),
    ...publicCapabilities(env),
    ...memoryCapabilities(memory),
    ...conversationCapabilities(env.HYPERDRIVE, (businessId) =>
      Effect.runPromise(employeesOf(env.HYPERDRIVE, businessId)),
    ),
    ...workspaceCapabilities(runner, (businessId) => appSkills(env.HYPERDRIVE, businessId)),
    ...artifactCapabilities(
      env,
      runner,
      async (invocation, card) => {
        // The card goes where the employee is answering; a page made elsewhere goes to its DM.
        const key = conversationKey(invocation.conversation ?? `direct:${invocation.employeeId}`);
        if (key) await postEvent(env, invocation.businessId, key, card);
      },
      (businessId, id) => artifactUrl(env, businessId, id),
    ),
    ...codingCapabilities(codingDependencies(env)),
    ...browserCapabilities(modeOf(env).browser, env.LOADER, filling(env)),
    ...workCapabilities(
      env.HYPERDRIVE,
      async (businessId, employeeId) =>
        Boolean(
          await Effect.runPromise(activeEmployee(env.HYPERDRIVE, { businessId, employeeId })),
        ),
      (businessId, ref) => keepable(env, businessId, ref),
      (businessId, work) => codingIncomplete(env, businessId, work),
      (businessId, employeeId) => coordinates(env.HYPERDRIVE, { businessId, employeeId }),
      (asking, request) => askOwnerConnecting(env, asking, request, appCatalog),
    ),
    ...appSearchCapabilities(async (businessId, query) =>
      searchApps(env, businessId, query, await builtInDirectory(env, businessId)),
    ),
  ];
  return [
    ...catalog,
    ...teamCapabilities(
      env.HYPERDRIVE,
      hiring(() => capabilities(env, memory)),
    ),
  ];
}
