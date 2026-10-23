import { Schema } from "effect";
import { Ref } from "../protocol/ref.ts";
import { Timestamp } from "../protocol/time.ts";

/** Every state a work item can be in: the one list. */
const workItemStates = [
  "proposed",
  "ready",
  "in_progress",
  "waiting",
  "needs_decision",
  "completed",
  "cancelled",
] as const;
export type WorkItemState = (typeof workItemStates)[number];
export const WorkItemState = Schema.Literals(workItemStates);

/** Text that says something: not blank, at most `max` characters. */
const Line = (max: number) =>
  Schema.String.check(
    Schema.isMaxLength(max),
    Schema.makeFilter((value) => value.trim().length > 0 || "Expected some text"),
  );
const Text = (max: number) => Schema.String.check(Schema.isMaxLength(max));
/** An employee's id. */
const EmployeeId = Line(64);
/** A moment, in any form `Date.parse` reads; stored as an ISO timestamp. */
const Instant = Schema.String.check(
  Schema.makeFilter((value) => Number.isFinite(Date.parse(value)) || "Expected a date and time"),
);

/** Every state a step can be in. */
const stepStates = ["todo", "doing", "done", "blocked"] as const;
/**
 * One step of a work item's plan: what happens, where it stands, and whether it is the owner's
 * to do (`by: "owner"`, shown as "You: …"); otherwise its employee does it.
 */
export const WorkStep = Schema.Struct({
  title: Line(120),
  state: Schema.Literals(stepStates),
  by: Schema.optionalKey(Schema.Literal("owner")),
});
export type WorkStep = typeof WorkStep.Type;
/** An https address: a result links only where the owner can safely open it. */
const HttpsUrl = Schema.String.check(
  Schema.isMaxLength(500),
  Schema.makeFilter((value) => {
    try {
      return new URL(value).protocol === "https:" || "Expected an https:// address";
    } catch {
      return "Expected an https:// address";
    }
  }),
);
/**
 * Proof of an effect the owner can glance at: "Registered acme-widgets.com" with "expires
 * 2027-10-22", "Live at" with its url. `ok` says whether it was checked from outside: true
 * (it held), false (it failed) or null (uncertain); absent when there is nothing to check.
 */
export const WorkResult = Schema.Struct({
  label: Line(80),
  value: Schema.optionalKey(Line(120)),
  url: Schema.optionalKey(HttpsUrl),
  ok: Schema.optionalKey(Schema.NullOr(Schema.Boolean)),
});
export type WorkResult = typeof WorkResult.Type;

/** A work item's fields as people and employees write them: one rule for HTTP and capabilities. */
export const WorkItemFields = {
  title: Line(200),
  objective: Text(4000),
  nextAction: Text(1000),
  waitCondition: Schema.NullOr(Text(1000)),
  dueAt: Instant,
  /** A follow-up: when waiting work becomes ready again. */
  wakeAt: Instant,
  owner: EmployeeId,
  state: WorkItemState,
  revision: Schema.Int,
  /** The whole plan, replacing the last one. */
  steps: Schema.Array(WorkStep).check(Schema.isMaxLength(10)),
  /** The whole list of results, replacing the last one. */
  results: Schema.Array(WorkResult).check(Schema.isMaxLength(12)),
};

/** A project's fields as people and employees write them. Null clears an optional one. */
export const ProjectFields = {
  name: Line(80),
  goal: Text(500),
  /** A calendar date, `YYYY-MM-DD`. */
  deadline: Schema.String.check(
    Schema.makeFilter(
      (value) =>
        (/^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value))) ||
        "Expected a date as YYYY-MM-DD",
    ),
  ),
  budget: Schema.Struct({
    cents: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
    currency: Schema.String.check(
      Schema.makeFilter((value) => /^[A-Z]{3}$/.test(value) || "Expected a currency like USD"),
    ),
  }),
  lead: EmployeeId,
  members: Schema.Array(EmployeeId).check(Schema.isMaxLength(50)),
};

/** A work item a person records over HTTP, in the API's field names. */
export const NewWorkItem = Schema.Struct({
  title: WorkItemFields.title,
  owner: WorkItemFields.owner,
  objective: Schema.optional(WorkItemFields.objective),
  next_action: Schema.optional(WorkItemFields.nextAction),
  due_at: Schema.optional(WorkItemFields.dueAt),
  conditions: Schema.optional(
    Schema.Record(Schema.String, Schema.Record(Schema.String, Schema.Unknown)),
  ),
  project_id: Schema.optional(Schema.String),
});
export type NewWorkItem = typeof NewWorkItem.Type;
/** A person's change at the revision they saw; null clears what waits or the due date. */
export const WorkItemChange = Schema.Struct({
  expected_revision: WorkItemFields.revision,
  title: Schema.optional(WorkItemFields.title),
  owner: Schema.optional(WorkItemFields.owner),
  state: Schema.optional(WorkItemFields.state),
  next_action: Schema.optional(WorkItemFields.nextAction),
  wait_condition: Schema.optional(WorkItemFields.waitCondition),
  due_at: Schema.optional(Schema.NullOr(WorkItemFields.dueAt)),
});

