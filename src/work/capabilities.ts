import { Effect, Schema } from "effect";
import type { Database } from "../data/database.ts";
import { stableId } from "../protocol/bytes.ts";
import { capability, CapabilityError, Invocation } from "../protocol/capability.ts";
import { rpc, stored } from "../protocol/rpc.ts";
import { Ref, ref } from "../protocol/ref.ts";
import type { Commitment, Project } from "./contract.ts";
import {
  commitment,
  commitments,
  createCommitment,
  updateCommitment,
  type Change,
} from "./service.ts";
import { addToProject, createProject, project, projects, updateProject } from "./projects.ts";

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
  projectId: Schema.NullOr(Schema.String),
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
  projectId: item.project_id,
});
const Day = Schema.String.check(
  Schema.makeFilter(
    (value) => /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value)),
  ),
);
const Budget = Schema.Struct({
  cents: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
  currency: Schema.String.check(Schema.isPattern(/^[A-Z]{3}$/)),
});
const Members = Schema.Array(Id).check(Schema.isMaxLength(50));

const ProjectView = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  goal: Schema.NullOr(Schema.String),
  deadline: Schema.NullOr(Schema.String),
  budget: Schema.NullOr(Schema.Struct({ cents: Schema.Number, currency: Schema.String })),
  lead: Schema.NullOr(Schema.String),
  members: Schema.Array(Schema.String),
  items: Schema.Array(Schema.Struct({ id: Schema.String, ref: Ref })),
});
const view = (item: Project) => ({
  id: item.id,
  name: item.name,
  goal: item.goal,
  deadline: item.deadline,
  budget: item.budget,
  lead: item.lead_employee_id,
  members: item.member_ids,
  items: item.items,
});

