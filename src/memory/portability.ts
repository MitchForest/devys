import { Schema } from "effect";
import type { Evidence, MemoryExportPage, PortableRecord } from "./contract.ts";
import { excludeBefore, type Claims } from "./claims.ts";
import { fingerprint } from "./operation.ts";
import { ImportSchema } from "./schema.ts";
import type { Storage } from "./store.ts";
import { fail } from "./validation.ts";

/** One page of portable records, ordered by stable type-prefixed cursors. */
export async function exportPage(
  storage: Storage,
  claims: Claims,
  after: string | undefined,
): Promise<MemoryExportPage> {
  const { revision } = await storage.state();
  // Stable type-prefixed keys allow portable streaming without exposing SQL cursors.
  const records = await storage.rows<{ cursor: string; kind: string; value: string }>(
    `SELECT * FROM (
          SELECT 'c:'||key AS cursor,'claim' AS kind,key AS value FROM memories WHERE scope_id=$1
          UNION ALL SELECT 'f:','excluded-before',to_char(excluded_before AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') FROM memory_state WHERE scope_id=$1 AND excluded_before IS NOT NULL
          UNION ALL SELECT 'k:'||key,'excluded-key',key FROM memory_exclusions WHERE scope_id=$1
          UNION ALL SELECT 'l:'||jsonb_build_array(key,source_id)::text,'evidence-link',jsonb_build_object('key',key,'evidence',evidence)::text FROM memory_links WHERE scope_id=$1
          UNION ALL SELECT 's:'||id,'excluded-source',id FROM memory_sources WHERE scope_id=$1 AND excluded
        ) records WHERE cursor>$2 ORDER BY cursor COLLATE "C" LIMIT 30`,
    after ?? "",
  );
  const items: PortableRecord[] = [];
  for (const record of records) {
    if (record.kind === "claim") {
      const current = await claims.get(record.value);
      if (current) items.push({ version: 1, kind: "claim", claim: current });
    } else if (record.kind === "excluded-before")
      items.push({ version: 1, kind: "excluded-before", before: record.value });
    else if (record.kind === "evidence-link")
      items.push({ version: 1, kind: "evidence-link", ...JSON.parse(record.value) });
    else if (record.kind === "excluded-key")
      items.push({ version: 1, kind: "excluded-key", key: record.value });
    else items.push({ version: 1, kind: "excluded-source", id: record.value });
  }
  if ((await storage.state()).revision !== revision)
    fail("conflict", "Memory changed during export; restart the export");
  return { items, next: records.length === 30 ? records.at(-1)!.cursor : null, revision };
}

/** Imports exported records into an empty store; exclusions apply to everything imported. */
export async function importRecords(
  storage: Storage,
  claims: Claims,
  records: PortableRecord[],
  operationId: string,
) {
  try {
    Schema.decodeUnknownSync(ImportSchema)(records);
  } catch {
    return fail("invalid", "Invalid portable memory records or format version");
  }
  const signature = await fingerprint({ type: "import", records });
  if (await claims.seen(operationId, signature)) return { status: "imported" as const };
  const { revision } = await storage.state();
  for (const record of records) {
    if (record.kind !== "claim") continue;
    if (record.claim.truncated) fail("invalid", "Cannot import a search excerpt");
    const prior = await claims.get(record.claim.key);
    if (prior && JSON.stringify(prior) !== JSON.stringify(record.claim))
      fail("conflict", "Import would overwrite existing memory; migrate into an empty store");
  }
  const knownSource = (evidence: Evidence) =>
    storage.statement(
      `INSERT INTO memory_sources(scope_id,id,kind,observed_at,processed) VALUES ($1,$2,$3,$4,true) ON CONFLICT DO NOTHING`,
      evidence.id,
      evidence.kind === "owner" ? "owner" : "external",
      evidence.observedAt,
    );
  const writes = records.flatMap((record) => {
    switch (record.kind) {
      case "excluded-before":
        return excludeBefore(storage, record.before);
      case "excluded-key":
        return [
          storage.statement(
            `INSERT INTO memory_exclusions(scope_id,key) VALUES ($1,$2) ON CONFLICT DO NOTHING`,
            record.key,
          ),
          storage.statement(`DELETE FROM memories WHERE scope_id=$1 AND key=$2`, record.key),
        ];
      case "excluded-source":
        return [
          storage.statement(
            `INSERT INTO memory_sources(scope_id,id,kind,observed_at,excluded,processed) VALUES ($1,$2,'external','1970-01-01T00:00:00.000Z',true,true) ON CONFLICT(scope_id,id) DO UPDATE SET excluded=true,content=NULL`,
            record.id,
          ),
        ];
      case "evidence-link":
        return [claims.links(record.key, [record.evidence]), knownSource(record.evidence)];
      case "claim":
        return [...claims.save(record.claim), ...record.claim.evidence.map(knownSource)];
    }
  });
  const committed = await claims.commit(revision, [
    ...writes,
    storage.statement(
      `DELETE FROM memories WHERE scope_id=$1 AND (key IN (SELECT key FROM memory_exclusions WHERE scope_id=$1) OR EXISTS (SELECT 1 FROM memory_links l JOIN memory_sources s ON s.scope_id=l.scope_id AND s.id=l.source_id WHERE l.scope_id=$1 AND l.key=memories.key AND s.excluded))`,
    ),
    storage.statement(
      `DELETE FROM memory_links WHERE scope_id=$1 AND key NOT IN (SELECT key FROM memories WHERE scope_id=$1)`,
    ),
    claims.receipt(operationId, signature),
  ]);
  if (!committed) fail("conflict", "Memory changed during import");
  return { status: "imported" as const };
}