/** A project's fields from a person, in the clients' JSON. A null clears an optional field. */
export const ProjectChange = Schema.Struct({
  name: Schema.optional(ProjectFields.name),
  goal: Schema.optional(Schema.NullOr(ProjectFields.goal)),
  deadline: Schema.optional(Schema.NullOr(ProjectFields.deadline)),
  budget: Schema.optional(Schema.NullOr(ProjectFields.budget)),
  lead: Schema.optional(ProjectFields.lead),
  members: Schema.optional(ProjectFields.members),
});
export type ProjectChange = typeof ProjectChange.Type;
export const NewProject = Schema.Struct({ ...ProjectChange.fields, name: ProjectFields.name });

/** What was done; a coding result names its commit and the check that ran against it. */
const Evidence = Schema.Struct({
  by: Schema.String,
  note: Schema.String,
  at: Timestamp,
  commit: Schema.optionalKey(Schema.String),
  check: Schema.optionalKey(
    Schema.Struct({ command: Schema.String, exit_code: Schema.NullOr(Schema.Number) }),
  ),
  /** What a commit changed, as "3 files changed, 10 insertions(+)". */
  changes: Schema.optionalKey(Schema.String),
  /** The pull request the work was published as. */
  pull_request: Schema.optionalKey(Schema.String),
  /** A deploy of `commit`: where, the URL checked, and whether it answered. */
  deploy: Schema.optionalKey(
    Schema.Struct({
      stage: Schema.Literals(["preview", "production"]),
      url: Schema.NullOr(Schema.String),
      live: Schema.Boolean,
    }),
  ),
  /** The event this was recorded from; evidence from one source is recorded once. */
  source: Schema.optionalKey(Schema.String),
});

/** What is owed: who is accountable, what's next, and the evidence once done. */
export const WorkItem = Schema.Struct({
  id: Schema.String,
  owner_employee_id: Schema.String,
  title: Schema.String,
  objective: Schema.String,
  next_action: Schema.String,
  wait_condition: Schema.NullOr(Schema.String),
  /** A deadline, never a start time. */
  due_at: Schema.NullOr(Timestamp),
  /** A follow-up: when this waiting work becomes ready again. Only waiting work has one. */
  wake_at: Schema.NullOr(Timestamp),
  /** When a follow-up woke this work, until it next changes. */
  woken_at: Schema.NullOr(Timestamp),
  state: WorkItemState,
  /** The project it belongs to, if any; its thread is in that project's channel. */
  project_id: Schema.NullOr(Schema.String),
  /** Values for capabilities' own constraint fields, by capability name. They only narrow. */
  conditions: Schema.Record(Schema.String, Schema.Record(Schema.String, Schema.Unknown)),
  evidence: Schema.Array(Evidence),
  /** The plan its employee shows while it takes time. */
  steps: Schema.Array(WorkStep),
  /** What it achieved, each checked from outside where it can be. */
  results: Schema.Array(WorkResult),
  revision: Schema.Int,
  /** The person who took this over from the employee, if anyone. */
  taken_over_by: Schema.NullOr(Schema.String),
  /** `person:<id>` or `employee:<id>`. */
  created_by: Schema.String,
  updated_at: Timestamp,
});
export type WorkItem = typeof WorkItem.Type;

/** A record a project shows: a reference, never a copy (an artifact or a business file). */
export const ProjectItem = Schema.Struct({ id: Schema.String, ref: Ref });
export type ProjectItem = typeof ProjectItem.Type;

/** A bounded initiative. Its work items belong to it; it confers no access. */
export const Project = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  goal: Schema.NullOr(Schema.String),
  /** A calendar date, `YYYY-MM-DD`. */
  deadline: Schema.NullOr(Schema.String),
  /** A spending limit in the currency's smallest unit; it narrows, never grants. */
  budget: Schema.NullOr(Schema.Struct({ cents: Schema.Int, currency: Schema.String })),
  /** The employee who answers in the project's channel; null until one is chosen. */
  lead_employee_id: Schema.NullOr(Schema.String),
  /** The employees assigned to it, besides the lead. */
  member_ids: Schema.Array(Schema.String),
  items: Schema.Array(ProjectItem),
});
export type Project = typeof Project.Type;

