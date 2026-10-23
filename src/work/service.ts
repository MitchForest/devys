import { database, isoText, type Database } from "../data/database.ts";
import type { WorkItem, WorkItemState, WorkResult, WorkStep } from "./contract.ts";

const columns = `id, owner_employee_id, title, objective, next_action, wait_condition, due_at, wake_at, woken_at, state,
  project_id, conditions, evidence, steps, results, revision, taken_over_by, created_by, updated_at`;

export const workItems = (db: Database, businessId: string, since?: string) =>
  database(db, (sql) =>
    sql.rows<WorkItem>(
      `SELECT ${columns} FROM work_items
       WHERE business_id = $1 AND ($2::timestamptz IS NULL OR updated_at > $2)
       ORDER BY updated_at DESC LIMIT 200`,
      [businessId, since ?? null],
    ),
  );

export const workItem = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.row<WorkItem>(`SELECT ${columns} FROM work_items WHERE business_id = $1 AND id = $2`, [
      businessId,
      id,
    ]),
  );

export const createWorkItem = (
  db: Database,
  businessId: string,
  input: {
    /** A new id, or one derived from the operation so a retried create makes one item. */
    id: string;
    owner: string;
    title: string;
    objective?: string;
    nextAction?: string;
    dueAt?: string;
    conditions?: WorkItem["conditions"];
    /** The project it belongs to; the caller has checked it is this business's. */
    projectId?: string;
    createdBy: string;
    /** A person who drives it from the start: in progress and never dispatched until handed back. */
    takenOverBy?: string;
    /** Its plan from the start. */
    steps?: readonly WorkStep[];
    /** A plan that waits for the owner's Start (`proposed`) before it is handed out. */
    waitsForStart?: boolean;
  },
) =>
  database(db, async (sql) => {
    await sql.run(
      `INSERT INTO work_items (id, business_id, owner_employee_id, title, objective, next_action,
         due_at, conditions, created_by, taken_over_by, project_id, steps, state)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
         CASE WHEN $10::text IS NOT NULL THEN 'in_progress'
           WHEN $13::boolean THEN 'proposed' ELSE 'ready' END)
       ON CONFLICT (id) DO NOTHING`,
      [
        input.id,
        businessId,
        input.owner,
        input.title,
        input.objective ?? "",
        input.nextAction ?? "",
        input.dueAt ?? null,
        JSON.stringify(input.conditions ?? {}),
        input.createdBy,
        input.takenOverBy ?? null,
        input.projectId ?? null,
        JSON.stringify(input.steps ?? []),
        input.waitsForStart ?? false,
      ],
    );
    // A retry finds the item its first attempt made; an id of another business finds nothing.
    const created = await sql.row<WorkItem>(
      `SELECT ${columns} FROM work_items WHERE business_id = $1 AND id = $2`,
      [businessId, input.id],
    );
    if (!created) throw new Error("A work item with this id belongs to another business");
    return created;
  });

export interface Change {
  title?: string;
  owner?: string;
  state?: WorkItemState;
  nextAction?: string;
  waitCondition?: string | null;
  dueAt?: string | null;
  /** A follow-up while `waiting` (null clears it). Any other state clears it too. */
  wakeAt?: string | null;
  evidence?: { by: string; note: string };
  /** The whole plan, replacing the last. */
  steps?: readonly WorkStep[];
  /** The whole list of results, replacing the last. */
  results?: readonly WorkResult[];
}

/**
 * Applies a change at an expected revision. Nothing (undefined) means the revision was
 * stale or a person took the work over: a conflict, never an overwrite.
 */
