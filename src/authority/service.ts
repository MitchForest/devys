import { Schema } from "effect";
import { database, type Database, type Sql } from "../data/database.ts";
import type { Scope } from "../identity/contract.ts";
import type { Capability } from "../protocol/capability.ts";
import { sha256 } from "../protocol/bytes.ts";
import type { Decision, Grant, Mode, OwnerRequest, Outcome } from "./contract.ts";

const columns = "id, capability, mode, constraints, responsibility, created_at";

/** Whether this grant allows this exact input now. Constraints only ever narrow. */
export function decide(grant: Grant | undefined, capability: Capability, input: unknown): Outcome {
  if (!grant) return { outcome: "deny", reason: `Not granted: ${capability.name}` };
  if (capability.constraints) {
    let constraints: unknown;
    try {
      constraints = Schema.decodeUnknownSync(capability.constraints.schema)(grant.constraints);
    } catch {
      return { outcome: "deny", reason: `The grant for ${capability.name} has invalid limits` };
    }
    if (!capability.constraints.allows(constraints, input))
      return { outcome: "deny", reason: `Outside the limits of the grant for ${capability.name}` };
  }
  return grant.mode === "ask"
    ? { outcome: "ask", grantId: grant.id }
    : { outcome: "allow", grantId: grant.id };
}

/** The active grant, read fresh on every call so revocation applies immediately. */
export const activeGrant = (db: Database, scope: Scope, capability: string) =>
  database(db, (sql) =>
    sql.row<Grant>(
      `SELECT ${columns} FROM grants
       WHERE business_id = $1 AND employee_id = $2 AND capability = $3 AND revoked_at IS NULL`,
      [scope.businessId, scope.employeeId, capability],
    ),
  );

export const grantsFor = (db: Database, scope: Scope) =>
  database(db, (sql) =>
    sql.rows<Grant>(
      `SELECT ${columns} FROM grants
       WHERE business_id = $1 AND employee_id = $2 AND revoked_at IS NULL ORDER BY capability`,
      [scope.businessId, scope.employeeId],
    ),
  );

interface Grantable {
  capability: Capability;
  mode: Mode;
  constraints?: Record<string, unknown>;
  responsibility?: string;
}

/** Replaces any active grant for the capability. Constraints must fit its schema. */
async function insertGrant(sql: Sql, scope: Scope, input: Grantable) {
  const { capability } = input;
  const constraints = input.constraints ?? {};
  if (capability.constraints) Schema.decodeUnknownSync(capability.constraints.schema)(constraints);
  else if (Object.keys(constraints).length) throw new Error(`${capability.name} takes no limits`);
  await sql.run(
    `UPDATE grants SET revoked_at = now()
     WHERE business_id = $1 AND employee_id = $2 AND capability = $3 AND revoked_at IS NULL`,
    [scope.businessId, scope.employeeId, capability.name],
  );
  return (await sql.row<Grant>(
    `INSERT INTO grants (id, business_id, employee_id, capability, mode, constraints, responsibility)
     VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING ${columns}`,
    [
      crypto.randomUUID(),
      scope.businessId,
      scope.employeeId,
      capability.name,
      input.mode,
      JSON.stringify(constraints),
      input.responsibility ?? null,
    ],
  ))!;
}

export const grant = (db: Database, scope: Scope, input: Grantable) =>
  database(db, (sql) => insertGrant(sql, scope, input), { transaction: true });

/** Applies a role preset in one transaction. */
export const grantAll = (db: Database, scope: Scope, inputs: Grantable[]) =>
  database(
    db,
    async (sql) => {
      for (const input of inputs) await insertGrant(sql, scope, input);
    },
    { transaction: true },
  );

