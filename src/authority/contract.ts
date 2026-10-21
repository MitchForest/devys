import { Schema } from "effect";
import { ConversationKey } from "../conversations/contract.ts";
import { Timestamp } from "../protocol/time.ts";

/** `auto` runs inside the grant; `ask` needs an owner decision. Absence of a grant denies. */
export const Mode = Schema.Literals(["auto", "ask"]);
export type Mode = typeof Mode.Type;

/** One employee's standing permission for one capability. Immutable: a change is a new grant. */
export const Grant = Schema.Struct({
  id: Schema.String,
  capability: Schema.String,
  mode: Mode,
  /** Values for the capability's own constraint fields; empty means no extra limits. */
  constraints: Schema.Record(Schema.String, Schema.Unknown),
  /** The area of accountability this grant serves, e.g. "Launch". */
  responsibility: Schema.NullOr(Schema.String),
  created_at: Timestamp,
});
export type Grant = typeof Grant.Type;

export type Outcome =
  | { outcome: "allow"; grantId: string }
  | { outcome: "ask"; grantId: string; decisionId?: string }
  | { outcome: "deny"; reason: string };

/** A one-off owner approval of one exact request. Single-use; expires to rejected. */
export const Decision = Schema.Struct({
  id: Schema.String,
  employee_id: Schema.String,
  capability: Schema.String,
  /** The exact input the employee asked to run. */
  input: Schema.Unknown,
  work_item_id: Schema.NullOr(Schema.String),
  /** The conversation the asking turn was answering; the answer is posted there. */
  conversation: Schema.NullOr(ConversationKey),
  status: Schema.Literals(["pending", "approved", "rejected", "used"]),
  requested_at: Timestamp,
  expires_at: Timestamp,
});
export type Decision = typeof Decision.Type;
