import { Effect, Schema } from "effect";
import type { Database } from "../data/database.ts";
import { stableId } from "../protocol/bytes.ts";
import { capability, CapabilityError, Invocation } from "../protocol/capability.ts";
import { rpc, stored } from "../protocol/rpc.ts";
import { Ref, RefOf, ref } from "../protocol/ref.ts";
import {
  ProjectFields,
  WorkItemFields,
  type Project,
  type WorkItem,
  type WorkItemState,
} from "./contract.ts";
import { workItem, workItems, createWorkItem, updateWorkItem, type Change } from "./service.ts";
import { addToProject, createProject, project, projects, updateProject } from "./projects.ts";

/**
 * The states an employee sets with `workUpdate`: completing takes evidence (`workComplete`)
 * and proposing is how a person records work.
 */
const WorkItemUpdateState = Schema.Literals([
  "ready",
  "in_progress",
  "waiting",
  "needs_decision",
  "cancelled",
] as const satisfies readonly WorkItemState[]);

const Summary = Schema.Struct({
  ref: Ref,
  title: Schema.String,
  state: Schema.String,
  owner: Schema.String,
  nextAction: Schema.String,
  waitCondition: Schema.NullOr(Schema.String),
  dueAt: Schema.NullOr(Schema.String),
  revision: Schema.Number,
  takenOver: Schema.Boolean,
  project: Schema.NullOr(Ref),
});
const summary = (item: WorkItem) => ({
  ref: ref("work", "item", item.id),
  title: item.title,
  state: item.state,
  owner: item.owner_employee_id,
  nextAction: item.next_action,
  waitCondition: item.wait_condition,
  dueAt: item.due_at,
  revision: item.revision,
  takenOver: item.taken_over_by !== null,
  project: item.project_id === null ? null : ref("work", "project", item.project_id),
});
const WorkItemRef = RefOf("work", "item");
const ProjectRef = RefOf("work", "project");

const ProjectView = Schema.Struct({
  ref: Ref,
  name: Schema.String,
  goal: Schema.NullOr(Schema.String),
  deadline: Schema.NullOr(Schema.String),
  budget: Schema.NullOr(Schema.Struct({ cents: Schema.Number, currency: Schema.String })),
  lead: Schema.NullOr(Schema.String),
  members: Schema.Array(Schema.String),
  /** The records it shows. */
  items: Schema.Array(Ref),
});
const view = (item: Project) => ({
  ref: ref("work", "project", item.id),
  name: item.name,
  goal: item.goal,
  deadline: item.deadline,
  budget: item.budget,
  lead: item.lead_employee_id,
  members: item.member_ids,
  items: item.items.map((shown) => shown.ref),
});

