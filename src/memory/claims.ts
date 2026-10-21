import type { Change, Claim, Evidence } from "./contract.ts";
import { claim, type Row, type Statement, type Storage } from "./store.ts";
import { fail, validateChange } from "./validation.ts";

/** Claims and their evidence in one business's store; every write goes through `commit`. */
export function claims(storage: Storage, assertActive: () => Promise<void>) {
  const { statement } = storage;

  const get = async (key: string) => {
    const row = await storage.row<Row>("SELECT * FROM memories WHERE scope_id=$1 AND key=$2", key);
    return row ? claim(row) : undefined;
  };

  const isExcluded = async (key: string) =>
    Boolean(
      await storage.row("SELECT key FROM memory_exclusions WHERE scope_id=$1 AND key=$2", key),
    );

  /** Whether the operation already ran; the same id for a different mutation is a conflict. */
  const seen = async (operationId: string, signature: string) => {
    if (!operationId || operationId.length > 200) fail("invalid", "Invalid operation ID");
    const prior = await storage.row<{ fingerprint: string }>(
      "SELECT fingerprint FROM memory_operations WHERE scope_id=$1 AND id=$2",
      operationId,
    );
    if (prior && prior.fingerprint !== signature)
      fail("conflict", "Operation ID already used for a different mutation");
    return Boolean(prior);
  };

  const receipt = (operationId: string, signature: string) =>
    statement(
      `INSERT INTO memory_operations(scope_id,id,fingerprint) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING`,
      operationId,
      signature,
    );

  /** The claim a change makes, citing only evidence that exists and is not excluded. */
  async function prepare(change: Change, operationId: string): Promise<Claim> {
    validateChange(change);
    const evidence: Evidence[] = [];
    for (const id of change.evidenceIds ?? []) {
      const source = await storage.row<{
        id: string;
        kind: "owner" | "external";
        observed_at: string;
      }>(
        "SELECT id,kind,observed_at FROM memory_sources WHERE scope_id=$1 AND id=$2 AND NOT excluded",
        id,
      );
      if (!source) return fail("invalid", "Evidence is missing or excluded");
      evidence.push({ id: source.id, kind: source.kind, observedAt: source.observed_at });
    }
    if (await isExcluded(change.key)) {
      const before = (
        await storage.row<{ excluded_before: string | null }>(
          "SELECT excluded_before FROM memory_state WHERE scope_id=$1",
        )
      )?.excluded_before;
      const restoredByOwner = evidence.some(
        (item) =>
          item.kind === "owner" &&
          Date.parse(item.observedAt) > Date.parse(before ?? "1970-01-01T00:00:00.000Z"),
      );
      if (!restoredByOwner)
        fail("conflict", "Restoring forgotten knowledge requires new owner evidence");
    }
    const prior = await get(change.key);
    if (prior && change.expectedRevision === undefined)
      fail("conflict", "Read the existing claim and supply expectedRevision before correcting it");
    if (change.expectedRevision !== undefined && change.expectedRevision !== (prior?.revision ?? 0))
      fail("conflict", "Memory changed; read it before correcting");
    return {
      key: change.key,
      content: change.content,
      subject: change.subject ?? "owner",
      scope: change.scope ?? "unspecified",
      validFrom: change.validFrom ? new Date(change.validFrom).toISOString() : null,
      validUntil: change.validUntil ? new Date(change.validUntil).toISOString() : null,
      relations: change.relations ?? [],
      evidence,
      source_kind:
        change.source === "user" &&
        evidence.length > 0 &&
        evidence.every((item) => item.kind === "owner")
          ? "user"
          : "inference",
      source_operation_id: operationId,
      revision: (prior?.revision ?? 0) + 1,
      updated_at: new Date().toISOString(),
    };
  }

  /** Keeps a claim's evidence links, so forgetting a source can find what it supported. */
  const links = (key: string, evidence: Evidence[]) =>
    statement(
      `INSERT INTO memory_links(scope_id,key,source_id,evidence)
      SELECT $1,$2,e->>'id',e FROM jsonb_array_elements($3::jsonb) e
      ON CONFLICT DO NOTHING`,
      key,
      JSON.stringify(evidence),
    );

  const save = (value: Claim): Statement[] => [
    statement(
      `INSERT INTO memories(scope_id,key,content,source_kind,source_operation_id,revision,updated_at,details)
 VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
 ON CONFLICT(scope_id,key) DO UPDATE SET content=excluded.content,source_kind=excluded.source_kind,source_operation_id=excluded.source_operation_id,revision=excluded.revision,updated_at=excluded.updated_at,details=excluded.details`,
      value.key,
      value.content,
      value.source_kind,
      value.source_operation_id,
      value.revision,
      value.updated_at,
      JSON.stringify({
        subject: value.subject,
        scope: value.scope,
        validFrom: value.validFrom,
        validUntil: value.validUntil,
        evidence: value.evidence,
        relations: value.relations,
      }),
    ),
    links(value.key, value.evidence),
  ];

  /** Applies `writes` only while the employee is active and nobody else wrote since `revision`. */
  const commit = async (revision: number, writes: Statement[]) => {
    await assertActive();
    return storage.commit(revision, writes);
  };

  return { get, isExcluded, seen, receipt, prepare, links, save, commit };
}

export type Claims = ReturnType<typeof claims>;

/** Sources observed at or before `before` are no longer evidence for anything. */
export const excludeBefore = (storage: Storage, before: string) => [
  storage.statement(
    `UPDATE memory_state SET excluded_before=GREATEST(excluded_before,$2::timestamptz) WHERE scope_id=$1`,
    before,
  ),
  storage.statement(
    `UPDATE memory_sources SET processed=true,content=NULL WHERE scope_id=$1 AND NOT processed AND observed_at<=$2::timestamptz`,
    before,
  ),
];