export const revokeGrant = (db: Database, scope: Scope, grantId: string) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE grants SET revoked_at = now()
       WHERE id = $1 AND business_id = $2 AND employee_id = $3 AND revoked_at IS NULL`,
      [grantId, scope.businessId, scope.employeeId],
    ),
  );

/** JSON with object keys sorted at every depth, so equal inputs hash equally. */
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object")
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`)
      .join(",")}}`;
  return JSON.stringify(value);
}

/**
 * Binds a request to the capability, the grant (its revision), the exact input and the work
 * it is for: approving it for one work item does not approve it for another.
 */
const requestHash = (
  grantId: string,
  capability: string,
  input: unknown,
  workItemId: string | null,
) => sha256(canonical({ capability, workItemId, grantId, input }));

const decisionLife = "24 hours";
const decisionColumns =
  "id, kind, employee_id, capability, input, work_item_id, conversation, status, requested_at, expires_at, signed_by";

/**
 * Settles an `ask`: uses an approved decision for this exact request once, or makes
 * sure one pending request exists and returns it. Runs in one transaction.
 */
export const settleAsk = (
  db: Database,
  scope: Scope,
  ask: {
    grantId: string;
    capability: string;
    input: unknown;
    workItemId?: string;
    conversation?: string;
  },
) =>
  database(
    db,
    async (sql): Promise<Outcome> => {
      const hash = await requestHash(
        ask.grantId,
        ask.capability,
        ask.input,
        ask.workItemId ?? null,
      );
      const used = await sql.run(
        `UPDATE decisions SET status = 'used', used_at = now()
         WHERE grant_id = $1 AND input_hash = $2 AND status = 'approved' AND expires_at > now()`,
        [ask.grantId, hash],
      );
      if (used === 1) return { outcome: "allow", grantId: ask.grantId };
      // The owner said no to exactly this: it is not asked again while that answer stands.
      const refused = await sql.row<{ id: string }>(
        `SELECT id FROM decisions WHERE grant_id = $1 AND input_hash = $2 AND status = 'rejected'
           AND decided_by IS NOT NULL AND decided_at > now() - interval '${decisionLife}'`,
        [ask.grantId, hash],
      );
      if (refused)
        return {
          outcome: "deny",
          reason:
            "The owner rejected exactly this request. Do not retry it another way; change the proposal or ask the owner in the conversation.",
        };
      // An expired open request is rejected, so a fresh one can be made.
      await sql.run(
        `UPDATE decisions SET status = 'rejected', decided_at = now()
         WHERE grant_id = $1 AND input_hash = $2 AND status IN ('pending', 'approved')
           AND expires_at <= now()`,
        [ask.grantId, hash],
      );
      await sql.run(
        `INSERT INTO decisions (id, business_id, employee_id, grant_id, capability, input, input_hash,
           work_item_id, conversation, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now() + interval '${decisionLife}')
         ON CONFLICT (grant_id, input_hash) WHERE status IN ('pending', 'approved') DO NOTHING`,
        [
          crypto.randomUUID(),
          scope.businessId,
          scope.employeeId,
          ask.grantId,
          ask.capability,
          JSON.stringify(ask.input),
          hash,
          ask.workItemId ?? null,
          ask.conversation ?? null,
        ],
      );
      const open = await sql.row<{ id: string }>(
        `SELECT id FROM decisions
         WHERE grant_id = $1 AND input_hash = $2 AND status IN ('pending', 'approved')`,
        [ask.grantId, hash],
      );
      return { outcome: "ask", grantId: ask.grantId, ...(open ? { decisionId: open.id } : {}) };
    },
    { transaction: true },
  );

/** Pending requests past their expiry become rejected (no one decided them). Run every minute. */
export const expireDecisions = (db: Database) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE decisions SET status = 'rejected', decided_at = now()
       WHERE status = 'pending' AND expires_at <= now()`,
    ),
  );

/** Requests waiting on the owner, newest first. Expired ones are not shown. */
export const pendingDecisions = (db: Database, businessId: string) =>
  database(db, (sql) =>
    sql.rows<Decision>(
      `SELECT ${decisionColumns} FROM decisions
       WHERE business_id = $1 AND status = 'pending' AND expires_at > now()
       ORDER BY requested_at DESC LIMIT 100`,
      [businessId],
    ),
  );

