import { database, type Database } from "../data/database.ts";
import type { Business, Employee, Look, Person, RoleTemplateId, Scope } from "./contract.ts";

export const activePerson = (db: Database, personId: string) =>
  database(db, (sql) =>
    sql.row<Person>("SELECT id, display_name FROM people WHERE id = $1 AND revoked_at IS NULL", [
      personId,
    ]),
  );

export const businessesFor = (db: Database, personId: string) =>
  database(db, (sql) =>
    sql.rows<Business>(
      `SELECT b.id, b.name, b.look, b.brief FROM businesses b JOIN memberships m ON m.business_id = b.id
       WHERE m.person_id = $1 ORDER BY b.created_at, b.id`,
      [personId],
    ),
  );

/** The business, if this active person is a member of it; otherwise nothing. */
export const memberBusiness = (db: Database, personId: string, businessId: string) =>
  database(db, (sql) =>
    sql.row<Business>(
      `SELECT b.id, b.name, b.look, b.brief FROM businesses b JOIN memberships m ON m.business_id = b.id
       JOIN people p ON p.id = m.person_id
       WHERE m.person_id = $1 AND b.id = $2 AND p.revoked_at IS NULL`,
      [personId, businessId],
    ),
  );

export const businessName = (db: Database, businessId: string) =>
  database(
    db,
    async (sql) =>
      (await sql.row<{ name: string }>("SELECT name FROM businesses WHERE id = $1", [businessId]))
        ?.name,
  );

export const employeesOf = (db: Database, businessId: string) =>
  database(db, (sql) =>
    sql.rows<Employee>(
      `SELECT id, business_id, name, role, model, template, paused_at IS NOT NULL AS paused, look FROM employees
       WHERE business_id = $1 AND revoked_at IS NULL ORDER BY created_at, id`,
      [businessId],
    ),
  );

/** An active employee of exactly this business. */
export const activeEmployee = (db: Database, scope: Scope) =>
  database(db, (sql) =>
    sql.row<Employee>(
      `SELECT id, business_id, name, role, model, template, paused_at IS NOT NULL AS paused, look FROM employees
       WHERE business_id = $1 AND id = $2 AND revoked_at IS NULL`,
      [scope.businessId, scope.employeeId],
    ),
  );

/** Creates a business owned by this person, staffed with a Head of Operations. */
export const createBusiness = (
  db: Database,
  personId: string,
  input: {
    name: string;
    brief: string;
    model: string;
    operations: { name: string; role: string };
  },
) =>
  database(
    db,
    async (sql) => {
      const { name, brief, model } = input;
      const business: Business = { id: crypto.randomUUID(), name, look: null, brief };
      const operations: Employee = {
        id: crypto.randomUUID(),
        business_id: business.id,
        name: input.operations.name,
        role: input.operations.role,
        model,
        template: "operations",
        paused: false,
        look: null,
      };
      await sql.run("INSERT INTO businesses (id, name, brief) VALUES ($1, $2, $3)", [
        business.id,
        name,
        brief,
      ]);
      const member = await sql.run(
        `INSERT INTO memberships (business_id, person_id, role)
         SELECT $1, id, 'owner' FROM people WHERE id = $2 AND revoked_at IS NULL`,
        [business.id, personId],
      );
      if (member !== 1) throw new Error("Person is not active");
      await sql.run(
        `INSERT INTO employees (id, business_id, name, role, model, template)
         VALUES ($1, $2, $3, $4, $5, 'operations')`,
        [operations.id, business.id, operations.name, operations.role, model],
      );
      return { business, operations };
    },
    { transaction: true },
  );

