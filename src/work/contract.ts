import { Schema } from "effect";
import type { Ref } from "../protocol/ref.ts";

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

/** A work item's fields as people and employees write them: one rule for HTTP and capabilities. */
export const WorkItemFields = {
  title: Line(200),
  objective: Text(4000),
  nextAction: Text(1000),
  waitCondition: Schema.NullOr(Text(1000)),
  dueAt: Instant,
  owner: EmployeeId,
  state: WorkItemState,
  expectedRevision: Schema.Int,
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

/** What is owed: who is accountable, what's next, and the evidence once done. */
export interface WorkItem {
  id: string;
  owner_employee_id: string;
  title: string;
  objective: string;
  next_action: string;
  wait_condition: string | null;
  due_at: string | null;
  state: WorkItemState;
  /** The project it belongs to, if any. */
  project_id: string | null;
  /** Values for capabilities' own constraint fields, by capability name. They only narrow. */
  conditions: Record<string, Record<string, unknown>>;
  /** What was done; a coding result names its commit and the check that ran against it. */
  evidence: {
    by: string;
    note: string;
    at: string;
    commit?: string;
    check?: { command: string; exitCode: number | null };
    /** What a commit changed, as "3 files changed, 10 insertions(+)". */
    changes?: string;
    /** The pull request the work was published as. */
    pullRequest?: string;
    /** A deploy of `commit`: where, the URL checked, and whether it answered. */
    deploy?: { stage: "preview" | "production"; url: string | null; live: boolean };
    /** The event this was recorded from; evidence from one source is recorded once. */
    source?: string;
  }[];
  revision: number;
  /** The person who took this over from the employee, if anyone. */
  taken_over_by: string | null;
  created_by: string;
  updated_at: string;
}

/** A record a project shows: a reference, never a copy (an artifact or a business file). */
export interface ProjectItem {
  id: string;
  ref: Ref;
}

/** A bounded initiative. Its work items belong to it; it confers no access. */
export interface Project {
  id: string;
  name: string;
  goal: string | null;
  /** A calendar date, `YYYY-MM-DD`. */
  deadline: string | null;
  /** A spending limit in the currency's smallest unit; it narrows, never grants. */
  budget: { cents: number; currency: string } | null;
  /** The employee who answers in the project's channel; null until one is chosen. */
  lead_employee_id: string | null;
  /** The employees assigned to it, besides the lead. */
  member_ids: string[];
  items: ProjectItem[];
}
