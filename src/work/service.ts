import { database, type Database } from "../data/database.ts";
import type { Commitment, CommitmentState } from "./contract.ts";

const columns = `id, owner_employee_id, title, objective, next_action, wait_condition, due_at, state,
  conditions, evidence, revision, taken_over_by, created_by, updated_at`;

export const commitments = (db: Database, businessId: string, since?: string) =>
  database(db, (sql) =>
    sql.rows<Commitment>(
      `SELECT ${columns} FROM commitments
       WHERE business_id = $1 AND ($2::timestamptz IS NULL OR updated_at > $2)
       ORDER BY updated_at DESC LIMIT 200`,
      [businessId, since ?? null],
    ),
  );

export const commitment = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.row<Commitment>(`SELECT ${columns} FROM commitments WHERE business_id = $1 AND id = $2`, [
      businessId,
      id,
    ]),
  );

export const createCommitment = (
  db: Database,
  businessId: string,
  input: {
    owner: string;
    title: string;
    objective?: string;
    nextAction?: string;
    dueAt?: string;
    conditions?: Commitment["conditions"];
    createdBy: string;
    /** A person who drives it from the start: in progress and never dispatched until handed back. */
    takenOverBy?: string;
  },
) =>
  database(db, async (sql) => {
    const created = await sql.row<Commitment>(
      `INSERT INTO commitments (id, business_id, owner_employee_id, title, objective, next_action,
         due_at, conditions, created_by, taken_over_by, state)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
         CASE WHEN $10::text IS NULL THEN 'ready' ELSE 'in_progress' END) RETURNING ${columns}`,
      [
        crypto.randomUUID(),
        businessId,
        input.owner,
        input.title,
        input.objective ?? "",
        input.nextAction ?? "",
        input.dueAt ?? null,
        JSON.stringify(input.conditions ?? {}),
        input.createdBy,
        input.takenOverBy ?? null,
      ],
    );
    return created!;
  });

export interface Change {
  title?: string;
  owner?: string;
  state?: CommitmentState;
  nextAction?: string;
  waitCondition?: string | null;
  dueAt?: string | null;
  evidence?: { by: string; note: string };
}

/**
 * Applies a change at an expected revision. Nothing (undefined) means the revision was
 * stale or a person took the work over: a conflict, never an overwrite.
 */
export const updateCommitment = (
  db: Database,
  businessId: string,
  id: string,
  expectedRevision: number,
  change: Change,
  actor: { kind: "person" | "employee"; id: string },
) =>
  database(db, async (sql) => {
    const updated = await sql.row<Commitment>(
      `UPDATE commitments SET
         title = coalesce($4, title),
         owner_employee_id = coalesce($5, owner_employee_id),
         state = coalesce($6, state),
         next_action = coalesce($7, next_action),
         wait_condition = CASE WHEN $8::boolean THEN $9 ELSE wait_condition END,
         due_at = CASE WHEN $10::boolean THEN $11::timestamptz ELSE due_at END,
         evidence = CASE WHEN $12::jsonb IS NULL THEN evidence
           ELSE evidence || jsonb_build_array($12::jsonb || jsonb_build_object('at', now())) END,
         revision = revision + 1,
         updated_at = now()
       WHERE business_id = $1 AND id = $2 AND revision = $3
         AND ($13 = 'person' OR taken_over_by IS NULL)
       RETURNING ${columns}`,
      [
        businessId,
        id,
        expectedRevision,
        change.title ?? null,
        change.owner ?? null,
        change.state ?? null,
        change.nextAction ?? null,
        change.waitCondition !== undefined,
        change.waitCondition ?? null,
        change.dueAt !== undefined,
        change.dueAt ?? null,
        change.evidence ? JSON.stringify(change.evidence) : null,
        actor.kind,
      ],
    );
    return updated;
  });

/**
 * Records a fact about the work, such as an accepted commit or the check run against it.
 * Evidence is appended even while a person holds the work: it says what happened. An entry
 * with a `source` already recorded changes nothing, so redelivered events add nothing.
 */
export const addEvidence = (
  db: Database,
  businessId: string,
  id: string,
  entry: Omit<Commitment["evidence"][number], "at">,
) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE commitments SET
         evidence = evidence || jsonb_build_array($3::jsonb || jsonb_build_object('at', now())),
         revision = revision + 1, updated_at = now()
       WHERE business_id = $1 AND id = $2
         AND ($4::text IS NULL OR NOT evidence @> jsonb_build_array(jsonb_build_object('source', $4::text)))`,
      [businessId, id, JSON.stringify(entry), entry.source ?? null],
    ),
  );

/**
 * Hands every open commitment of one employee to another, as when the first retires.
 * Work in progress goes back to ready, so the dispatcher gives it to the new owner.
 */
export const reassignOpen = (db: Database, businessId: string, from: string, to: string) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE commitments SET owner_employee_id = $3,
         state = CASE WHEN state = 'in_progress' THEN 'ready' ELSE state END,
         revision = revision + 1, updated_at = now()
       WHERE business_id = $1 AND owner_employee_id = $2
         AND state NOT IN ('completed', 'cancelled')`,
      [businessId, from, to],
    ),
  );

/** Work in progress goes back to ready, so the dispatcher hands it to its employee again. */
export const requeue = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE commitments SET state = 'ready', revision = revision + 1, updated_at = now()
       WHERE business_id = $1 AND id = $2 AND state = 'in_progress'`,
      [businessId, id],
    ),
  );

/** A person takes the work from its employee, or hands it back. */
export const setTakeover = (db: Database, businessId: string, id: string, person: string | null) =>
  database(db, (sql) =>
    sql.row<Commitment>(
      `UPDATE commitments SET taken_over_by = $3, revision = revision + 1, updated_at = now()
       WHERE business_id = $1 AND id = $2 RETURNING ${columns}`,
      [businessId, id, person],
    ),
  );

/** Ready work whose current revision hasn't been handed to its employee yet. */
/** Ready, due work, skipping owners who take no work now so they cannot hold up the rest. */
export const dueCommitments = (db: Database, skipOwners: readonly string[], limit = 20) =>
  database(db, (sql) =>
    sql.rows<Commitment & { business_id: string }>(
      `SELECT business_id, ${columns} FROM commitments
       WHERE state = 'ready' AND (due_at IS NULL OR due_at <= now()) AND taken_over_by IS NULL
         AND submitted_revision IS DISTINCT FROM revision AND owner_employee_id <> ALL($2::text[])
       ORDER BY coalesce(due_at, created_at) LIMIT $1`,
      [limit, skipOwners],
    ),
  );

/** Records that this revision reached the employee's runtime. Pi dedupes resubmission. */
export const markSubmitted = (db: Database, id: string, revision: number) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE commitments SET state = 'in_progress', submitted_revision = revision
       WHERE id = $1 AND revision = $2 AND state = 'ready'`,
      [id, revision],
    ),
  );