/** Every state a routine can be in: proposed by an employee, active once the owner decides. */
const routineStates = ["proposed", "active", "paused"] as const;
export const RoutineState = Schema.Literals(routineStates);
export type RoutineState = (typeof routineStates)[number];

/** Whether a run speaks always, or only when it found something (a quiet check-in). */
export const RoutineNotify = Schema.Literals(["always", "when_found"]);
export type RoutineNotify = typeof RoutineNotify.Type;

/** A time of day, `HH:MM` on a 24-hour clock. */
const ClockTime = Schema.String.check(
  Schema.makeFilter(
    (value) => /^([01]\d|2[0-3]):[0-5]\d$/.test(value) || "Expected a time like 09:00",
  ),
);
const weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"] as const;
/**
 * When runs may happen, in the routine's time zone: from `start` up to `end` (`end` before
 * `start` spans midnight), on `days` (every day when absent). Slots outside are skipped.
 */
export const ActiveHours = Schema.Struct({
  start: ClockTime,
  end: ClockTime,
  days: Schema.optionalKey(Schema.Array(Schema.Literals(weekdays)).check(Schema.isMinLength(1))),
});
export type ActiveHours = typeof ActiveHours.Type;

/** A literal an event field must equal. */
const FilterValue = Schema.Union([Schema.String, Schema.Finite, Schema.Boolean]);
/** A source's name, an event type or a field name: short, plain words. */
const Name = Schema.String.check(Schema.isPattern(/^[a-z][a-z0-9_.-]{0,63}$/));

/**
 * What starts a run: a cron expression (five fields) in an IANA time zone, optionally within
 * active hours; or an event from a source (such as mail) whose fields equal every filter.
 */
export const Trigger = Schema.Union([
  Schema.Struct({
    kind: Schema.Literal("cron"),
    expression: Schema.String.check(Schema.isMinLength(9), Schema.isMaxLength(100)),
    timezone: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(64)),
    hours: Schema.optionalKey(ActiveHours),
  }),
  Schema.Struct({
    kind: Schema.Literal("event"),
    source: Name,
    type: Name,
    filters: Schema.Record(Name, FilterValue).check(
      Schema.makeFilter((value) => Object.keys(value).length <= 10 || "At most 10 filters"),
    ),
  }),
]);
export type Trigger = typeof Trigger.Type;

/** Recurring or event-started work of one employee, for a responsibility or a project. */
export const Routine = Schema.Struct({
  id: Schema.String,
  employee_id: Schema.String,
  /** The project it serves: its runs speak in that project's channel, else the employee's DM. */
  project_id: Schema.NullOr(Schema.String),
  title: Schema.String,
  instruction: Schema.String,
  trigger: Trigger,
  /** The trigger in words, as the owner reads it: "At 09:00 AM, only on Monday (Europe/London)". */
  schedule: Schema.String,
  notify: RoutineNotify,
  state: RoutineState,
  /** Each proposal is a new revision; the owner's decision activates exactly one. */
  revision: Schema.Int,
  /** The next scheduled run, while active. */
  next_run_at: Schema.NullOr(Timestamp),
  last_run_at: Schema.NullOr(Timestamp),
  /** What the last run said, shortened, or "nothing to report". */
  last_result: Schema.NullOr(Schema.String),
  /** `person:<id>` or `employee:<id>`. */
  created_by: Schema.String,
  updated_at: Timestamp,
});
export type Routine = typeof Routine.Type;

/** A result in words, the same in every client: "Registered acme.com · expires 2027-10-22 ✓". */
export const resultText = (result: WorkResult) =>
  [
    result.label,
    result.value && `· ${result.value}`,
    result.url,
    result.ok === true ? "✓" : result.ok === false ? "✗" : result.ok === null ? "?" : undefined,
  ]
    .filter(Boolean)
    .join(" ");

/** Where the steps stand, as Home shows moving work: "2 of 5 · Setting up email". */
export function progressText(steps: readonly WorkStep[]) {
  if (!steps.length) return null;
  const done = steps.filter((step) => step.state === "done").length;
  const now =
    steps.find((step) => step.state === "blocked") ?? steps.find((step) => step.state === "doing");
  return [
    `${done} of ${steps.length}`,
    now && `· ${now.state === "blocked" ? "Blocked: " : ""}${now.title}`,
  ]
    .filter(Boolean)
    .join(" ");
}
