import { database, type Database, type Sql } from "../data/database.ts";
import type { Project, ProjectItem } from "./contract.ts";

type Row = {
  id: string;
  name: string;
  goal: string | null;
  deadline: string | null;
  budget_cents: number | null;
  budget_currency: string | null;
  lead_employee_id: string | null;
};

const columns = `id, name, goal, to_char(deadline, 'YYYY-MM-DD') AS deadline, budget_cents,
  budget_currency, lead_employee_id`;

async function load(sql: Sql, businessId: string, id?: string): Promise<Project[]> {
  const only = id ?? null;
  const [rows, members, items] = await Promise.all([
    sql.rows<Row>(
      `SELECT ${columns} FROM projects WHERE business_id = $1 AND ($2::text IS NULL OR id = $2)
       ORDER BY created_at, id`,
      [businessId, only],
    ),
    sql.rows<{ project_id: string; employee_id: string }>(
      `SELECT project_id, employee_id FROM project_members
       WHERE business_id = $1 AND ($2::text IS NULL OR project_id = $2) ORDER BY created_at`,
      [businessId, only],
    ),
    sql.rows<ProjectItem & { project_id: string }>(
      `SELECT id, project_id, kind, ref FROM project_items
       WHERE business_id = $1 AND ($2::text IS NULL OR project_id = $2) ORDER BY created_at, id`,
      [businessId, only],
    ),
  ]);
  return rows.map(({ budget_cents, budget_currency, ...project }) => ({
    ...project,
    budget:
      budget_cents === null || budget_currency === null
        ? null
        : { cents: budget_cents, currency: budget_currency },
    member_ids: members
      .filter((member) => member.project_id === project.id)
      .map((member) => member.employee_id),
    items: items
      .filter((item) => item.project_id === project.id)
      .map(({ id, kind, ref }) => ({ id, kind, ref })),
  }));
}

/** Every project in the business, with its members and references, oldest first. */
export const projects = (db: Database, businessId: string) =>
  database(db, (sql) => load(sql, businessId));

export const project = (db: Database, businessId: string, id: string) =>
  database(db, async (sql) => (await load(sql, businessId, id))[0]);

export interface ProjectChange {
  name?: string;
  goal?: string | null;
  deadline?: string | null;
  budget?: Project["budget"];
  lead?: string;
  /** The whole set of assigned employees, replacing the current one. */
  members?: readonly string[];
}

async function setMembers(sql: Sql, businessId: string, id: string, members: readonly string[]) {
  await sql.run(
    `DELETE FROM project_members WHERE business_id = $1 AND project_id = $2
       AND employee_id <> ALL($3::text[])`,
    [businessId, id, [...members]],
  );
  await sql.run(
    `INSERT INTO project_members (business_id, project_id, employee_id)
     SELECT $1, $2, unnest($3::text[]) ON CONFLICT DO NOTHING`,
    [businessId, id, [...members]],
  );
}

/** The caller has checked the lead and members are employees of this business. */
export const createProject = (
  db: Database,
  businessId: string,
  input: ProjectChange & { name: string },
) =>
  database(
    db,
    async (sql) => {
      const id = crypto.randomUUID();
      await sql.run(
        `INSERT INTO projects (id, business_id, name, goal, deadline, budget_cents,
           budget_currency, lead_employee_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [
          id,
          businessId,
          input.name,
          input.goal ?? null,
          input.deadline ?? null,
          input.budget?.cents ?? null,
          input.budget?.currency ?? null,
          input.lead ?? null,
        ],
      );
      await setMembers(sql, businessId, id, input.members ?? []);
      return (await load(sql, businessId, id))[0]!;
    },
    { transaction: true },
  );

/**
 * Changes what is given: a name, goal, deadline or budget (null clears one), the lead, or the
 * members. Undefined when there is no such project.
 */
export const updateProject = (
  db: Database,
  businessId: string,
  id: string,
  change: ProjectChange,
) =>
  database(
    db,
    async (sql) => {
      const changed = await sql.run(
        `UPDATE projects SET name = coalesce($3, name),
           goal = CASE WHEN $4::boolean THEN $5 ELSE goal END,
           deadline = CASE WHEN $6::boolean THEN $7::date ELSE deadline END,
           budget_cents = CASE WHEN $8::boolean THEN $9::bigint ELSE budget_cents END,
           budget_currency = CASE WHEN $8::boolean THEN $10 ELSE budget_currency END,
           lead_employee_id = coalesce($11, lead_employee_id)
         WHERE business_id = $1 AND id = $2`,
        [
          businessId,
          id,
          change.name ?? null,
          change.goal !== undefined,
          change.goal ?? null,
          change.deadline !== undefined,
          change.deadline ?? null,
          change.budget !== undefined,
          change.budget?.cents ?? null,
          change.budget?.currency ?? null,
          change.lead ?? null,
        ],
      );
      if (!changed) return undefined;
      if (change.members) await setMembers(sql, businessId, id, change.members);
      return (await load(sql, businessId, id))[0];
    },
    { transaction: true },
  );

/**
 * Shows a record in a project. The caller has already checked the record belongs to this
 * business. Adding twice is a no-op; undefined when there is no such project.
 */
export const addToProject = (
  db: Database,
  businessId: string,
  projectId: string,
  item: { kind: ProjectItem["kind"]; ref: string },
) =>
  database(db, async (sql) => {
    if (
      !(await sql.row("SELECT 1 FROM projects WHERE business_id = $1 AND id = $2", [
        businessId,
        projectId,
      ]))
    )
      return undefined;
    await sql.run(
      `INSERT INTO project_items (id, business_id, project_id, kind, ref) VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (project_id, kind, ref) DO NOTHING`,
      [crypto.randomUUID(), businessId, projectId, item.kind, item.ref],
    );
    return (await sql.row<ProjectItem>(
      "SELECT id, kind, ref FROM project_items WHERE project_id = $1 AND kind = $2 AND ref = $3",
      [projectId, item.kind, item.ref],
    ))!;
  });

/** Takes a record out of a project. The record itself is untouched. */
export const removeFromProject = (
  db: Database,
  businessId: string,
  projectId: string,
  itemId: string,
) =>
  database(db, (sql) =>
    sql.run("DELETE FROM project_items WHERE business_id = $1 AND project_id = $2 AND id = $3", [
      businessId,
      projectId,
      itemId,
    ]),
  );
