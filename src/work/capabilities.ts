import { Effect, Schema } from "effect";
import type { Database } from "../data/database.ts";
import { capability, CapabilityError, Invocation } from "../protocol/capability.ts";
import type { Commitment } from "./contract.ts";
import {
  commitment,
  commitments,
  createCommitment,
  updateCommitment,
  type Change,
} from "./service.ts";
import { addToSpace, createSpace, spaces } from "./spaces.ts";

const Id = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(64));
const Line = (max: number) => Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(max));
const When = Schema.String.check(Schema.makeFilter((value) => Number.isFinite(Date.parse(value))));
const Summary = Schema.Struct({
  id: Schema.String,
  title: Schema.String,
  state: Schema.String,
  owner: Schema.String,
  nextAction: Schema.String,
  waitCondition: Schema.NullOr(Schema.String),
  dueAt: Schema.NullOr(Schema.String),
  revision: Schema.Number,
  takenOver: Schema.Boolean,
});
const summary = (item: Commitment) => ({
  id: item.id,
  title: item.title,
  state: item.state,
  owner: item.owner_employee_id,
  nextAction: item.next_action,
  waitCondition: item.wait_condition,
  dueAt: item.due_at,
  revision: item.revision,
  takenOver: item.taken_over_by !== null,
});

const run = <A>(effect: Effect.Effect<A, unknown>) =>
  effect.pipe(
    Effect.mapError(
      () => new CapabilityError({ code: "unavailable", message: "Work records are unavailable" }),
    ),
  );

