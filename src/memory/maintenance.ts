import type { Claim, CompleteMemory, ConsolidationChange, Observation } from "./contract.ts";
import { fingerprint } from "./operation.ts";
import type { Claims } from "./claims.ts";
import type { Statement, Storage } from "./store.ts";
import { fail, validateChange } from "./validation.ts";

/** Unprocessed observations, oldest first, at most four and 64,000 characters together. */
export async function pendingObservations(
  storage: Storage,
  maxSources: number,
): Promise<Observation[]> {
  const candidates = await storage.rows<{
    id: string;
    kind: "owner" | "external";
    observed_at: string;
    content: string;
  }>(
    "SELECT id,kind,observed_at,content FROM memory_sources WHERE scope_id=$1 AND NOT processed AND NOT excluded ORDER BY observed_at,id LIMIT $2",
    Math.max(1, Math.min(4, Math.floor(maxSources) || 1)),
  );
  const pending: Observation[] = [];
  let inputChars = 0;
  for (const candidate of candidates) {
    if (inputChars + candidate.content.length > 64000) break;
    pending.push({
      id: candidate.id,
      kind: candidate.kind,
      observedAt: candidate.observed_at,
      content: candidate.content,
    });
    inputChars += candidate.content.length;
  }
  return pending;
}

/**
 * One consolidation pass: the model proposes changes from new observations and the existing
 * claims they touch; each is checked again before the pass commits and marks them processed.
 */
export async function consolidate(
  storage: Storage,
  claims: Claims,
  complete: CompleteMemory,
  pass: { revision: number; observations: Observation[]; existing: Claim[] },
) {
  const { revision, observations, existing } = pass;
  const changes = await complete({ observations, existing });
  if (!Array.isArray(changes) || changes.length > 20)
    fail("invalid", "Consolidation exceeds change budget");
  const prepared: Claim[] = [];
  const merges: { key: string; previous: Claim[] }[] = [];
  const changedKeys = new Set<string>();
  const removedKeys = new Set<string>();
  const allowedEvidence = new Set([
    ...observations.map((observation) => observation.id),
    ...existing.flatMap((item) => item.evidence.map((evidence) => evidence.id)),
  ]);
  const operationId = `consolidate:${await fingerprint(observations[0]!.id)}`;
  for (const change of changes) {
    validateChange(change);
    if (changedKeys.has(change.key)) fail("invalid", "Duplicate consolidation key");
    changedKeys.add(change.key);
    checkCitations(change, observations, existing, allowedEvidence);
    if (await claims.isExcluded(change.key)) continue;
    const prior = await claims.get(change.key);
    const previous = (await Promise.all((change.supersedes ?? []).map(claims.get))).filter(
      (item) => item !== undefined,
    );
    const replaces = mayReplace(change, observations);
    if ((prior && !replaces(prior)) || previous.some((old) => !replaces(old))) continue;
    for (const old of previous) {
      if (removedKeys.has(old.key)) fail("invalid", "A duplicate can only be merged once per pass");
      removedKeys.add(old.key);
    }
    merges.push({ key: change.key, previous });
    prepared.push(
      await claims.prepare({ ...change, expectedRevision: prior?.revision ?? 0 }, operationId),
    );
  }
  if (prepared.some((item) => removedKeys.has(item.key)))
    fail("invalid", "Consolidation cannot both change and supersede a key");
  const committed = await claims.commit(revision, [
    ...prepared.flatMap(claims.save),
    ...merges.flatMap((merge) =>
      merge.previous.flatMap((old) => mergeInto(storage, claims, merge.key, old)),
    ),
    ...observations.map((observation) =>
      storage.statement(
        `UPDATE memory_sources SET processed=true,content=NULL WHERE scope_id=$1 AND id=$2`,
        observation.id,
      ),
    ),
  ]);
  if (!committed) fail("conflict", "Memory changed during consolidation");
  return {
    processed: observations.length,
    more: Boolean(
      await storage.row(
        "SELECT id FROM memory_sources WHERE scope_id=$1 AND NOT processed AND NOT excluded LIMIT 1",
      ),
    ),
  };
}

/** A change must cite a new observation, only supplied evidence, and merge only supplied claims. */
function checkCitations(
  change: ConsolidationChange,
  observations: Observation[],
  existing: Claim[],
  allowedEvidence: Set<string>,
) {
  if (
    !change.evidenceIds?.length ||
    !change.evidenceIds.some((id) => observations.some((observation) => observation.id === id)) ||
    change.evidenceIds.some((id) => !allowedEvidence.has(id))
  )
    fail("invalid", "Consolidation must cite supplied evidence including a new observation");
  if (
    change.supersedes &&
    (!Array.isArray(change.supersedes) ||
      change.supersedes.length > 8 ||
      change.supersedes.some(
        (key) =>
          typeof key !== "string" ||
          key === change.key ||
          !existing.some((item) => item.key === key),
      ))
  )
    fail("invalid", "Merges must name supplied existing duplicate claims");
}

/**
 * Whether a change may replace an existing claim: never with older evidence; a consolidated
 * claim always; an owner's or saved claim only by the owner's own newer statement.
 */
function mayReplace(change: ConsolidationChange, observations: Observation[]) {
  const cited = observations.filter((observation) => change.evidenceIds!.includes(observation.id));
  const latestEvidence = Math.max(
    ...cited.map((observation) => Date.parse(observation.observedAt)),
  );
  return (old: Claim) => {
    const oldEvidence = old.evidence.map((evidence) => Date.parse(evidence.observedAt));
    if (latestEvidence < Math.max(...oldEvidence)) return false;
    if (old.source_operation_id.startsWith("consolidate:")) return true;
    const priorTime = Math.max(Date.parse(old.updated_at), ...oldEvidence);
    return (
      change.source === "user" &&
      cited.every((observation) => observation.kind === "owner") &&
      latestEvidence > priorTime
    );
  };
}

/** Folds a duplicate claim into `key`, keeping its evidence links, then removes it. */
const mergeInto = (storage: Storage, claims: Claims, key: string, old: Claim): Statement[] => [
  claims.links(old.key, old.evidence),
  storage.statement(
    `INSERT INTO memory_links(scope_id,key,source_id,evidence) SELECT $1,$2,source_id,evidence FROM memory_links WHERE scope_id=$1 AND key=$3 ON CONFLICT DO NOTHING`,
    key,
    old.key,
  ),
  storage.statement(`DELETE FROM memories WHERE scope_id=$1 AND key=$2`, old.key),
  storage.statement(`DELETE FROM memory_links WHERE scope_id=$1 AND key=$2`, old.key),
];