/** The business's durable work, operated by employees through the same rules as people. */
export function workCapabilities(
  db: Database,
  employeeIn: (businessId: string, employeeId: string) => Promise<boolean>,
  /** Whether a ref names a record of this business a project can show: an artifact or a file. */
  keepable: (businessId: string, ref: Ref) => Promise<boolean>,
  /** Why this work cannot be completed yet (such as a coding check that has not passed). */
  completionBlocked: (businessId: string, work: WorkItem) => Promise<string | undefined>,
  /** Whether this employee directs others' work (the Head of Operations). */
  coordinates: (businessId: string, employeeId: string) => Promise<boolean>,
) {
  /** A work item is changed by its owner, or by Operations; others ask in its thread. */
  const ownWork = (id: string) =>
    Effect.gen(function* () {
      const { businessId, employeeId } = yield* Invocation;
      const work = yield* stored(workItem(db, businessId, id));
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
        updateWorkItem(db, businessId, id, expectedRevision, value, {
          kind: "employee",
          id: employeeId,
        }),
      );
      if (!updated)
        return yield* new CapabilityError({
          code: "conflict",
          message: "The work item changed or was taken over; list it again",
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
      name: "workList",
      description:
        "List the business's work items: what is owed, who is accountable, the next action and state, each with its ref. Read before changing one; changes name it by its ref and need its current revision.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({ openOnly: Schema.optional(Schema.Boolean) }),
      output: Schema.Struct({ workItems: Schema.Array(Summary) }),
      execute: ({ openOnly }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          const items = yield* stored(workItems(db, businessId));
          return {
            workItems: items
              .filter((item) => !openOnly || !["completed", "cancelled"].includes(item.state))
              .map(summary),
          };
        }),
    }),
    capability({
      name: "workCreate",
      description:
        "Record something the business owes: a title, objective and next action, accountable to you or another employee, optionally in a project. Use for work that outlives this conversation.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        title: WorkItemFields.title,
        objective: Schema.optional(WorkItemFields.objective),
        nextAction: Schema.optional(WorkItemFields.nextAction),
        owner: Schema.optional(WorkItemFields.owner),
        dueAt: Schema.optional(WorkItemFields.dueAt),
        project: Schema.optional(ProjectRef),
      }),
      output: Summary,
      execute: (input) =>
        Effect.gen(function* () {
          const { businessId, employeeId, operationId } = yield* Invocation;
          const owner = input.owner ?? employeeId;
          if (!(yield* rpc(() => employeeIn(businessId, owner))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "The accountable employee isn't part of this business",
            });
          if (input.project && !(yield* stored(project(db, businessId, input.project))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such project in this business",
            });
          const id = yield* Effect.promise(() => stableId(`${businessId}:${operationId}`));
          return summary(
            yield* stored(
              createWorkItem(db, businessId, {
                id,
                owner,
                title: input.title,
                ...(input.objective ? { objective: input.objective } : {}),
                ...(input.nextAction ? { nextAction: input.nextAction } : {}),
                ...(input.dueAt ? { dueAt: new Date(input.dueAt).toISOString() } : {}),
                ...(input.project ? { projectId: input.project } : {}),
                createdBy: `employee:${employeeId}`,
              }),
            ),
          );
        }),
    }),
    capability({
      name: "workUpdate",
      description:
        "Update a work item (its ref) at its current revision: the next action, its state (ready, in_progress, waiting, needs_decision, cancelled), what it waits on, or its due date.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        item: WorkItemRef,
        expectedRevision: WorkItemFields.expectedRevision,
        state: Schema.optional(WorkItemUpdateState),
        nextAction: Schema.optional(WorkItemFields.nextAction),
        waitCondition: Schema.optional(WorkItemFields.waitCondition),
        dueAt: Schema.optional(Schema.NullOr(WorkItemFields.dueAt)),
      }),
      output: Summary,
      execute: ({ item, expectedRevision, state, nextAction, waitCondition, dueAt }) =>
        change(item, expectedRevision, {
          ...(state ? { state } : {}),
          ...(nextAction !== undefined ? { nextAction } : {}),
          ...(waitCondition !== undefined ? { waitCondition } : {}),
          ...(dueAt !== undefined ? { dueAt: dueAt && new Date(dueAt).toISOString() } : {}),
        }),
    }),
    capability({
      name: "workComplete",
      description:
        "Mark a work item (its ref) completed, at its current revision, with evidence: what was done and where to see it. Saying 'done' in chat does not complete work.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        item: WorkItemRef,
        expectedRevision: WorkItemFields.expectedRevision,
        evidence: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(2000)),
      }),
      output: Summary,
      execute: ({ item, expectedRevision, evidence }) =>
        Effect.gen(function* () {
          const { businessId, employeeId } = yield* Invocation;
          const work = yield* ownWork(item);
          const blocked = yield* rpc(() => completionBlocked(businessId, work));
          if (blocked) return yield* new CapabilityError({ code: "conflict", message: blocked });
          return yield* change(item, expectedRevision, {
            state: "completed",
            evidence: { by: `employee:${employeeId}`, note: evidence },
          });
        }),
    }),
    capability({
      name: "projectList",
      description:
        "List the business's projects (bounded initiatives like Launch): goal, deadline, budget, lead, members and the refs of the artifacts and files each one shows. Its work items carry its ref as project in workList.",
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
        name: ProjectFields.name,
        goal: Schema.optional(ProjectFields.goal),
        deadline: Schema.optional(ProjectFields.deadline),
        budget: Schema.optional(ProjectFields.budget),
        members: Schema.optional(ProjectFields.members),
      }),
      output: ProjectView,
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
          return view(created);
        }),
    }),
    capability({
      name: "projectUpdate",
      description:
        "Change a project (its ref): its name, goal, deadline or budget (null clears one), its lead, or its members (the whole list).",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        project: ProjectRef,
        name: Schema.optional(ProjectFields.name),
        goal: Schema.optional(Schema.NullOr(ProjectFields.goal)),
        deadline: Schema.optional(Schema.NullOr(ProjectFields.deadline)),
        budget: Schema.optional(Schema.NullOr(ProjectFields.budget)),
        lead: Schema.optional(ProjectFields.lead),
        members: Schema.optional(ProjectFields.members),
      }),
      output: ProjectView,
      execute: ({ project: id, lead, members, ...rest }) =>
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
        "Show a saved artifact (devys:documents/artifact/<id>), a file in the business folder (devys:documents/file/<percent-encoded absolute path>) or a coding session (devys:code/session/<id>) on a project (its ref), by the record's ref. It's a reference: the record keeps one home and can appear in several projects. Work items join a project when created with its ref as project.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ project: ProjectRef, ref: Ref }),
      output: Schema.Struct({ project: Ref, ref: Ref }),
      execute: ({ project: projectId, ref: kept }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          if (!(yield* rpc(() => keepable(businessId, kept))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such artifact, file or coding session in this business",
            });
          const item = yield* stored(addToProject(db, businessId, projectId, kept));
          if (!item)
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such project in this business",
            });
          return { project: ref("work", "project", projectId), ref: item.ref };
        }),
    }),
  ];
}
