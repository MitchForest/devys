import { Effect } from "effect";
import type { Env } from "../../infra/api.ts";
import { grantsFor } from "../authority/service.ts";
import { authorize } from "./authorize.ts";
import { activeEmployee, businessBrief, businessName, employeesOf } from "../identity/service.ts";
import { roleTemplate } from "./team.ts";
import { AgentRuntime, type AgentDependencies } from "../runtime/agent.ts";
import { capabilities } from "./capabilities.ts";
import { channelFor } from "./channel.ts";
import { memoryFor } from "./memory.ts";
import { applicationModels, modelChoice } from "./models.ts";
import { runnerFor, workplaceFor } from "./runner.ts";
import { interruptAssignments } from "./delegates.ts";

/** The only production selection of the employee runtime's adapters. */
export function agentDependencies(env: Env): AgentDependencies {
  return {
    capabilities: capabilities(env),
    runner: runnerFor(env),
    interruptDelegates: (scope) => interruptAssignments(env, scope),
    workplace: workplaceFor(env),
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
    granted: async (scope) =>
      (await Effect.runPromise(grantsFor(env.HYPERDRIVE, scope))).map((grant) => grant.capability),
    models: (beforeDispatch) => applicationModels(env, beforeDispatch),
    // Resolved at admission so a configuration typo cannot disable stop/status.
    foregroundModel: async (scope) => {
      const employee = await Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope));
      if (!employee) throw new Error("Employee access revoked");
      return modelChoice(employee.model);
    },
  };
}

export class DevysAgent extends AgentRuntime {
  protected dependencies() {
    return agentDependencies(this.env);
  }
}
