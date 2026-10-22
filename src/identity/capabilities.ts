import { Effect, Schema } from "effect";
import type { Database } from "../data/database.ts";
import { capability, CapabilityError, Invocation } from "../protocol/capability.ts";
import { HireableRoleId } from "../protocol/roles.ts";
import { FoundApp } from "../apps/contract.ts";
import { rpc } from "../protocol/rpc.ts";
import { hire, hireInput, type Hiring } from "./team.ts";

/**
 * The Team app's capability. Employees propose hires through it; Operations holds it in `ask`
 * mode, so a proposal becomes a decision and approving it lets the identical call through once.
 */
export function teamCapabilities(db: Database, hiring: Hiring) {
  return [
    capability({
      name: "hireEmployee",
      description:
        "Hire a new employee from a role template (engineering, growth, business-operations or custom) with a name, responsibilities and optionally a model id. The owner approves each hire.",
      effect: "change",
      // Each call hires someone new: after an interruption, list the team before trying again.
      replay: "reconcile",
      input: Schema.Struct({
        template: HireableRoleId,
        name: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(80)),
        responsibilities: Schema.optional(Schema.String.check(Schema.isMaxLength(2000))),
        model: Schema.optional(Schema.String.check(Schema.isMaxLength(120))),
      }),
      output: Schema.Struct({ id: Schema.String, name: Schema.String }),
      execute: (input) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          const checked = hireInput(input, hiring);
          if (typeof checked === "string")
            return yield* Effect.fail(
              new CapabilityError({ code: "invalid_input", message: checked }),
            );
          const employee = yield* Effect.tryPromise({
            try: () => hire(db, businessId, checked, hiring),
            catch: () =>
              new CapabilityError({ code: "unavailable", message: "Hiring failed; try again" }),
          });
          return { id: employee.id, name: employee.name };
        }),
    }),
  ];
}

/**
 * The Team app's `appSearch`: finding apps for the team by what they do or are called (the
 * business's apps and the MCP Registry, searched in wiring).
 */
export function appSearchCapabilities(
  search: (businessId: string, query: string) => Promise<FoundApp[]>,
) {
  return [
    capability({
      name: "appSearch",
      description:
        'Find apps for a job by name or what they do ("ramp", "accounting", "calendar"): the business\'s own apps and the public MCP Registry. An app that isn\'t on yet is connected by the owner: pass its `app` to askOwner {kind: "connect", app, why} in a work item\'s thread. When you know an app\'s MCP server address (https://…), askOwner connect takes that too.',
      effect: "read",
      replay: "read",
      core: true,
      input: Schema.Struct({
        query: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(200)),
      }),
      output: Schema.Struct({ apps: Schema.Array(FoundApp) }),
      execute: ({ query }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          return { apps: yield* rpc(() => search(businessId, query)) };
        }),
    }),
  ];
}
