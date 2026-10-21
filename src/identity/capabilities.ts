import { Effect, Schema } from "effect";
import type { Database } from "../data/database.ts";
import { capability, CapabilityError, Invocation } from "../protocol/capability.ts";
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
        template: Schema.Literals(["engineering", "growth", "business-operations", "custom"]),
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
