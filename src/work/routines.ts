import { Cron } from "croner";
import cronstrue from "cronstrue";
import { database, type Database } from "../data/database.ts";
import type { ActiveHours, Routine, RoutineNotify, Trigger } from "./contract.ts";

type CronTrigger = Extract<Trigger, { kind: "cron" }>;

/** Runs closer together than this are refused: each run is a model turn. */
const shortestGap = 15 * 60_000;
/** How many scheduled slots are tried for one inside the active hours. */
const slotsTried = 2000;

const cronOf = (trigger: CronTrigger) =>
  new Cron(trigger.expression, { timezone: trigger.timezone, mode: "5-part" });

/** The weekday (`mon`) and minute of the day of a moment, in a time zone. */
function localTime(at: Date, timezone: string) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(at);
  const part = (type: string) => parts.find((item) => item.type === type)?.value ?? "";
  return {
    day: part("weekday").slice(0, 3).toLowerCase(),
    minute: Number(part("hour")) * 60 + Number(part("minute")),
  };
}

const minuteOf = (clock: string) => Number(clock.slice(0, 2)) * 60 + Number(clock.slice(3));

/** Whether a moment falls inside the active hours, in the routine's time zone. */
export function withinHours(hours: ActiveHours, timezone: string, at: Date) {
  const { day, minute } = localTime(at, timezone);
  if (hours.days && !(hours.days as readonly string[]).includes(day)) return false;
  const start = minuteOf(hours.start);
  const end = minuteOf(hours.end);
  return start < end ? minute >= start && minute < end : minute >= start || minute < end;
}

/**
 * The first scheduled slot after `after` inside the active hours, as an ISO timestamp; null when
 * none comes. Slots missed while nothing ran are not returned: the next is always after `after`.
 */
export function nextRun(trigger: CronTrigger, after: Date): string | null {
  const cron = cronOf(trigger);
  let at = cron.nextRun(after);
  for (let tried = 0; at && tried < slotsTried; tried++) {
    if (!trigger.hours || withinHours(trigger.hours, trigger.timezone, at)) return at.toISOString();
    at = cron.nextRun(at);
  }
  return null;
}

/** Why a trigger cannot be scheduled, or undefined when it can. */
export function triggerProblem(trigger: Trigger, now: Date): string | undefined {
  if (trigger.kind === "event") return undefined;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: trigger.timezone });
  } catch {
    return `Unknown time zone ${trigger.timezone}: use an IANA name such as America/New_York`;
  }
  let runs: Date[];
  try {
    runs = cronOf(trigger).nextRuns(20, now);
  } catch {
    return "Expected a cron expression with five fields: minute hour day-of-month month day-of-week";
  }
  if (
    runs.some((run, index) => index > 0 && run.getTime() - runs[index - 1]!.getTime() < shortestGap)
  )
    return "A routine runs at most every 15 minutes";
  if (trigger.hours && trigger.hours.start === trigger.hours.end)
    return "Active hours need a start and an end that differ";
  if (!nextRun(trigger, now)) return "The schedule never runs inside its active hours";
  return undefined;
}

const dayNames: Record<string, string> = {
  sun: "Sun",
  mon: "Mon",
  tue: "Tue",
  wed: "Wed",
  thu: "Thu",
  fri: "Fri",
  sat: "Sat",
};

/** A trigger in words, as the owner reads a proposal. */
export function describe(trigger: Trigger) {
  if (trigger.kind === "event") {
    const filters = Object.entries(trigger.filters).map(
      ([field, value]) => `${field} is ${JSON.stringify(value)}`,
    );
    return `When ${trigger.source} reports ${trigger.type}${filters.length ? ` where ${filters.join(" and ")}` : ""}`;
  }
  const hours = trigger.hours
    ? `, between ${trigger.hours.start} and ${trigger.hours.end}${
        trigger.hours.days ? ` on ${trigger.hours.days.map((day) => dayNames[day]).join(", ")}` : ""
      }`
    : "";
  return `${cronstrue.toString(trigger.expression, { use24HourTimeFormat: true })}${hours} (${trigger.timezone})`;
}

/** The result recorded for a run that found nothing and posted nothing. */
export const nothingToReport = "nothing to report";

const columns = `id, employee_id, project_id, title, instruction, trigger, notify, state, revision,
  next_run_at, last_run_at, last_result, created_by, updated_at`;
type Row = Omit<Routine, "schedule">;
const shown = (row: Row): Routine => ({ ...row, schedule: describe(row.trigger) });

