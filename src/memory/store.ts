import { query, transaction, type Database } from "../data/database.ts";
import type { Claim } from "./contract.ts";
export interface Row {
  key: string;
  content: string;
  source_kind: "user" | "inference";
  source_operation_id: string;
  revision: number;
  updated_at: string;
  details: Partial<Claim>;
}
export function claim(row: Row): Claim {
  const details = row.details;
  return {
    key: row.key,
    content: row.content,
    source_kind: row.source_kind,
    source_operation_id: row.source_operation_id,
    revision: row.revision,
    updated_at: row.updated_at,
    subject: details.subject ?? "owner",
    scope: details.scope ?? "unspecified",
    validFrom: details.validFrom ?? null,
    validUntil: details.validUntil ?? null,
    evidence: details.evidence ?? [
      { id: row.source_operation_id, kind: "legacy", observedAt: row.updated_at },
    ],
    relations: details.relations ?? [],
  };
}

/** One SQL statement; `$1` is always the scope. */
export interface Statement {
  text: string;
  values: unknown[];
}

/** Postgres is private to this implementation. All writes advance one scope revision. */
export function store(db: Database, scope: string) {
  const statement = (text: string, ...values: unknown[]): Statement => ({
    text,
    values: [scope, ...values],
  });
  const run = (writes: Statement[]) =>
    transaction(db, async (sql) => {
      for (const write of writes) await sql.run(write.text, write.values);
    });
  return {
    statement,
    rows: <T>(text: string, ...values: unknown[]) =>
      query(db, (sql) => sql.rows<T>(text, [scope, ...values])),
    row: <T>(text: string, ...values: unknown[]) =>
      query(db, (sql) => sql.row<T>(text, [scope, ...values])),
    async state() {
      return query(db, async (sql) => {
        await sql.run("INSERT INTO memory_state (scope_id) VALUES ($1) ON CONFLICT DO NOTHING", [
          scope,
        ]);
        return (await sql.row<{ revision: number; cursor: number }>(
          "SELECT revision, cursor FROM memory_state WHERE scope_id = $1",
          [scope],
        ))!;
      });
    },
    /** Applies `writes` only if the revision is still `revision`; false means someone else wrote. */
    commit(revision: number, writes: Statement[]) {
      return transaction(db, async (sql) => {
        const advanced = await sql.run(
          "UPDATE memory_state SET revision = revision + 1 WHERE scope_id = $1 AND revision = $2",
          [scope, revision],
        );
        if (advanced !== 1) return false;
        for (const write of writes) await sql.run(write.text, write.values);
        return true;
      });
    },
    batch: run,
  };
}
