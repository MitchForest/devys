import { Effect, Schema } from "effect";
import { OwnerRequest, type Decision } from "../authority/contract.ts";
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
  WorkResult,
  WorkStep,
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

/**
 * One naming rule for every work, project and routine capability: the record a capability reads
 * or changes is `ref` and its revision `revision`, the names its output gives them, so what one
 * call returns is passed to the next as is. Any other record is named by what it is (`project`).
 */
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
  steps: Schema.Array(WorkStep),
  results: Schema.Array(WorkResult),
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
  steps: item.steps,
  results: item.results,
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
  /** Whether this employee directs others' work (the Chief of Staff). */
  coordinates: (businessId: string, employeeId: string) => Promise<boolean>,
  /**
   * Shows the work item as one card in the conversation it was created from; clients draw it
   * from the item as it is now, so each later change updates it in place. Its thread shows the
   * same card above its messages without a post.
   */
  showCard: (businessId: string, work: WorkItem, conversation: string) => Promise<void>,
  /** Asks the owner, bound to this work item (authority's request, connected in wiring). */
  askOwner: (
    asking: { businessId: string; employeeId: string; workItemId: string; conversation: string },
    request: OwnerRequest,
  ) => Promise<Decision>,
  /**
   * Whether the owner has something to act on for this work item now: a pending request, or a
   * question card in its thread. Either way they have buttons to tap.
   */
  ownerCanAct: (businessId: string, workItemId: string) => Promise<boolean>,
) {
  /**
   * A work item is changed by its owner (colleagues ask there); the Chief of Staff, coordinating,
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
  const change = (id: string, revision: number, value: Change) =>
    Effect.gen(function* () {
      const { businessId, employeeId } = yield* Invocation;
      const updated = yield* stored(
        updateWorkItem(db, businessId, id, revision, value, {
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
  /** A routine is changed by its employee, or by the Chief of Staff. */
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
          message: "Another employee's routine: ask them, or the Chief of Staff.",
        });
      return found;
    });
  return [
    capability({
      name: "workList",
      activity: "Checking the work",
      description:
        "List the business's work items: what is owed, who is accountable, the next action and state, its steps and results, each with its ref and revision. Read before changing one; a change passes its ref and revision as they are.",
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
      activity: "Writing the plan",
      description:
        'Record something the business owes: a title, objective and next action, accountable to you or another employee, optionally in a project. Use for work that outlives this conversation. Give work of more than two steps its plan as steps (at most 10, each {title, state: todo, by?: "owner"}): a few plain words each ("Connect Ramp", "Sign in to the registrar", "Approve the total"), in order, with by: "owner" on each step only the owner can do (connect an app, sign in, approve a payment). A plan with a step for the owner, a payment or anything public waits for the owner\'s Start (it always does with an owner step; set waitForStart for a payment or anything public) and is handed to its employee once started; any other plan starts at once. Start approves the order only: each payment, send, publish or production deploy is still asked when reached. Returns its ref and revision, which workUpdate and workComplete take as they are.',
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        title: WorkItemFields.title,
        objective: Schema.optional(WorkItemFields.objective),
        nextAction: Schema.optional(WorkItemFields.nextAction),
        owner: Schema.optional(WorkItemFields.owner),
        dueAt: Schema.optional(WorkItemFields.dueAt),
        project: Schema.optional(ProjectRef),
        steps: Schema.optional(WorkItemFields.steps),
        waitForStart: Schema.optional(Schema.Boolean),
      }),
      output: Summary,
      execute: (input) =>
        Effect.gen(function* () {
          const { businessId, employeeId, operationId, conversation } = yield* Invocation;
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
          const created = yield* stored(
            createWorkItem(db, businessId, {
              id,
              owner,
              title: input.title,
              ...(input.objective ? { objective: input.objective } : {}),
              ...(input.nextAction ? { nextAction: input.nextAction } : {}),
              ...(input.dueAt ? { dueAt: new Date(input.dueAt).toISOString() } : {}),
              ...(input.project ? { projectId: input.project } : {}),
              ...(input.steps ? { steps: input.steps } : {}),
              waitsForStart:
                Boolean(input.waitForStart) ||
                Boolean(input.steps?.some((step) => step.by === "owner")),
              createdBy: `employee:${employeeId}`,
            }),
          );
          // The conversation it came from shows its card, which opens it and follows its progress.
          if (conversation && !conversation.startsWith("work:"))
            yield* rpc(() => showCard(businessId, created, conversation));
          return summary(created);
        }),
    }),
    capability({
      name: "workUpdate",
      activity: "Updating the plan",
      description:
        'Update a work item (ref and revision, as workList or the last change returned them), from any conversation: the next action, its state (ready, in_progress, waiting, needs_decision, cancelled), what it waits on, or its due date (a deadline only). needs_decision is for a question or request the owner has in front of them now; a ready item is handed to you in its thread, so never set needs_decision for a request you have yet to make. steps is the whole plan the owner watches in the thread for anything that takes more than a minute (at most 10, each {title, state: todo, doing, done or blocked}); send it again as each step moves. results is the whole list of what it achieved, each checked from outside (at most 12, each {label, value?, url? (https), ok?: true held, false failed, null uncertain}), such as {label: "Live at", url} or {label: "MX records", ok: true}. Each replaces the last. To follow up later ("look again Thursday"), set state waiting with wakeAt: at that time it becomes ready and is handed back to you in its thread, once. A routine (routinePropose) is for work that recurs.',
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        ref: WorkItemRef,
        revision: WorkItemFields.revision,
        state: Schema.optional(WorkItemUpdateState),
        nextAction: Schema.optional(WorkItemFields.nextAction),
        waitCondition: Schema.optional(WorkItemFields.waitCondition),
        dueAt: Schema.optional(Schema.NullOr(WorkItemFields.dueAt)),
        /** With state waiting: when to look again. Null clears it. */
        wakeAt: Schema.optional(Schema.NullOr(WorkItemFields.wakeAt)),
        steps: Schema.optional(WorkItemFields.steps),
        results: Schema.optional(WorkItemFields.results),
      }),
      output: Summary,
      execute: ({
        ref: id,
        revision,
        state,
        nextAction,
        waitCondition,
        dueAt,
        wakeAt,
        steps,
        results,
      }) =>
        Effect.gen(function* () {
          yield* ownWork(id, "anywhere");
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
          // The owner's turn always comes with what to tap, never as an instruction.
          const { businessId } = yield* Invocation;
          if (state === "needs_decision" && !(yield* rpc(() => ownerCanAct(businessId, id))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message:
                "The owner's turn needs something to tap. Raise this step with askOwner in the work item's thread (connect an app, take_over to sign in, approve, a secret or a file), or ask its question there with suggestReplies; then set needs_decision. Don't tell the owner to do it in words.",
            });
          return yield* change(id, revision, {
            ...(state ? { state } : {}),
            ...(nextAction !== undefined ? { nextAction } : {}),
            ...(waitCondition !== undefined ? { waitCondition } : {}),
            ...(dueAt !== undefined ? { dueAt: dueAt && new Date(dueAt).toISOString() } : {}),
            ...(wakeAt !== undefined ? { wakeAt: wakeAt && new Date(wakeAt).toISOString() } : {}),
            ...(steps ? { steps } : {}),
            ...(results ? { results } : {}),
          });
        }),
    }),
    capability({
      name: "workComplete",
      activity: "Wrapping up the work",
      description:
        "Mark a work item (ref and revision, as returned) completed, in its own thread, with evidence: what was done and where to see it, and results: the whole list of what it achieved, as in workUpdate, each checked from outside first. Saying 'done' in chat does not complete work.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        ref: WorkItemRef,
        revision: WorkItemFields.revision,
        evidence: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(2000)),
        results: Schema.optional(WorkItemFields.results),
      }),
      output: Summary,
      execute: ({ ref: id, revision, evidence, results }) =>
        Effect.gen(function* () {
          const { businessId, employeeId } = yield* Invocation;
          const work = yield* ownWork(id, "thread");
          const blocked = yield* rpc(() => completionBlocked(businessId, work));
          if (blocked) return yield* new CapabilityError({ code: "conflict", message: blocked });
          return yield* change(id, revision, {
            state: "completed",
            evidence: { by: `employee:${employeeId}`, note: evidence },
            ...(results ? { results } : {}),
          });
        }),
    }),
    capability({
      name: "projectList",
      activity: "Checking projects",
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
      activity: "Starting a project",
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
      activity: "Updating the project",
      description:
        "Change a project (its ref): its name, goal, deadline or budget (null clears one), its lead, or its members (the whole list).",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        ref: ProjectRef,
        name: Schema.optional(ProjectFields.name),
        goal: Schema.optional(Schema.NullOr(ProjectFields.goal)),
        deadline: Schema.optional(Schema.NullOr(ProjectFields.deadline)),
        budget: Schema.optional(Schema.NullOr(ProjectFields.budget)),
        lead: Schema.optional(ProjectFields.lead),
        members: Schema.optional(ProjectFields.members),
      }),
      output: ProjectView,
      execute: ({ ref: id, lead, members, ...rest }) =>
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
      activity: "Adding to the project",
      description:
        "Show a record on a project (its ref): record is a saved artifact (devys:documents/artifact/<id>), a file in the business folder (devys:documents/file/<percent-encoded absolute path>) or a coding session (devys:code/session/<id>). It's a reference: the record keeps one home and can appear in several projects. Returns the project. Work items join a project when created with its ref as project.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ ref: ProjectRef, record: Ref }),
      output: ProjectView,
      execute: ({ ref: projectId, record: kept }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          if (!(yield* rpc(() => keepable(businessId, kept))))
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such artifact, file or coding session in this business",
            });
          const item = yield* stored(addToProject(db, businessId, projectId, kept));
          const shown = item && (yield* stored(project(db, businessId, projectId)));
          if (!shown)
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "No such project in this business",
            });
          return view(shown);
        }),
    }),
    capability({
      name: "routineList",
      activity: "Checking routines",
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
      activity: "Proposing a routine",
      description:
        'Propose a routine: work you (or, for the Chief of Staff, another employee) run on a schedule or when an event happens, for a responsibility or a project (its ref; runs then speak in its channel, else in the employee\'s direct chat). trigger is {kind: "cron", expression: five-field cron like "0 9 * * 1", timezone: the owner\'s IANA zone, hours?: {start: "09:00", end: "18:00", days?: ["mon", …]}} or {kind: "event", source, type, filters: {field: exact value}}. notify when_found makes a quiet check-in: a run that finds nothing posts nothing. To change a routine, pass its ref and revision as returned: that is a new proposal and it stops running until approved. Proposing activates nothing: then call routineActivate with the ref and revision it returns, which asks the owner. For a one-off look later, use workUpdate with wakeAt instead.',
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        ref: Schema.optional(RoutineRef),
        revision: Schema.optional(Schema.Int),
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
              message:
                "Propose routines for yourself; the Chief of Staff proposes them for others.",
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
          if (!input.ref) {
            const id = yield* Effect.promise(() => stableId(`${businessId}:${operationId}`));
            return routineView(
              yield* stored(proposeRoutine(db, businessId, id, proposal, `employee:${employeeId}`)),
            );
          }
          yield* ownRoutine(input.ref);
          if (input.revision === undefined)
            return yield* new CapabilityError({
              code: "invalid_input",
              message: "Revising a routine needs its current revision",
            });
          const revised = yield* stored(
            reviseRoutine(db, businessId, input.ref, input.revision, proposal),
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
      activity: "Turning on a routine",
      description:
        "Ask the owner to activate a proposed routine (its ref) at exactly this revision. It is the owner's decision each time: the request waits for the owner, and once approved, calling it again with the same input activates it. A later revision needs a new decision.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ ref: RoutineRef, revision: Schema.Int }),
      output: RoutineView,
      execute: ({ ref: id, revision }) =>
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
      activity: "Pausing a routine",
      description:
        "Pause an active routine (its ref) of yours, such as one that no longer finds anything worth doing; say why where you are talking. Only the owner resumes it.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({ ref: RoutineRef }),
      output: RoutineView,
      execute: ({ ref: id }) =>
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
    capability({
      name: "askOwner",
      activity: "Asking you",
      description:
        'Bring the owner in, from a work item\'s thread; a turn in a direct chat or channel can\'t ask: workCreate the work, say you will ask there, and ask when you continue in its thread (leave it ready: it is handed to you there within a minute). {kind: "approve", action, counterparty, amount?, renewal?}: before a consequential action you will take anywhere (browser, shell, an app), state it exactly: action is what you will do, counterparty who or where (merchant, site, person; for a card payment, the merchant\'s site such as namecheap.com, where the card will be filled); any spend has amount {cents, currency}, which the owner signs with Face ID or Touch ID, and renewal says what recurs. To ask once for several actions that go together, list each exactly in steps (["Merge PR #12 at a1b2c3", "Deploy a1b2c3 of site to production"]): the approval covers those steps and nothing else. To show the owner what goes out (an email draft, a post, an invoice, a page), pass it as preview: the ref of a page or a file; changing it afterwards voids the approval, so ask again. {kind: "take_over", reason, url?}: something only the owner can do in the business\'s browser (sign in, 2FA, CAPTCHA); they take the work over, do it and hand it back. {kind: "secret", name, why, spend?}: a secret the business lacks (an API key, a password; spend: true for a card), named as you will use it (STRIPE_KEY); the owner enters it in a secure sheet and you use it by name (run\'s secrets, browserFill), never seeing it. {kind: "connect", app, why}: an app the business doesn\'t have yet (an id or registry name from appSearch, or an MCP server\'s https address); the owner connects it with its own sign-in and chooses what you may do with it; why is one line on the card. {kind: "file", purpose, accept?}: a file only the owner has (a logo, a signed contract, an ID scan); purpose is one line on the card, accept the media types it may be (["image/*", "application/pdf"]); their file arrives in the business folder and its ref in this thread. It returns at once: carry on with other work or wait; the answer arrives in this thread. Asking again with exactly the same input tells you where it stands (asked, approved, declined, taken_over, done). A changed amount, merchant or action is a new request. Never ask for passwords, codes or card numbers in chat.',
      effect: "change",
      replay: "idempotent",
      core: true,
      input: OwnerRequest,
      output: Schema.Struct({
        request: Schema.String,
        kind: Schema.Literals(["approve", "take_over", "secret", "connect", "file"]),
        state: Schema.Literals(["asked", "approved", "declined", "taken_over", "done"]),
        expiresAt: Schema.String,
        /** For a file request once answered: the file the owner chose. */
        file: Schema.optional(Ref),
      }),
      execute: (request) =>
        Effect.gen(function* () {
          const { businessId, employeeId, workItemId } = yield* Invocation;
          if (!workItemId)
            return yield* new CapabilityError({
              code: "conflict",
              message:
                "askOwner is asked in a work item's thread, where the answer binds: record the work (workCreate) or find it (workList), and ask in its thread.",
            });
          const asked = yield* rpc(() =>
            askOwner(
              // The answer is said in the thread, whichever turn asked.
              { businessId, employeeId, workItemId, conversation: `work:${workItemId}` },
              request,
            ),
          );
          return {
            request: asked.id,
            kind: request.kind,
            state: requestState(asked),
            expiresAt: asked.expires_at,
            ...(asked.answer ? { file: asked.answer } : {}),
          };
        }),
    }),
  ];
}

/** Where an `askOwner` request stands, in the words its output uses. */
const requestState = (decision: Decision) =>
  decision.status === "pending"
    ? ("asked" as const)
    : decision.status === "rejected"
      ? ("declined" as const)
      : decision.kind === "secret" || decision.kind === "connect" || decision.kind === "file"
        ? ("done" as const)
        : decision.kind === "take_over"
          ? decision.status === "approved"
            ? ("taken_over" as const)
            : ("done" as const)
          : ("approved" as const);