export const createEmployee = (
  db: Database,
  businessId: string,
  input: { name: string; role: string; model: string; template: RoleTemplateId },
) =>
  database(db, async (sql) => {
    const employee: Employee = {
      id: crypto.randomUUID(),
      business_id: businessId,
      ...input,
      paused: false,
      look: null,
    };
    await sql.run(
      `INSERT INTO employees (id, business_id, name, role, model, template)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [employee.id, businessId, input.name, input.role, input.model, input.template],
    );
    return employee;
  });

/** Renames an employee or rewrites its responsibilities. */
export const updateEmployee = (
  db: Database,
  scope: Scope,
  change: { name?: string; role?: string },
) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE employees SET name = coalesce($3, name), role = coalesce($4, role)
       WHERE business_id = $1 AND id = $2 AND revoked_at IS NULL`,
      [scope.businessId, scope.employeeId, change.name ?? null, change.role ?? null],
    ),
  );

/** Retires an employee: it takes no further actions; its records and history remain. */
export const retireEmployee = (db: Database, scope: Scope) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE employees SET revoked_at = now()
       WHERE business_id = $1 AND id = $2 AND revoked_at IS NULL AND template <> 'operations'`,
      [scope.businessId, scope.employeeId],
    ),
  );

/** Renames a business or rewrites its brief. */
export const updateBusiness = (
  db: Database,
  businessId: string,
  change: { name?: string; brief?: string },
) =>
  database(db, (sql) =>
    sql.run(
      "UPDATE businesses SET name = coalesce($2, name), brief = coalesce($3, brief) WHERE id = $1",
      [businessId, change.name ?? null, change.brief ?? null],
    ),
  );

/** The brief every employee of the business reads. */
export const businessBrief = (db: Database, businessId: string) =>
  database(
    db,
    async (sql) =>
      (await sql.row<{ brief: string }>("SELECT brief FROM businesses WHERE id = $1", [businessId]))
        ?.brief ?? "",
  );

/** Changes the model an employee uses from its next conversation turn. */
export const setEmployeeModel = (db: Database, scope: Scope, model: string) =>
  database(db, (sql) =>
    sql.run(
      "UPDATE employees SET model = $3 WHERE business_id = $1 AND id = $2 AND revoked_at IS NULL",
      [scope.businessId, scope.employeeId, model],
    ),
  );

/** Pausing stops the employee's next action; resuming lets it act again. */
export const setPaused = (db: Database, scope: Scope, paused: boolean) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE employees SET paused_at = CASE WHEN $3 THEN coalesce(paused_at, now()) ELSE NULL END
       WHERE business_id = $1 AND id = $2 AND revoked_at IS NULL`,
      [scope.businessId, scope.employeeId, paused],
    ),
  );

/** The member and employee a chat on a channel reaches, while all three remain active. */
export const channelBinding = (db: Database, channel: string, sender: string, chat: string) =>
  database(db, async (sql) => {
    const row = await sql.row<{ person_id: string; business_id: string; employee_id: string }>(
      `SELECT c.person_id, c.business_id, c.employee_id FROM channel_bindings c
       JOIN people p ON p.id = c.person_id
       JOIN employees e ON e.business_id = c.business_id AND e.id = c.employee_id
       WHERE c.channel = $1 AND c.sender_id = $2 AND c.chat_id = $3
         AND c.revoked_at IS NULL AND p.revoked_at IS NULL AND e.revoked_at IS NULL`,
      [channel, sender, chat],
    );
    return row
      ? { personId: row.person_id, businessId: row.business_id, employeeId: row.employee_id }
      : undefined;
  });

/** Binds a chat on a channel to one employee. An existing binding is never transferred. */
export const bindChannel = (
  db: Database,
  input: { channel: string; personId: string; scope: Scope; sender: string; chat: string },
) =>
  database(db, async (sql) => {
    await sql.run(
      `INSERT INTO channel_bindings (id, business_id, employee_id, person_id, channel, sender_id, chat_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (channel, sender_id, chat_id) DO NOTHING`,
      [
        crypto.randomUUID(),
        input.scope.businessId,
        input.scope.employeeId,
        input.personId,
        input.channel,
        input.sender,
        input.chat,
      ],
    );
    const bound = await sql.row<{ person_id: string; business_id: string; employee_id: string }>(
      "SELECT person_id, business_id, employee_id FROM channel_bindings WHERE channel = $1 AND sender_id = $2 AND chat_id = $3",
      [input.channel, input.sender, input.chat],
    );
    if (
      bound?.person_id !== input.personId ||
      bound.business_id !== input.scope.businessId ||
      bound.employee_id !== input.scope.employeeId
    )
      throw new Error("That chat is already bound elsewhere");
  });

/** Sets how a business appears; null restores its initial. */
export const setBusinessLook = (db: Database, businessId: string, look: Look | null) =>
  database(db, (sql) =>
    sql.run("UPDATE businesses SET look = $2 WHERE id = $1", [
      businessId,
      look && JSON.stringify(look),
    ]),
  );

/** Sets how an employee appears; null restores its default Face. */
export const setEmployeeLook = (db: Database, scope: Scope, look: Look | null) =>
  database(db, (sql) =>
    sql.run(
      "UPDATE employees SET look = $3 WHERE business_id = $1 AND id = $2 AND revoked_at IS NULL",
      [scope.businessId, scope.employeeId, look && JSON.stringify(look)],
    ),
  );
