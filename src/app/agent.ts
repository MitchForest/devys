import { Effect } from "effect";
import type { Env } from "./env.ts";
import { grantsFor } from "../authority/service.ts";
import { authorize } from "./authorize.ts";
import { usableIn } from "./apps.ts";
import { activeEmployee, businessBrief, businessName, employeesOf } from "../identity/service.ts";
import { roleTemplate } from "./team.ts";
import { AgentRuntime, type AgentDependencies } from "../runtime/agent.ts";
import { capabilities } from "./capabilities.ts";
import { channelFor } from "./channel.ts";
import { memoryFor } from "./memory.ts";
import { applicationModels, modelChoice } from "./models.ts";
import { modeOf } from "./mode.ts";
import { interruptAssignments } from "./delegates.ts";

/** The only production selection of the employee runtime's adapters. */
export function agentDependencies(env: Env): AgentDependencies {
  return {
    capabilities: capabilities(env),
    runner: modeOf(env).runner(),
    interruptDelegates: (scope) => interruptAssignments(env, scope),
    workplace: modeOf(env).workplace,
    channel: channelFor(env),
    memory: (businessId, signal) => memoryFor(env, businessId, signal),
    employee: async (scope) => {
      const [employee, business, brief, team] = await Promise.all([
        Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope)),
        Effect.runPromise(businessName(env.HYPERDRIVE, scope.businessId)),
        Effect.runPromise(businessBrief(env.HYPERDRIVE, scope.businessId)),
        Effect.runPromise(employeesOf(env.HYPERDRIVE, scope.businessId)),
      ]);
      return employee && business
        ? {
            name: employee.name,
            role: employee.role,
            businessName: business,
            brief,
            paused: employee.paused,
            colleagues: team
              .filter((colleague) => colleague.id !== employee.id)
              .map(
                (colleague) =>
                  `${colleague.name} (${roleTemplate(colleague.template)?.summary || colleague.role.slice(0, 120)})`,
              ),
          }
        : undefined;
    },
    authorize: (scope, capability, input, context) =>
      authorize(env, scope, capability, input, context),
    // An uninstalled app's capabilities are not discovered, whatever is granted.
    granted: async (scope) => {
      const usable = await usableIn(env.HYPERDRIVE, scope.businessId);
      return (await Effect.runPromise(grantsFor(env.HYPERDRIVE, scope)))
        .map((grant) => grant.capability)
        .filter(usable);
    },
    models: (beforeDispatch) => applicationModels(env, beforeDispatch),
    // Resolved at admission so a configuration typo cannot disable stop/status.
    foregroundModel: async (scope) => {
      const employee = await Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope));
      if (!employee) throw new Error("Employee access revoked");
      return modelChoice(employee.model);
    },
  };
}

export class DevysAgent extends AgentRuntime<Env> {
  protected dependencies() {
    return agentDependencies(this.env);
  }
}
