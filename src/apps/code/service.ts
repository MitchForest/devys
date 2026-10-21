import type { Database } from "../../data/database.ts";
import { database } from "../../data/database.ts";
import type { CodingSession, Provider, Purpose, Started } from "./contract.ts";

const columns = `id, work_item_id, employee_id, provider, purpose, objective, repository,
  base_commit, branch, worktree, provider_session_id, created_at`;

/** Records the intent to start, before the host is asked. Recording it twice is harmless. */
export const recordCodingSession = (
  db: Database,
  businessId: string,
  intent: {
    id: string;
    workItemId: string;
    employeeId: string;
    provider: Provider;
    purpose: Purpose;
    objective: string;
    reviews?: string;
  },
) =>
  database(db, (sql) =>
    sql.run(
      `INSERT INTO coding_sessions (id, business_id, work_item_id, employee_id, provider, purpose,
         objective, reviews)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT (id) DO NOTHING`,
      [
        intent.id,
        businessId,
        intent.workItemId,
        intent.employeeId,
        intent.provider,
        intent.purpose,
        intent.objective,
        intent.reviews ?? null,
      ],
    ),
  );

/** Where the host started it. */
export const recordStarted = (db: Database, businessId: string, id: string, started: Started) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE coding_sessions SET repository = $3, base_commit = $4, branch = $5, worktree = $6,
         provider_session_id = $7
       WHERE business_id = $1 AND id = $2`,
      [
        businessId,
        id,
        started.repository,
        started.baseCommit,
        started.branch,
        started.worktree,
        started.providerSessionId,
      ],
    ),
  );

export const codingSession = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.row<CodingSession>(
      `SELECT ${columns} FROM coding_sessions WHERE business_id = $1 AND id = $2`,
      [businessId, id],
    ),
  );

/** A coding session by id alone, for events from the host, with the business it belongs to. */
export const codingSessionById = (db: Database, id: string) =>
  database(db, (sql) =>
    sql.row<CodingSession & { business_id: string }>(
      `SELECT business_id, ${columns} FROM coding_sessions WHERE id = $1`,
      [id],
    ),
  );

export const codingSessionsFor = (db: Database, businessId: string, workItemId: string) =>
  database(db, (sql) =>
    sql.rows<CodingSession>(
      `SELECT ${columns} FROM coding_sessions WHERE business_id = $1 AND work_item_id = $2
       ORDER BY created_at`,
      [businessId, workItemId],
    ),
  );

/** An employee's coding sessions that have started, for Stop. */
export const employeeCodingSessions = (db: Database, businessId: string, employeeId: string) =>
  database(db, (sql) =>
    sql.rows<CodingSession>(
      `SELECT ${columns} FROM coding_sessions
       WHERE business_id = $1 AND employee_id = $2 AND provider_session_id IS NOT NULL
       ORDER BY created_at DESC LIMIT 50`,
      [businessId, employeeId],
    ),
  );

/** Work items with coding sessions, most recently started first: the Code app's work. */
export const codedWork = (db: Database, businessId: string) =>
  database(db, async (sql) =>
    (
      await sql.rows<{ work_item_id: string }>(
        `SELECT work_item_id FROM coding_sessions
         WHERE business_id = $1 AND provider_session_id IS NOT NULL
         GROUP BY work_item_id ORDER BY max(created_at) DESC`,
        [businessId],
      )
    ).map((row) => row.work_item_id),
  );

/** The business's started coding sessions and the work item each belongs to, newest first. */
export const startedSessions = (db: Database, businessId: string) =>
  database(db, (sql) =>
    sql.rows<{ id: string; work_item_id: string }>(
      `SELECT id, work_item_id FROM coding_sessions
       WHERE business_id = $1 AND provider_session_id IS NOT NULL ORDER BY created_at DESC`,
      [businessId],
    ),
  );

/** Whether the business has any coding session: the Code app has records to show. */
export const hasCodingSessions = (db: Database, businessId: string) =>
  database(db, async (sql) =>
    Boolean(
      await sql.row("SELECT 1 FROM coding_sessions WHERE business_id = $1 LIMIT 1", [businessId]),
    ),
  );
