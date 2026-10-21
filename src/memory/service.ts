import { Effect } from "effect";
import type { Database } from "../data/database.ts";
import { MemoryError } from "./contract.ts";
import type { CompleteMemory, Memory } from "./contract.ts";
import { claims as claimsIn, excludeBefore } from "./claims.ts";
import { consolidate, pendingObservations } from "./maintenance.ts";
import { fingerprint } from "./operation.ts";
import { exportPage, importRecords } from "./portability.ts";
import { contextText, currentClaims, searchClaims } from "./search.ts";
import { claim, store, type Row } from "./store.ts";
import { bounded, fail, validateChange, validateObservations } from "./validation.ts";

/** Any failure other than a memory rule's is reported as memory being unavailable. */
const attempt = <A>(operation: () => Promise<A>) =>
  Effect.tryPromise({
    try: operation,
    catch: (error) =>
      error instanceof MemoryError
        ? error
        : new MemoryError({ code: "unavailable", message: "Memory operation unavailable" }),
  });

/** One business's memory in Postgres; `assertActive` is checked before every write. */
export function createMemory(
  db: Database,
  scope: string,
  complete?: CompleteMemory,
  assertActive: () => Promise<void> = async () => {},
): Memory {
  const storage = store(db, scope);
  const { statement } = storage;
  const claims = claimsIn(storage, assertActive);

  const search: Memory["search"] = (request) => attempt(() => searchClaims(storage, request));

  return {
    observe: (batch, cursor) =>
      attempt(async () => {
        validateObservations(batch, cursor);
        const writes = batch.map((observation) =>
          statement(
            `INSERT INTO memory_sources(scope_id,id,kind,observed_at,content,processed)
               VALUES ($1,$2,$3,$4,CASE WHEN $4::timestamptz<=(SELECT excluded_before FROM memory_state WHERE scope_id=$1) THEN NULL ELSE $5 END,
               coalesce($4::timestamptz<=(SELECT excluded_before FROM memory_state WHERE scope_id=$1),false)) ON CONFLICT DO NOTHING`,
            observation.id,
            observation.kind,
            new Date(observation.observedAt).toISOString(),
            observation.content,
          ),
        );
        if (cursor !== undefined)
          writes.push(
            statement(
              "INSERT INTO memory_state(scope_id,cursor) VALUES ($1,$2) ON CONFLICT(scope_id) DO UPDATE SET cursor=GREATEST(memory_state.cursor,excluded.cursor)",
              cursor,
            ),
          );
        if (writes.length) {
          await assertActive();
          await storage.batch(writes);
        }
        return { status: "accepted" as const };
      }),

    remember: (change, operationId) =>
      attempt(async () => {
        validateChange(change);
        const { evidenceIds: _evidence, expectedRevision: _revision, ...semantic } = change;
        const signature = await fingerprint({ type: "remember", change: semantic });
        if (await claims.seen(operationId, signature)) {
          const existing = await claims.get(change.key);
          if (!existing) return fail("conflict", "Previously saved memory has been forgotten");
          return { status: "saved" as const, claim: existing };
        }
        const { revision } = await storage.state();
        const prior = await claims.get(change.key);
        const value = await claims.prepare(change, operationId);
        const committed = await claims.commit(revision, [
          ...(prior ? [claims.links(prior.key, prior.evidence)] : []),
          ...claims.save(value),
          statement(`DELETE FROM memory_exclusions WHERE scope_id=$1 AND key=$2`, change.key),
          claims.receipt(operationId, signature),
        ]);
        if (!committed) fail("conflict", "Memory changed; retry after reading");
        return { status: "saved" as const, claim: value };
      }),

    inspect: (after) =>
      attempt(async () => {
        const rows = await storage.rows<Row>(
          "SELECT * FROM memories WHERE scope_id=$1 AND key>$2 ORDER BY key LIMIT 30",
          after ?? "",
        );
        return { items: rows.map(claim), next: rows.length === 30 ? rows.at(-1)!.key : null };
      }),

    search,

    context: (request) =>
      Effect.gen(function* () {
        const maxChars = bounded(request.maxChars, 12000);
        const { revision } = yield* attempt(() => storage.state());
        const current = yield* attempt(() => currentClaims(storage));
        const relevant = request.query
          ? yield* search({ query: request.query, maxChars: Math.floor(maxChars / 2) })
          : { items: [] };
        const text = contextText(relevant.items, current, maxChars);
        yield* attempt(async () => {
          if ((await storage.state()).revision !== revision)
            fail("conflict", "Memory changed while assembling context; retry");
        });
        return { text, revision };
      }),

    forget: (keys, operationId) =>
      attempt(async () => {
        if (
          !keys.length ||
          keys.length > 30 ||
          keys.some((key) => typeof key !== "string" || key.length > 200)
        )
          fail("invalid", "Invalid forget selection");
        const signature = await fingerprint({ type: "forget", keys: [...keys].sort() });
        if (await claims.seen(operationId, signature)) return { status: "forgotten" as const };
        const { revision } = await storage.state();
        const current = (await Promise.all(keys.map(claims.get))).filter(
          (item) => item !== undefined,
        );
        const selected = JSON.stringify(keys);
        // A claim without evidence could have come from anything said before now.
        const unknownEvidence = current.some((item) => !item.evidence.length);
        const before = new Date().toISOString();
        // SQL performs the transitive source exclusion without loading the owner's corpus.
        const committed = await claims.commit(revision, [
          ...current.map((item) => claims.links(item.key, item.evidence)),
          statement(
            `INSERT INTO memory_sources(scope_id,id,kind,observed_at,excluded,processed)
              SELECT $1,source_id,'external','1970-01-01T00:00:00.000Z',true,true FROM memory_links
              WHERE scope_id=$1 AND key IN (SELECT jsonb_array_elements_text($2::jsonb))
              ON CONFLICT(scope_id,id) DO UPDATE SET excluded=true,content=NULL`,
            selected,
          ),
          statement(
            `INSERT INTO memory_exclusions(scope_id,key) SELECT $1,k FROM jsonb_array_elements_text($2::jsonb) k ON CONFLICT DO NOTHING`,
            selected,
          ),
          statement(`INSERT INTO memory_exclusions(scope_id,key) SELECT $1,l.key FROM memory_links l
              JOIN memory_sources s ON s.scope_id=l.scope_id AND s.id=l.source_id
              WHERE l.scope_id=$1 AND s.excluded ON CONFLICT DO NOTHING`),
          statement(
            `DELETE FROM memories WHERE scope_id=$1 AND key IN (SELECT key FROM memory_exclusions WHERE scope_id=$1)`,
          ),
          statement(
            `DELETE FROM memory_links WHERE scope_id=$1 AND key IN (SELECT key FROM memory_exclusions WHERE scope_id=$1)`,
          ),
          ...(unknownEvidence ? excludeBefore(storage, before) : []),
          claims.receipt(operationId, signature),
        ]);
        if (!committed) fail("conflict", "Memory changed; retry forgetting");
        return { status: "forgotten" as const };
      }),

    maintain: (budget) =>
      Effect.gen(function* () {
        const { revision } = yield* attempt(() => storage.state());
        const observations = yield* attempt(() => pendingObservations(storage, budget.maxSources));
        if (!observations.length) return { processed: 0, more: false };
        if (!complete)
          return yield* Effect.fail(
            new MemoryError({
              code: "unavailable",
              message: "Memory consolidation model is unavailable",
            }),
          );
        const { items: existing } = yield* search({
          query: observations.map((observation) => observation.content).join(" "),
          maxChars: 16000,
        });
        return yield* attempt(() =>
          consolidate(storage, claims, complete, { revision, observations, existing }),
        );
      }),

    progress: () => attempt(async () => ({ cursor: (await storage.state()).cursor })),
    export: (after) => attempt(() => exportPage(storage, claims, after)),
    import: (records, operationId) =>
      attempt(() => importRecords(storage, claims, records, operationId)),
  };
}