/** A work item's requests, newest first, whatever their answer: its page shows them. */
export const decisionsFor = (db: Database, businessId: string, workItemId: string) =>
  database(db, (sql) =>
    sql.rows<Decision>(
      `SELECT ${decisionColumns} FROM decisions
       WHERE business_id = $1 AND work_item_id = $2
       ORDER BY requested_at DESC LIMIT 20`,
      [businessId, workItemId],
    ),
  );

/** One request of the business, whatever its answer. */
export const decision = (db: Database, businessId: string, decisionId: string) =>
  database(db, (sql) =>
    sql.row<Decision>(
      `SELECT ${decisionColumns} FROM decisions WHERE id = $1 AND business_id = $2`,
      [decisionId, businessId],
    ),
  );

/**
 * Approves or rejects a pending, unexpired request once. Returns it, or null if it can't. A
 * spend approval is approved only with the signature that was verified for it (the table
 * refuses it otherwise); a take-over request is approved only by taking the work over.
 */
export const answerDecision = (
  db: Database,
  businessId: string,
  decisionId: string,
  answer: { approve: boolean; by: string; signed?: { keyId: string; signature: string } },
) =>
  database(db, async (sql) => {
    return sql.row<Decision>(
      `UPDATE decisions SET status = $3, decided_by = $4, decided_at = now(), signed_by = $5,
         signature = $6
       WHERE id = $1 AND business_id = $2 AND status = 'pending' AND expires_at > now()
         AND ($3 = 'rejected' OR kind <> 'take_over')
       RETURNING ${decisionColumns}`,
      [
        decisionId,
        businessId,
        answer.approve ? "approved" : "rejected",
        answer.by,
        answer.signed?.keyId ?? null,
        answer.signed?.signature ?? null,
      ],
    );
  });

/**
 * An employee's `askOwner`: the standing answer to exactly this request on this work item, if
 * one was given in the last day (or the open request), else a new pending request. Asking
 * again with the same input is how an employee reads the answer.
 */
export const askOwner = (
  db: Database,
  scope: Scope,
  ask: { grantId: string; request: OwnerRequest; workItemId: string; conversation: string },
) =>
  database(
    db,
    async (sql) => {
      const hash = await requestHash(ask.grantId, "askOwner", ask.request, ask.workItemId);
      const standing = await sql.row<Decision>(
        `SELECT ${decisionColumns} FROM decisions
         WHERE grant_id = $1 AND input_hash = $2 AND requested_at > now() - interval '${decisionLife}'
           AND status <> 'used' AND (status <> 'rejected' OR decided_by IS NOT NULL)
         ORDER BY requested_at DESC LIMIT 1`,
        [ask.grantId, hash],
      );
      if (standing) return standing;
      // Older answers to the same request are spent, and unanswered ones lapsed: ask anew.
      await sql.run(
        `UPDATE decisions SET status = CASE status WHEN 'approved' THEN 'used' ELSE 'rejected' END,
           used_at = CASE status WHEN 'approved' THEN now() ELSE used_at END,
           decided_at = CASE status WHEN 'pending' THEN now() ELSE decided_at END
         WHERE grant_id = $1 AND input_hash = $2 AND status IN ('pending', 'approved')`,
        [ask.grantId, hash],
      );
      await sql.run(
        `INSERT INTO decisions (id, kind, business_id, employee_id, grant_id, capability, input,
           input_hash, work_item_id, conversation, expires_at)
         VALUES ($1, $2, $3, $4, $5, 'askOwner', $6, $7, $8, $9, now() + interval '${decisionLife}')
         ON CONFLICT (grant_id, input_hash) WHERE status IN ('pending', 'approved') DO NOTHING`,
        [
          crypto.randomUUID(),
          ask.request.kind,
          scope.businessId,
          scope.employeeId,
          ask.grantId,
          JSON.stringify(ask.request),
          hash,
          ask.workItemId,
          ask.conversation,
        ],
      );
      return (await sql.row<Decision>(
        `SELECT ${decisionColumns} FROM decisions
         WHERE grant_id = $1 AND input_hash = $2 AND status IN ('pending', 'approved')`,
        [ask.grantId, hash],
      ))!;
    },
    { transaction: true },
  );

