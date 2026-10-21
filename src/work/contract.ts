export type CommitmentState =
  | "proposed"
  | "ready"
  | "in_progress"
  | "waiting"
  | "needs_decision"
  | "completed"
  | "cancelled";

/** What is owed: who is accountable, what's next, and the evidence once done. */
export interface Commitment {
  id: string;
  owner_employee_id: string;
  title: string;
  objective: string;
  next_action: string;
  wait_condition: string | null;
  due_at: string | null;
  state: CommitmentState;
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

/** A record a project shows: a reference, never a copy. */
export interface ProjectItem {
  id: string;
  /** A file's reference is its path in the business folder. */
  kind: "artifact" | "file";
  ref: string;
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
