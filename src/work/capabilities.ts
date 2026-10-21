import { Effect, Schema } from "effect";
import type { Database } from "../data/database.ts";
import { stableId } from "../protocol/bytes.ts";
import { capability, CapabilityError, Invocation } from "../protocol/capability.ts";
import { rpc, stored } from "../protocol/rpc.ts";
import { Ref, RefOf, ref } from "../protocol/ref.ts";
import {
  ProjectFields,
  RoutineNotify,
  RoutineState,
  Trigger,
  WorkItemFields,
  type Project,
  type Routine,
  type WorkItem,
  type WorkItemState,
} from "./contract.ts";
import { workItem, workItems, createWorkItem, updateWorkItem, type Change } from "./service.ts";
import { addToProject, createProject, project, projects, updateProject } from "./projects.ts";
import {
  activateRoutine,
  nextRun,
  pauseRoutine,
  proposeRoutine,
  reviseRoutine,
  routine,
  routines,
  triggerProblem,
  type Proposal,
} from "./routines.ts";

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
  wakeAt: Schema.NullOr(Schema.String),
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
  wakeAt: item.wake_at,
  revision: item.revision,
  takenOver: item.taken_over_by !== null,
  project: item.project_id === null ? null : ref("work", "project", item.project_id),
});
const WorkItemRef = RefOf("work", "item");
const ProjectRef = RefOf("work", "project");
const RoutineRef = RefOf("work", "routine");

