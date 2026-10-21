import { MemoryError } from "./contract.ts";
import type { Change, Observation } from "./contract.ts";

export const fail = (code: "invalid" | "conflict", message: string): never => {
  throw new MemoryError({ code, message });
};

/** A caller's character budget, kept between 2 KiB and `maximum`. */
export const bounded = (value: number | undefined, maximum: number) =>
  Math.max(2048, Math.min(maximum, Number.isFinite(value) ? Math.floor(value!) : maximum));

const isText = (value: unknown, maximum: number) =>
  typeof value === "string" && value.length > 0 && value.length <= maximum;

export function validateChange(change: Change) {
  if (!change || !isText(change.key, 200) || !isText(change.content, 4000))
    fail("invalid", "Memory key/content exceeds limits");
  if (change.source !== undefined && !["user", "inference"].includes(change.source))
    fail("invalid", "Invalid source kind");
  for (const value of [change.subject, change.scope])
    if (value !== undefined && !isText(value, 300)) fail("invalid", "Invalid memory scope");
  for (const value of [change.validFrom, change.validUntil])
    if (value != null && (typeof value !== "string" || !Number.isFinite(Date.parse(value))))
      fail("invalid", "Invalid memory date");
  if (
    change.validFrom &&
    change.validUntil &&
    Date.parse(change.validFrom) >= Date.parse(change.validUntil)
  )
    fail("invalid", "Invalid memory interval");
  if (
    change.evidenceIds &&
    (!Array.isArray(change.evidenceIds) ||
      change.evidenceIds.length > 20 ||
      change.evidenceIds.some((id) => typeof id !== "string" || id.length > 200))
  )
    fail("invalid", "Invalid evidence");
  if (
    change.relations &&
    (!Array.isArray(change.relations) ||
      change.relations.length > 10 ||
      change.relations.some(
        (relation) =>
          !relation || !isText(relation.predicate, 200) || !isText(relation.target, 200),
      ))
  )
    fail("invalid", "Invalid relationships");
  if (
    change.expectedRevision !== undefined &&
    (!Number.isSafeInteger(change.expectedRevision) || change.expectedRevision < 0)
  )
    fail("invalid", "Invalid revision");
}

export function validateObservations(batch: Observation[], cursor: number | undefined) {
  if (batch.length > 50 || (cursor !== undefined && (!Number.isSafeInteger(cursor) || cursor < 0)))
    fail("invalid", "Observation batch exceeds limit");
  for (const observation of batch)
    if (
      !observation.id ||
      observation.id.length > 200 ||
      !["owner", "external"].includes(observation.kind) ||
      typeof observation.content !== "string" ||
      observation.content.length > 64000 ||
      !Number.isFinite(Date.parse(observation.observedAt))
    )
      fail("invalid", "Invalid observation");
}
