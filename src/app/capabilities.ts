import type { Env } from "../../infra/api.ts";
import type { MemoryFactory } from "../memory/contract.ts";
import { memoryFor } from "./memory.ts";
import { runnerFor } from "./runner.ts";
import { teamCapabilities } from "./team.ts";
import { memoryCapabilities } from "../memory/capabilities.ts";
import { driveCapabilities } from "../connections/capabilities.ts";
import { workspaceCapabilities } from "../workspace/capabilities.ts";
import { artifactCapabilities } from "../artifacts/capabilities.ts";
import { conversationCapabilities } from "./conversations.ts";
import { publicCapabilities } from "../egress/capabilities.ts";
import { workCapabilities } from "../work/capabilities.ts";
import { activeEmployee } from "../identity/service.ts";
import { artifactLocation } from "../artifacts/service.ts";
import { Effect } from "effect";
import { delegateCapabilities } from "../delegates/capabilities.ts";
import { codingIncomplete, delegateDependencies } from "./delegates.ts";
import type { Capability } from "../protocol/capability.ts";
/** Composition only: implementations and SQL belong to their domains. */
export function capabilities(
  env: Env,
  memory: MemoryFactory = (owner) => memoryFor(env, owner),
): Capability[] {
  const runner = runnerFor(env);
  const catalog = [
    ...driveCapabilities(env),
    ...publicCapabilities(env),
    ...memoryCapabilities(memory),
    ...conversationCapabilities(env),
    ...workspaceCapabilities(runner),
    ...artifactCapabilities(env, runner),
    ...delegateCapabilities(delegateDependencies(env)),
    ...workCapabilities(
      env.HYPERDRIVE,
      async (businessId, employeeId) =>
        Boolean(
          await Effect.runPromise(activeEmployee(env.HYPERDRIVE, { businessId, employeeId })),
        ),
      async (businessId, artifactId) =>
        Boolean(await Effect.runPromise(artifactLocation(env.HYPERDRIVE, businessId, artifactId))),
      (businessId, work) => codingIncomplete(env, businessId, work),
    ),
  ];
  return [...catalog, ...teamCapabilities(env, () => capabilities(env, memory))];
}
