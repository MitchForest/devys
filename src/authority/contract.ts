/** `auto` runs inside the grant; `ask` needs an owner decision. Absence of a grant denies. */
export type Mode = "auto" | "ask";

/** One employee's standing permission for one capability. Immutable: a change is a new grant. */
export interface Grant {
  id: string;
  capability: string;
  mode: Mode;
  /** Values for the capability's own constraint fields; empty means no extra limits. */
  constraints: Record<string, unknown>;
  /** The area of accountability this grant serves, e.g. "Launch". */
  responsibility: string | null;
  created_at: string;
}

export type Outcome =
  | { outcome: "allow"; grantId: string }
  | { outcome: "ask"; grantId: string; decisionId?: string }
  | { outcome: "deny"; reason: string };

/** A one-off owner approval of one exact request. Single-use; expires to rejected. */
export interface Decision {
  id: string;
  employee_id: string;
  capability: string;
  /** The exact input the employee asked to run. */
  input: unknown;
  work_item_id: string | null;
  /** The conversation the asking turn was answering; the answer is posted there. */
  conversation: string | null;
  status: "pending" | "approved" | "rejected" | "used";
  requested_at: string;
  expires_at: string;
}
