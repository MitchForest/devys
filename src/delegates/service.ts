import type { Database } from "../data/database.ts";
import { database } from "../data/database.ts";
import type { Assignment, Provider, Purpose, Started } from "./contract.ts";

const columns = `id, commitment_id, employee_id, provider, purpose, objective, repository,
  base_commit, branch, worktree, session_id, created_at`;

/** Records the intent to start, before the host is asked. Recording it twice is harmless. */
export const recordAssignment = (
  db: Database,
  businessId: string,
  intent: {
    id: string;
    commitmentId: string;
    employeeId: string;
    provider: Provider;
    purpose: Purpose;
    objective: string;
    reviews?: string;
  },
) =>
  database(db, (sql) =>
    sql.run(
      `INSERT INTO assignments (id, business_id, commitment_id, employee_id, provider, purpose,
         objective, reviews)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT (id) DO NOTHING`,
      [
        intent.id,
        businessId,
        intent.commitmentId,
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
      `UPDATE assignments SET repository = $3, base_commit = $4, branch = $5, worktree = $6,
         session_id = $7
       WHERE business_id = $1 AND id = $2`,
      [
        businessId,
        id,
        started.repository,
        started.baseCommit,
        started.branch,
        started.worktree,
        started.sessionId,
      ],
    ),
  );

export const assignment = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.row<Assignment>(`SELECT ${columns} FROM assignments WHERE business_id = $1 AND id = $2`, [
      businessId,
      id,
    ]),
  );

/** An assignment by id alone, for events from the host, with the business it belongs to. */
export const assignmentById = (db: Database, id: string) =>
  database(db, (sql) =>
    sql.row<Assignment & { business_id: string }>(
      `SELECT business_id, ${columns} FROM assignments WHERE id = $1`,
      [id],
    ),
  );

export const assignmentsFor = (db: Database, businessId: string, commitmentId: string) =>
  database(db, (sql) =>
    sql.rows<Assignment>(
      `SELECT ${columns} FROM assignments WHERE business_id = $1 AND commitment_id = $2
       ORDER BY created_at`,
      [businessId, commitmentId],
    ),
  );

/** An employee's assignments that have started, for Stop. */
export const employeeAssignments = (db: Database, businessId: string, employeeId: string) =>
  database(db, (sql) =>
    sql.rows<Assignment>(
      `SELECT ${columns} FROM assignments
       WHERE business_id = $1 AND employee_id = $2 AND session_id IS NOT NULL
       ORDER BY created_at DESC LIMIT 50`,
      [businessId, employeeId],
    ),
  );

/** Work items with coding sessions, most recently started first: the Code app's work. */
export const codedWork = (db: Database, businessId: string) =>
  database(db, async (sql) =>
    (
      await sql.rows<{ commitment_id: string }>(
        `SELECT commitment_id FROM assignments
         WHERE business_id = $1 AND session_id IS NOT NULL
         GROUP BY commitment_id ORDER BY max(created_at) DESC`,
        [businessId],
      )
    ).map((row) => row.commitment_id),
  );

/** Whether the business has any coding assignment: the Code app has records to show. */
export const hasAssignments = (db: Database, businessId: string) =>
  database(db, async (sql) =>
    Boolean(
      await sql.row("SELECT 1 FROM assignments WHERE business_id = $1 LIMIT 1", [businessId]),
    ),
  );