/** The business's routines, newest change first; one employee's or one project's when given. */
export const routines = (
  db: Database,
  businessId: string,
  filter: { employeeId?: string; projectId?: string } = {},
) =>
  database(db, async (sql) =>
    (
      await sql.rows<Row>(
        `SELECT ${columns} FROM routines
         WHERE business_id = $1 AND ($2::text IS NULL OR employee_id = $2)
           AND ($3::text IS NULL OR project_id = $3)
         ORDER BY updated_at DESC LIMIT 200`,
        [businessId, filter.employeeId ?? null, filter.projectId ?? null],
      )
    ).map(shown),
  );

export const routine = (db: Database, businessId: string, id: string) =>
  database(db, async (sql) => {
    const row = await sql.row<Row>(
      `SELECT ${columns} FROM routines WHERE business_id = $1 AND id = $2`,
      [businessId, id],
    );
    return row && shown(row);
  });

export interface Proposal {
  employeeId: string;
  projectId: string | null;
  title: string;
  instruction: string;
  trigger: Trigger;
  notify: RoutineNotify;
}

/**
 * Records a proposed routine. `id` is derived from the operation, so a retried proposal makes
 * one routine; an id of another business finds nothing.
 */
export const proposeRoutine = (
  db: Database,
  businessId: string,
  id: string,
  proposal: Proposal,
  createdBy: string,
) =>
  database(db, async (sql) => {
    await sql.run(
      `INSERT INTO routines (id, business_id, employee_id, project_id, title, instruction, trigger,
         notify, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) ON CONFLICT (id) DO NOTHING`,
      [
        id,
        businessId,
        proposal.employeeId,
        proposal.projectId,
        proposal.title,
        proposal.instruction,
        JSON.stringify(proposal.trigger),
        proposal.notify,
        createdBy,
      ],
    );
    const created = await sql.row<Row>(
      `SELECT ${columns} FROM routines WHERE business_id = $1 AND id = $2`,
      [businessId, id],
    );
    if (!created) throw new Error("A routine with this id belongs to another business");
    return shown(created);
  });

/**
 * A new proposed revision of a routine, at the revision the employee read. It stops running
 * until the owner decides on the new revision. Undefined when the revision was stale.
 */
export const reviseRoutine = (
  db: Database,
  businessId: string,
  id: string,
  expectedRevision: number,
  proposal: Proposal,
) =>
  database(db, async (sql) => {
    const row = await sql.row<Row>(
      `UPDATE routines SET employee_id = $4, project_id = $5, title = $6, instruction = $7,
         trigger = $8, notify = $9, state = 'proposed', next_run_at = NULL,
         revision = revision + 1, updated_at = now()
       WHERE business_id = $1 AND id = $2 AND revision = $3
       RETURNING ${columns}`,
      [
        businessId,
        id,
        expectedRevision,
        proposal.employeeId,
        proposal.projectId,
        proposal.title,
        proposal.instruction,
        JSON.stringify(proposal.trigger),
        proposal.notify,
      ],
    );
    return row && shown(row);
  });

/**
 * Activates exactly this revision, with its first scheduled run (null for an event routine).
 * Undefined when the routine has moved on to another revision. Activating it again changes
 * nothing.
 */
export const activateRoutine = (
  db: Database,
  businessId: string,
  id: string,
  revision: number,
  nextRunAt: string | null,
) =>
  database(db, async (sql) => {
    const row = await sql.row<Row>(
      `UPDATE routines SET
         next_run_at = CASE WHEN state = 'active' THEN next_run_at ELSE $4::timestamptz END,
         state = 'active', updated_at = now()
       WHERE business_id = $1 AND id = $2 AND revision = $3
       RETURNING ${columns}`,
      [businessId, id, revision, nextRunAt],
    );
    return row && shown(row);
  });

/** Stops an active routine running; pausing a paused one changes nothing. Undefined otherwise. */
export const pauseRoutine = (db: Database, businessId: string, id: string) =>
  database(db, async (sql) => {
    const row = await sql.row<Row>(
      `UPDATE routines SET state = 'paused', next_run_at = NULL,
         updated_at = CASE WHEN state = 'paused' THEN updated_at ELSE now() END
       WHERE business_id = $1 AND id = $2 AND state IN ('active', 'paused')
       RETURNING ${columns}`,
      [businessId, id],
    );
    return row && shown(row);
  });

/**
 * The owner resumes a paused routine at the revision they read, with its next run. A paused
 * routine was active at its revision, so resuming decides nothing new. Undefined otherwise.
 */