/** The business's durable work, operated by employees through the same rules as people. */
export function workCapabilities(
  db: Database,
  employeeIn: (businessId: string, employeeId: string) => Promise<boolean>,
  artifactIn: (businessId: string, artifactId: string) => Promise<boolean>,
  /** Why this work cannot be completed yet (such as a coding check that has not passed). */
  completionBlocked: (businessId: string, work: Commitment) => Promise<string | undefined>,
) {
  const change = (id: string, expectedRevision: number, value: Change) =>
    Effect.gen(function* () {
      const { businessId, employeeId } = yield* Invocation;
      const updated = yield* run(
        updateCommitment(db, businessId, id, expectedRevision, value, {
          kind: "employee",
          id: employeeId,
        }),
      );
      if (!updated)
        return yield* new CapabilityError({
          code: "conflict",
          message: "The commitment changed or was taken over; list it again",
        });
      return summary(updated);
    });
  return [
    capability({
      name: "commitmentList",
      description:
        "List the business's commitments: what is owed, who is accountable, the next action and state. Read before changing one; changes need its current revision.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({ openOnly: Schema.optional(Schema.Boolean) }),
      output: Schema.Struct({ commitments: Schema.Array(Summary) }),
      execute: ({ openOnly }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          const items = yield* run(commitments(db, businessId));
          return {
            commitments: items
              .filter((item) => !openOnly || !["completed", "cancelled"].includes(item.state))
              .map(summary),
          };
        }),
    }),
    capability({
      name: "commitmentCreate",
      description:
        "Record something the business owes: a title, objective and next action, accountable to you or another employee. Use for work that outlives this conversation.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        title: Line(200),
        objective: Schema.optional(Schema.String.check(Schema.isMaxLength(4000))),
        nextAction: Schema.optional(Schema.String.check(Schema.isMaxLength(1000))),
        owner: Schema.optional(Id),
        dueAt: Schema.optional(When),
      }),
      output: Summary,
      execute: (input) =>
        Effect.gen(function* () {
          const { businessId, employeeId } = yield* Invocation;
          const owner = input.owner ?? employeeId;
          if (!(yield* Effect.promise(() => employeeIn(businessId, owner))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "The accountable employee isn't part of this business",
            });
          return summary(
            yield* run(
              createCommitment(db, businessId, {
                owner,
                title: input.title,
                ...(input.objective ? { objective: input.objective } : {}),
                ...(input.nextAction ? { nextAction: input.nextAction } : {}),
                ...(input.dueAt ? { dueAt: new Date(input.dueAt).toISOString() } : {}),
                createdBy: `employee:${employeeId}`,
              }),
            ),
          );
        }),
    }),
    capability({
      name: "commitmentUpdate",
      description:
        "Update a commitment at its current revision: the next action, its state (ready, in_progress, waiting, needs_decision, cancelled), what it waits on, or its due date.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        id: Id,
        expectedRevision: Schema.Int,
        state: Schema.optional(
          Schema.Literals(["ready", "in_progress", "waiting", "needs_decision", "cancelled"]),
        ),
        nextAction: Schema.optional(Schema.String.check(Schema.isMaxLength(1000))),
        waitCondition: Schema.optional(
          Schema.NullOr(Schema.String.check(Schema.isMaxLength(1000))),
        ),
        dueAt: Schema.optional(Schema.NullOr(When)),
      }),
      output: Summary,
      execute: ({ id, expectedRevision, state, nextAction, waitCondition, dueAt }) =>
        change(id, expectedRevision, {
          ...(state ? { state } : {}),
          ...(nextAction !== undefined ? { nextAction } : {}),
          ...(waitCondition !== undefined ? { waitCondition } : {}),
          ...(dueAt !== undefined ? { dueAt: dueAt && new Date(dueAt).toISOString() } : {}),
        }),
    }),
    capability({
      name: "commitmentComplete",
      description:
        "Mark a commitment completed, at its current revision, with evidence: what was done and where to see it. Saying 'done' in chat does not complete work.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ id: Id, expectedRevision: Schema.Int, evidence: Line(2000) }),
      output: Summary,
      execute: ({ id, expectedRevision, evidence }) =>
        Effect.gen(function* () {
          const { businessId, employeeId } = yield* Invocation;
          const work = yield* run(commitment(db, businessId, id));
          const blocked =
            work && (yield* run(Effect.promise(() => completionBlocked(businessId, work))));
          if (blocked) return yield* new CapabilityError({ code: "conflict", message: blocked });
          return yield* change(id, expectedRevision, {
            state: "completed",
            evidence: { by: `employee:${employeeId}`, note: evidence },
          });
        }),
    }),
    capability({
      name: "spaceList",
      description:
        "List the business's spaces (persistent places like Launch or Growth) and the commitments and files each one shows.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({}),
      output: Schema.Struct({
        spaces: Schema.Array(
          Schema.Struct({
            id: Schema.String,
            name: Schema.String,
            purpose: Schema.String,
            items: Schema.Array(
              Schema.Struct({ id: Schema.String, kind: Schema.String, ref: Schema.String }),
            ),
          }),
        ),
      }),
      execute: () =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          return { spaces: yield* run(spaces(db, businessId)) };
        }),
    }),
    capability({
      name: "spaceCreate",
      description:
        "Create a space: a persistent place for an area of the business, with a purpose.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        name: Line(80),
        purpose: Schema.optional(Schema.String.check(Schema.isMaxLength(500))),
      }),
      output: Schema.Struct({ id: Schema.String, name: Schema.String }),
      execute: ({ name, purpose }) =>
        Effect.gen(function* () {
          const { businessId, employeeId } = yield* Invocation;
          const space = yield* run(
            createSpace(db, businessId, {
              name,
              ...(purpose ? { purpose } : {}),
              lead: employeeId,
            }),
          );
          return { id: space.id, name: space.name };
        }),
    }),
    capability({
      name: "spaceAdd",
      description:
        "Show a commitment or a saved file in a space. It's a reference: the record keeps one home and can appear in several spaces.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        spaceId: Id,
        kind: Schema.Literals(["commitment", "artifact"]),
        ref: Id,
      }),
      output: Schema.Struct({ id: Schema.String }),
      execute: ({ spaceId, kind, ref }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          if (kind === "artifact" && !(yield* Effect.promise(() => artifactIn(businessId, ref))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such file in this business",
            });
          const item = yield* run(addToSpace(db, businessId, spaceId, { kind, ref }));
          if (!item)
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such space or commitment in this business",
            });
          return { id: item.id };
        }),
    }),
  ];
}