/** The owner took the work over: its pending take-over requests are being done. */
export const takeOverRequests = (
  db: Database,
  businessId: string,
  workItemId: string,
  by: string,
) =>
  database(db, (sql) =>
    sql.rows<Decision>(
      `UPDATE decisions SET status = 'approved', decided_by = $3, decided_at = now()
       WHERE business_id = $1 AND work_item_id = $2 AND kind = 'take_over' AND status = 'pending'
         AND expires_at > now()
       RETURNING ${decisionColumns}`,
      [businessId, workItemId, by],
    ),
  );

/** The owner handed the work back: the take-over requests they were doing are done. */
export const handBackRequests = (db: Database, businessId: string, workItemId: string) =>
  database(db, (sql) =>
    sql.rows<Decision>(
      `UPDATE decisions SET status = 'used', used_at = now()
       WHERE business_id = $1 AND work_item_id = $2 AND kind = 'take_over' AND status = 'approved'
       RETURNING ${decisionColumns}`,
      [businessId, workItemId],
    ),
  );

/** What the business has approved spending, in cents of one currency: its signed approvals. */
export const spentCents = (db: Database, businessId: string, currency: string) =>
  database(db, async (sql) => {
    const row = await sql.row<{ cents: number | null }>(
      `SELECT sum((input -> 'amount' ->> 'cents')::bigint) AS cents FROM decisions
       WHERE business_id = $1 AND kind = 'approve' AND status IN ('approved', 'used')
         AND signature IS NOT NULL AND input -> 'amount' ->> 'currency' = $2`,
      [businessId, currency],
    );
    return row?.cents === null || row?.cents === undefined ? null : Number(row.cents);
  });

/**
 * The owner added a secret: the pending `askOwner` requests for that name are answered. A card
 * answers a request for a card only, and a plain secret one for a plain secret.
 */
export const secretProvided = (
  db: Database,
  businessId: string,
  secret: { name: string; spend: boolean },
  by: string,
) =>
  database(db, (sql) =>
    sql.rows<Decision>(
      `UPDATE decisions SET status = 'approved', decided_by = $4, decided_at = now()
       WHERE business_id = $1 AND kind = 'secret' AND status = 'pending' AND expires_at > now()
         AND input ->> 'name' = $2 AND coalesce((input ->> 'spend')::boolean, false) = $3
       RETURNING ${decisionColumns}`,
      [businessId, secret.name, secret.spend, by],
    ),
  );

/**
 * Spends a signed spend approval on one card fill: approved, signed, unexpired and unused, of
 * this work item. It is used from then on; returned only if the fill sent nothing.
 */
export const claimSpend = (db: Database, businessId: string, workItemId: string, id: string) =>
  database(db, (sql) =>
    sql.row<Decision>(
      `UPDATE decisions SET status = 'used', used_at = now()
       WHERE id = $1 AND business_id = $2 AND work_item_id = $3 AND kind = 'approve'
         AND status = 'approved' AND signature IS NOT NULL AND input -> 'amount' IS NOT NULL
         AND expires_at > now()
       RETURNING ${decisionColumns}`,
      [id, businessId, workItemId],
    ),
  );

/** A claimed spend approval back to approved: its fill was refused before anything was sent. */
export const unclaimSpend = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE decisions SET status = 'approved', used_at = NULL
       WHERE id = $1 AND business_id = $2 AND kind = 'approve' AND status = 'used'
         AND signature IS NOT NULL`,
      [id, businessId],
    ),
  );