export const resumeRoutine = (
  db: Database,
  businessId: string,
  id: string,
  revision: number,
  nextRunAt: string | null,
) =>
  database(db, async (sql) => {
    const row = await sql.row<Row>(
      `UPDATE routines SET state = 'active', next_run_at = $4::timestamptz, updated_at = now()
       WHERE business_id = $1 AND id = $2 AND revision = $3 AND state = 'paused'
       RETURNING ${columns}`,
      [businessId, id, revision, nextRunAt],
    );
    return row && shown(row);
  });

/** A retired employee's routines stop; they are not handed to anyone without a decision. */
export const pauseRoutinesOf = (db: Database, businessId: string, employeeId: string) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE routines SET state = 'paused', next_run_at = NULL, updated_at = now()
       WHERE business_id = $1 AND employee_id = $2 AND state = 'active'`,
      [businessId, employeeId],
    ),
  );

/** Active routines whose next run has come, oldest first, skipping employees who take no work. */
export const dueRoutines = (db: Database, skipEmployees: readonly string[], limit = 20) =>
  database(db, async (sql) =>
    (
      await sql.rows<Row & { business_id: string }>(
        `SELECT business_id, ${columns} FROM routines
         WHERE state = 'active' AND next_run_at <= now() AND employee_id <> ALL($2::text[])
         ORDER BY next_run_at LIMIT $1`,
        [limit, skipEmployees],
      )
    ).map((row) => ({ ...shown(row), business_id: row.business_id })),
  );

/**
 * Records that the run for `slot` was submitted and moves to the next slot. Only the tick that
 * still sees `slot` moves it, so a slot is advanced once.
 */
export const advanceRoutine = (db: Database, id: string, slot: string, next: string | null) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE routines SET next_run_at = $3::timestamptz, last_run_at = now()
       WHERE id = $1 AND state = 'active' AND next_run_at = $2::timestamptz`,
      [id, slot, next],
    ),
  );

/** Records that an event started a run. */
export const ranOnEvent = (db: Database, id: string) =>
  database(db, (sql) => sql.run("UPDATE routines SET last_run_at = now() WHERE id = $1", [id]));

/**
 * Active event routines of a business for this source and type whose every filter equals the
 * event's field, skipping employees who take no work.
 */
export const eventRoutines = (
  db: Database,
  businessId: string,
  event: { source: string; type: string; fields: Record<string, unknown> },
  skipEmployees: readonly string[],
) =>
  database(db, async (sql) =>
    (
      await sql.rows<Row>(
        `SELECT ${columns} FROM routines
         WHERE business_id = $1 AND state = 'active' AND trigger ->> 'kind' = 'event'
           AND trigger ->> 'source' = $2 AND trigger ->> 'type' = $3
           AND $4::jsonb @> (trigger -> 'filters') AND employee_id <> ALL($5::text[])`,
        [businessId, event.source, event.type, JSON.stringify(event.fields), skipEmployees],
      )
    ).map(shown),
  );

/**
 * What a run said, shortened; or, for a run that found nothing and posted nothing, "nothing to
 * report" and the moment, which the owner's briefing counts.
 */
export const recordResult = (
  db: Database,
  businessId: string,
  id: string,
  result: { silent: true } | { silent: false; excerpt: string },
) =>
  database(db, (sql) =>
    result.silent
      ? sql.run(
          // The last 50 quiet runs are kept: enough for any briefing.
          `UPDATE routines SET last_result = $3,
             silent_runs = (array_append(silent_runs, now()))[greatest(cardinality(silent_runs) - 48, 1):]
           WHERE business_id = $1 AND id = $2`,
          [businessId, id, nothingToReport],
        )
      : sql.run("UPDATE routines SET last_result = $3 WHERE business_id = $1 AND id = $2", [
          businessId,
          id,
          result.excerpt.slice(0, 500),
        ]),
  );

/** How many times each routine ran quietly (found nothing, posted nothing) since `since`. */
export const quietRuns = (db: Database, businessId: string, since: string) =>
  database(db, (sql) =>
    sql.rows<{ id: string; title: string; runs: number }>(
      `SELECT id, title, runs FROM (
         SELECT id, title,
           (SELECT count(*) FROM unnest(silent_runs) AS ran WHERE ran > $2::timestamptz)::int AS runs
         FROM routines WHERE business_id = $1
       ) counted WHERE runs > 0 ORDER BY title`,
      [businessId, since],
    ),
  );