const RoutineView = Schema.Struct({
  ref: Ref,
  title: Schema.String,
  instruction: Schema.String,
  trigger: Trigger,
  /** The trigger in words. */
  schedule: Schema.String,
  notify: RoutineNotify,
  state: RoutineState,
  revision: Schema.Number,
  employee: Schema.String,
  project: Schema.NullOr(Ref),
  nextRunAt: Schema.NullOr(Schema.String),
  lastRunAt: Schema.NullOr(Schema.String),
  lastResult: Schema.NullOr(Schema.String),
});
const routineView = (item: Routine) => ({
  ref: ref("work", "routine", item.id),
  title: item.title,
  instruction: item.instruction,
  trigger: item.trigger,
  schedule: item.schedule,
  notify: item.notify,
  state: item.state,
  revision: item.revision,
  employee: item.employee_id,
  project: item.project_id === null ? null : ref("work", "project", item.project_id),
  nextRunAt: item.next_run_at,
  lastRunAt: item.last_run_at,
  lastResult: item.last_result,
});

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
  /**
   * A work item is changed by its owner (colleagues ask there); Operations, coordinating,
   * changes anyone's. Its plan and state change from any conversation, so what the owner asks
   * for in a chat is recorded there; it is completed only in its own thread, where it is
   * worked, so it is never finished twice from two places.
   */
  const ownWork = (id: string, where: "anywhere" | "thread") =>
    Effect.gen(function* () {
      const { businessId, employeeId, workItemId } = yield* Invocation;
      const work = yield* stored(workItem(db, businessId, id));
      if (!work)
        return yield* new CapabilityError({
          code: "invalid_input",
          message: "No such work item in this business",
        });
      if (yield* rpc(() => coordinates(businessId, employeeId))) return work;
      if (work.owner_employee_id !== employeeId)
        return yield* new CapabilityError({
          code: "forbidden",
          message: "Another employee's work item: ask its owner in its thread.",
        });
      if (where === "thread" && workItemId !== id)
        return yield* new CapabilityError({
          code: "conflict",
          message: `This work item is completed only in its own thread (${ref("work", "item", id)}), where it is worked. Here, update its plan or say what you found.`,
        });
      return work;
    });
  const change = (id: string, expectedRevision: number, value: Change) =>
    Effect.gen(function* () {
      const { businessId, employeeId } = yield* Invocation;
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
  /** A routine is changed by its employee, or by Operations. */
  const ownRoutine = (id: string) =>
    Effect.gen(function* () {
      const { businessId, employeeId } = yield* Invocation;
      const found = yield* stored(routine(db, businessId, id));
      if (!found)
        return yield* new CapabilityError({
          code: "invalid_input",
          message: "No such routine in this business",
        });
      if (
        found.employee_id !== employeeId &&
        !(yield* rpc(() => coordinates(businessId, employeeId)))
      )
        return yield* new CapabilityError({
          code: "forbidden",
          message: "Another employee's routine: ask them, or Operations.",
        });
      return found;
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
        'Update a work item (its ref) at its current revision, from any conversation: the next action, its state (ready, in_progress, waiting, needs_decision, cancelled), what it waits on, or its due date (a deadline only). To follow up later ("look again Thursday"), set state waiting with wakeAt: at that time it becomes ready and is handed back to you in its thread, once. A routine (routinePropose) is for work that recurs.',
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        item: WorkItemRef,
        expectedRevision: WorkItemFields.expectedRevision,
        state: Schema.optional(WorkItemUpdateState),
        nextAction: Schema.optional(WorkItemFields.nextAction),
        waitCondition: Schema.optional(WorkItemFields.waitCondition),
        dueAt: Schema.optional(Schema.NullOr(WorkItemFields.dueAt)),
        /** With state waiting: when to look again. Null clears it. */
        wakeAt: Schema.optional(Schema.NullOr(WorkItemFields.wakeAt)),
      }),
      output: Summary,
      execute: ({ item, expectedRevision, state, nextAction, waitCondition, dueAt, wakeAt }) =>
        Effect.gen(function* () {
          yield* ownWork(item, "anywhere");
          if (wakeAt && state !== "waiting")
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "A follow-up (wakeAt) goes with state waiting",
            });
          if (wakeAt && Date.parse(wakeAt) <= Date.now())
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "A follow-up (wakeAt) is a time in the future",
            });
          return yield* change(item, expectedRevision, {
            ...(state ? { state } : {}),
            ...(nextAction !== undefined ? { nextAction } : {}),
            ...(waitCondition !== undefined ? { waitCondition } : {}),
            ...(dueAt !== undefined ? { dueAt: dueAt && new Date(dueAt).toISOString() } : {}),
            ...(wakeAt !== undefined ? { wakeAt: wakeAt && new Date(wakeAt).toISOString() } : {}),
          });
        }),
    }),
    capability({
      name: "workComplete",
      description:
        "Mark a work item (its ref) completed, at its current revision, in its own thread, with evidence: what was done and where to see it. Saying 'done' in chat does not complete work.",
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
          const work = yield* ownWork(item, "thread");
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
    capability({
      name: "routineList",
      description:
        "List the business's routines (recurring or event-started work), or one employee's or one project's: each with its ref, schedule in words, state (proposed, active, paused), revision, next run and last result.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({
        employee: Schema.optional(WorkItemFields.owner),
        project: Schema.optional(ProjectRef),
      }),
      output: Schema.Struct({ routines: Schema.Array(RoutineView) }),
      execute: ({ employee, project: projectId }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          const found = yield* stored(
            routines(db, businessId, {
              ...(employee ? { employeeId: employee } : {}),
              ...(projectId ? { projectId } : {}),
            }),
          );
          return { routines: found.map(routineView) };
        }),
    }),
    capability({
      name: "routinePropose",
      description:
        'Propose a routine: work you (or, for Operations, another employee) run on a schedule or when an event happens, for a responsibility or a project (its ref; runs then speak in its channel, else in the employee\'s direct chat). trigger is {kind: "cron", expression: five-field cron like "0 9 * * 1", timezone: the owner\'s IANA zone, hours?: {start: "09:00", end: "18:00", days?: ["mon", …]}} or {kind: "event", source, type, filters: {field: exact value}}. notify when_found makes a quiet check-in: a run that finds nothing posts nothing. To change a routine, pass its ref and current revision: that is a new proposal and it stops running until approved. Proposing activates nothing: then call routineActivate with its ref and revision, which asks the owner. For a one-off look later, use workUpdate with wakeAt instead.',
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        routine: Schema.optional(RoutineRef),
        expectedRevision: Schema.optional(Schema.Int),
        title: WorkItemFields.title,
        instruction: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(4000)),
        trigger: Trigger,
        notify: RoutineNotify,
        project: Schema.optional(ProjectRef),
        employee: Schema.optional(WorkItemFields.owner),
      }),
      output: RoutineView,
      execute: (input) =>
        Effect.gen(function* () {
          const { businessId, employeeId, operationId } = yield* Invocation;
          const employee = input.employee ?? employeeId;
          if (employee !== employeeId && !(yield* rpc(() => coordinates(businessId, employeeId))))
            return yield* new CapabilityError({
              code: "forbidden",
              message: "Propose routines for yourself; Operations proposes them for others.",
            });
          if (!(yield* rpc(() => employeeIn(businessId, employee))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "The routine's employee isn't part of this business",
            });
          if (input.project && !(yield* stored(project(db, businessId, input.project))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such project in this business",
            });
          const problem = triggerProblem(input.trigger, new Date());
          if (problem)
            return yield* new CapabilityError({ code: "invalid_input", message: problem });
          const proposal: Proposal = {
            employeeId: employee,
            projectId: input.project ?? null,
            title: input.title,
            instruction: input.instruction,
            trigger: input.trigger,
            notify: input.notify,
          };
          if (!input.routine) {
            const id = yield* Effect.promise(() => stableId(`${businessId}:${operationId}`));
            return routineView(
              yield* stored(proposeRoutine(db, businessId, id, proposal, `employee:${employeeId}`)),
            );
          }
          yield* ownRoutine(input.routine);
          if (input.expectedRevision === undefined)
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "Revising a routine needs its current revision (expectedRevision)",
            });
          const revised = yield* stored(
            reviseRoutine(db, businessId, input.routine, input.expectedRevision, proposal),
          );
          if (!revised)
            return yield* new CapabilityError({
              code: "conflict",
              message: "The routine changed; list it again",
            });
          return routineView(revised);
        }),
    }),
    capability({
      name: "routineActivate",
      description:
        "Ask the owner to activate a proposed routine (its ref) at exactly this revision. It is the owner's decision each time: the request waits in Needs you, and once approved, calling it again with the same input activates it. A later revision needs a new decision.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ routine: RoutineRef, revision: Schema.Int }),
      output: RoutineView,
      execute: ({ routine: id, revision }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          const found = yield* ownRoutine(id);
          if (found.revision !== revision)
            return yield* new CapabilityError({
              code: "conflict",
              message: `The routine is at revision ${found.revision} now: ask for that revision`,
            });
          const next = found.trigger.kind === "cron" ? nextRun(found.trigger, new Date()) : null;
          if (found.trigger.kind === "cron" && !next)
            return yield* new CapabilityError({
              code: "conflict",
              message: "The schedule has no run left; propose a new one",
            });
          const activated = yield* stored(activateRoutine(db, businessId, id, revision, next));
          if (!activated)
            return yield* new CapabilityError({
              code: "conflict",
              message: "The routine changed; list it again",
            });
          return routineView(activated);
        }),
    }),
    capability({
      name: "routinePause",
      description:
        "Pause an active routine (its ref) of yours, such as one that no longer finds anything worth doing; say why where you are talking. Only the owner resumes it.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ routine: RoutineRef }),
      output: RoutineView,
      execute: ({ routine: id }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          yield* ownRoutine(id);
          const paused = yield* stored(pauseRoutine(db, businessId, id));
          if (!paused)
            return yield* new CapabilityError({
              code: "conflict",
              message: "Only an active routine can be paused",
            });
          return routineView(paused);
        }),
    }),
  ];
}