/** The business's durable work, operated by employees through the same rules as people. */
export function workCapabilities(
  db: Database,
  employeeIn: (businessId: string, employeeId: string) => Promise<boolean>,
  /** Whether a ref names a record of this business a project can show: an artifact or a file. */
  keepable: (businessId: string, ref: Ref) => Promise<boolean>,
  /** Why this work cannot be completed yet (such as a coding check that has not passed). */
  completionBlocked: (businessId: string, work: Commitment) => Promise<string | undefined>,
  /** Whether this employee directs others' work (the Head of Operations). */
  coordinates: (businessId: string, employeeId: string) => Promise<boolean>,
) {
  /** A work item is changed by its owner, or by Operations; others ask in its thread. */
  const ownWork = (id: string) =>
    Effect.gen(function* () {
      const { businessId, employeeId } = yield* Invocation;
      const work = yield* stored(commitment(db, businessId, id));
      if (!work)
        return yield* new CapabilityError({
          code: "invalid_input",
          message: "No such work item in this business",
        });
      if (
        work.owner_employee_id !== employeeId &&
        !(yield* rpc(() => coordinates(businessId, employeeId)))
      )
        return yield* new CapabilityError({
          code: "forbidden",
          message: "Another employee's work item: ask its owner in its thread.",
        });
      return work;
    });
  const change = (id: string, expectedRevision: number, value: Change) =>
    Effect.gen(function* () {
      const { businessId, employeeId } = yield* Invocation;
      yield* ownWork(id);
      const updated = yield* stored(
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
  const checkEmployees = (businessId: string, ids: readonly string[]) =>
    Effect.gen(function* () {
      for (const id of ids)
        if (!(yield* rpc(() => employeeIn(businessId, id))))
          return yield* new CapabilityError({
            code: "invalid_input",
            message: "Leads and members must be employees of this business",
          });
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
          const items = yield* stored(commitments(db, businessId));
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
        "Record something the business owes: a title, objective and next action, accountable to you or another employee, optionally in a project. Use for work that outlives this conversation.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        title: Line(200),
        objective: Schema.optional(Schema.String.check(Schema.isMaxLength(4000))),
        nextAction: Schema.optional(Schema.String.check(Schema.isMaxLength(1000))),
        owner: Schema.optional(Id),
        dueAt: Schema.optional(When),
        projectId: Schema.optional(Id),
      }),
      output: Schema.Struct({ ...Summary.fields, ref: Ref }),
      execute: (input) =>
        Effect.gen(function* () {
          const { businessId, employeeId, operationId } = yield* Invocation;
          const owner = input.owner ?? employeeId;
          if (!(yield* rpc(() => employeeIn(businessId, owner))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "The accountable employee isn't part of this business",
            });
          if (input.projectId && !(yield* stored(project(db, businessId, input.projectId))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such project in this business",
            });
          const id = yield* Effect.promise(() => stableId(`${businessId}:${operationId}`));
          const created = summary(
            yield* stored(
              createCommitment(db, businessId, {
                id,
                owner,
                title: input.title,
                ...(input.objective ? { objective: input.objective } : {}),
                ...(input.nextAction ? { nextAction: input.nextAction } : {}),
                ...(input.dueAt ? { dueAt: new Date(input.dueAt).toISOString() } : {}),
                ...(input.projectId ? { projectId: input.projectId } : {}),
                createdBy: `employee:${employeeId}`,
              }),
            ),
          );
          return { ...created, ref: ref("work", "item", created.id) };
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
          const work = yield* ownWork(id);
          const blocked = yield* rpc(() => completionBlocked(businessId, work));
          if (blocked) return yield* new CapabilityError({ code: "conflict", message: blocked });
          return yield* change(id, expectedRevision, {
            state: "completed",
            evidence: { by: `employee:${employeeId}`, note: evidence },
          });
        }),
    }),
    capability({
      name: "projectList",
      description:
        "List the business's projects (bounded initiatives like Launch): goal, deadline, budget, lead, members and the refs of the artifacts and files each one shows. Its work items carry its id as projectId in commitmentList.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({}),
      output: Schema.Struct({ projects: Schema.Array(ProjectView) }),
      execute: () =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          return { projects: (yield* stored(projects(db, businessId))).map(view) };
        }),
    }),
    capability({
      name: "projectCreate",
      description:
        "Create a project: a bounded initiative with a name and optionally a goal, a deadline (YYYY-MM-DD), a budget in cents and a currency, and assigned employees. You lead it.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        name: Line(80),
        goal: Schema.optional(Schema.String.check(Schema.isMaxLength(500))),
        deadline: Schema.optional(Day),
        budget: Schema.optional(Budget),
        members: Schema.optional(Members),
      }),
      output: Schema.Struct({ ...ProjectView.fields, ref: Ref }),
      execute: ({ name, goal, deadline, budget, members }) =>
        Effect.gen(function* () {
          const { businessId, employeeId, operationId } = yield* Invocation;
          yield* checkEmployees(businessId, members ?? []);
          const id = yield* Effect.promise(() => stableId(`${businessId}:${operationId}`));
          const created = yield* stored(
            createProject(db, businessId, {
              id,
              name,
              ...(goal ? { goal } : {}),
              ...(deadline ? { deadline } : {}),
              ...(budget ? { budget } : {}),
              lead: employeeId,
              ...(members ? { members } : {}),
            }),
          );
          return { ...view(created), ref: ref("work", "project", created.id) };
        }),
    }),
    capability({
      name: "projectUpdate",
      description:
        "Change a project: its name, goal, deadline or budget (null clears one), its lead, or its members (the whole list).",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        id: Id,
        name: Schema.optional(Line(80)),
        goal: Schema.optional(Schema.NullOr(Schema.String.check(Schema.isMaxLength(500)))),
        deadline: Schema.optional(Schema.NullOr(Day)),
        budget: Schema.optional(Schema.NullOr(Budget)),
        lead: Schema.optional(Id),
        members: Schema.optional(Members),
      }),
      output: ProjectView,
      execute: ({ id, lead, members, ...rest }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          yield* checkEmployees(businessId, [...(lead ? [lead] : []), ...(members ?? [])]);
          const updated = yield* stored(
            updateProject(db, businessId, id, {
              ...rest,
              ...(lead ? { lead } : {}),
              ...(members ? { members } : {}),
            }),
          );
          if (!updated)
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such project in this business",
            });
          return view(updated);
        }),
    }),
    capability({
      name: "projectAdd",
      description:
        "Show a saved artifact (devys:documents/artifact/<id>) or a file in the business folder (devys:documents/file/<percent-encoded absolute path>) on a project, by its ref. It's a reference: the record keeps one home and can appear in several projects. Work items join a project when created with its projectId.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ projectId: Id, ref: Ref }),
      output: Schema.Struct({ id: Schema.String }),
      execute: ({ projectId, ref: kept }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          if (!(yield* rpc(() => keepable(businessId, kept))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such artifact or file in this business",
            });
          const item = yield* stored(addToProject(db, businessId, projectId, kept));
          if (!item)
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such project in this business",
            });
          return { id: item.id };
        }),
    }),
  ];
}