export const updateWorkItem = (
  db: Database,
  businessId: string,
  id: string,
  expectedRevision: number,
  change: Change,
  actor: { kind: "person" | "employee"; id: string },
) =>
  database(db, async (sql) => {
    const updated = await sql.row<WorkItem>(
      `UPDATE work_items SET
         title = coalesce($4, title),
         owner_employee_id = coalesce($5, owner_employee_id),
         state = coalesce($6, state),
         next_action = coalesce($7, next_action),
         wait_condition = CASE WHEN $8::boolean THEN $9 ELSE wait_condition END,
         due_at = CASE WHEN $10::boolean THEN $11::timestamptz ELSE due_at END,
         wake_at = CASE WHEN coalesce($6, state) <> 'waiting' THEN NULL
           WHEN $14::boolean THEN $15::timestamptz ELSE wake_at END,
         woken_at = NULL,
         evidence = CASE WHEN $12::jsonb IS NULL THEN evidence
           ELSE evidence || jsonb_build_array($12::jsonb || jsonb_build_object('at', ${isoText("now()")})) END,
         steps = coalesce($16::jsonb, steps),
         results = coalesce($17::jsonb, results),
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
        change.wakeAt !== undefined,
        change.wakeAt ?? null,
        change.steps ? JSON.stringify(change.steps) : null,
        change.results ? JSON.stringify(change.results) : null,
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
  entry: Omit<WorkItem["evidence"][number], "at">,
) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE work_items SET
         evidence = evidence || jsonb_build_array($3::jsonb || jsonb_build_object('at', ${isoText("now()")})),
         revision = revision + 1, updated_at = now()
       WHERE business_id = $1 AND id = $2
         AND ($4::text IS NULL OR NOT evidence @> jsonb_build_array(jsonb_build_object('source', $4::text)))`,
      [businessId, id, JSON.stringify(entry), entry.source ?? null],
    ),
  );

/**
 * Hands every open work item of one employee to another, as when the first retires.
 * Work in progress goes back to ready, so the dispatcher gives it to the new owner.
 */
export const reassignOpen = (db: Database, businessId: string, from: string, to: string) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE work_items SET owner_employee_id = $3,
         state = CASE WHEN state = 'in_progress' THEN 'ready' ELSE state END,
         revision = revision + 1, updated_at = now()
       WHERE business_id = $1 AND owner_employee_id = $2
         AND state NOT IN ('completed', 'cancelled')`,
      [businessId, from, to],
    ),
  );

/**
 * Follow-ups: waiting work whose wake time has come becomes ready, once (the wake time is
 * cleared), so the dispatcher hands it to its employee. Work a person took over stays theirs.
 */
export const wakeFollowUps = (db: Database) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE work_items SET state = 'ready', woken_at = wake_at, wake_at = NULL,
         revision = revision + 1, updated_at = now()
       WHERE state = 'waiting' AND wake_at <= now() AND taken_over_by IS NULL`,
    ),
  );

/** Work in progress goes back to ready, so the dispatcher hands it to its employee again. */
export const requeue = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE work_items SET state = 'ready', revision = revision + 1, updated_at = now()
       WHERE business_id = $1 AND id = $2 AND state = 'in_progress'`,
      [businessId, id],
    ),
  );

/** The owner starts a plan that waited for them: it becomes ready and is handed out. */
export const startWorkItem = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.row<WorkItem>(
      `UPDATE work_items SET state = 'ready', revision = revision + 1, updated_at = now()
       WHERE business_id = $1 AND id = $2 AND state = 'proposed' RETURNING ${columns}`,
      [businessId, id],
    ),
  );

/** A person takes the work from its employee, or hands it back. */
export const setTakeover = (db: Database, businessId: string, id: string, person: string | null) =>
  database(db, (sql) =>
    sql.row<WorkItem>(
      `UPDATE work_items SET taken_over_by = $3, revision = revision + 1, updated_at = now()
       WHERE business_id = $1 AND id = $2 RETURNING ${columns}`,
      [businessId, id, person],
    ),
  );

/**
 * Ready work, soonest deadline first, skipping owners who take no work now so they cannot hold
 * up the rest. A due date is a deadline, never a start time: ready work is handed over now.
 */
export const readyWorkItems = (db: Database, skipOwners: readonly string[], limit = 20) =>
  database(db, (sql) =>
    sql.rows<WorkItem & { business_id: string }>(
      `SELECT business_id, ${columns} FROM work_items
       WHERE state = 'ready' AND taken_over_by IS NULL
         AND submitted_revision IS DISTINCT FROM revision AND owner_employee_id <> ALL($2::text[])
       ORDER BY due_at NULLS LAST, created_at LIMIT $1`,
      [limit, skipOwners],
    ),
  );

/**
 * Records that this revision reached the employee's runtime (Pi dedupes resubmission). A
 * later revision made before this lands (the employee's own turn already changing it) is
 * covered by the same hand-off, so it is not handed over a second time.
 */
export const markSubmitted = (db: Database, id: string, revision: number) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE work_items
       SET state = CASE WHEN state = 'ready' THEN 'in_progress' ELSE state END,
         submitted_revision = revision
       WHERE id = $1 AND revision >= $2 AND submitted_revision IS DISTINCT FROM revision`,
      [id, revision],
    ),
  );
