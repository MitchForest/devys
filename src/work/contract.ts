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

/** A record shown in a space: a reference, never a copy. */
export interface SpaceItem {
  id: string;
  /** A file's reference is its path in the business folder. */
  kind: "commitment" | "artifact" | "file";
  ref: string;
}

/** A persistent place for an area of the business. It confers no access. */
export interface Space {
  id: string;
  name: string;
  purpose: string;
  /** The employee who answers in the space's thread; null until one is chosen. */
  lead_employee_id: string | null;
  items: SpaceItem[];
}
