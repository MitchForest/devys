import { Effect, Schema } from "effect";
import { Timestamp } from "../protocol/time.ts";

export class MemoryError extends Schema.TaggedError<MemoryError>()("MemoryError", {
  code: Schema.Literals(["invalid", "conflict", "unavailable"]),
  message: Schema.String,
}) {}
export const Evidence = Schema.Struct({
  id: Schema.String,
  kind: Schema.Literals(["owner", "external"]),
  observed_at: Timestamp,
});
export type Evidence = typeof Evidence.Type;
/** What the business remembers: one claim, its revision and the evidence behind it. */
export const Claim = Schema.Struct({
  /** Search may return a marked excerpt; inspect/export return complete claims. */
  truncated: Schema.optionalKey(Schema.Boolean),
  key: Schema.String,
  content: Schema.String,
  source_kind: Schema.Literals(["user", "inference"]),
  source_operation_id: Schema.String,
  revision: Schema.Int,
  updated_at: Timestamp,
  subject: Schema.String,
  scope: Schema.String,
  valid_from: Schema.NullOr(Timestamp),
  valid_until: Schema.NullOr(Timestamp),
  evidence: Schema.Array(Evidence),
  relations: Schema.Array(Schema.Struct({ predicate: Schema.String, target: Schema.String })),
});
export type Claim = typeof Claim.Type;
/** `GET …/memory`: a page of claims, oldest key first. */
export const ClaimPage = Schema.Struct({
  items: Schema.Array(Claim),
  next: Schema.NullOr(Schema.String),
});
export interface Change {
  key: string;
  content: string;
  subject?: string;
  scope?: string;
  validFrom?: string | null;
  validUntil?: string | null;
  evidenceIds?: string[];
  source?: "user" | "inference";
  relations?: Claim["relations"];
  expectedRevision?: number;
}
export interface Observation {
  id: string;
  kind: "owner" | "external";
  observedAt: string;
  content: string;
}
export interface Page<T> {
  items: T[];
  next: string | null;
}
export interface MemoryExportPage extends Page<PortableRecord> {
  revision: number;
}
export type PortableRecord =
  | { version: 1; kind: "claim"; claim: Claim }
  | { version: 1; kind: "excluded-before"; before: string }
  | { version: 1; kind: "evidence-link"; key: string; evidence: Evidence }
  | { version: 1; kind: "excluded-key"; key: string }
  | { version: 1; kind: "excluded-source"; id: string };
export interface Memory {
  observe(
    batch: Observation[],
    cursor?: number,
  ): Effect.Effect<{ status: "accepted" }, MemoryError>;
  remember(
    change: Change,
    operationId: string,
  ): Effect.Effect<{ status: "saved"; claim: Claim }, MemoryError>;
  context(request: {
    query?: string;
    maxChars?: number;
  }): Effect.Effect<{ text: string; revision: number }, MemoryError>;
  search(request: {
    query: string;
    after?: string;
    maxChars?: number;
  }): Effect.Effect<Page<Claim>, MemoryError>;
  inspect(after?: string): Effect.Effect<Page<Claim>, MemoryError>;
  forget(keys: string[], operationId: string): Effect.Effect<{ status: "forgotten" }, MemoryError>;
  maintain(budget: {
    maxSources: number;
  }): Effect.Effect<{ processed: number; more: boolean }, MemoryError>;
  progress(): Effect.Effect<{ cursor: number }, MemoryError>;
  export(after?: string): Effect.Effect<MemoryExportPage, MemoryError>;
  import(
    records: PortableRecord[],
    operationId: string,
  ): Effect.Effect<{ status: "imported" }, MemoryError>;
}
export interface ConsolidationChange extends Change {
  /** Existing duplicate keys to merge into this claim, preserving their evidence. */
  supersedes?: string[];
}
export type CompleteMemory = (input: {
  observations: Observation[];
  existing: Claim[];
}) => Promise<ConsolidationChange[]>;
export type MemoryFactory = (ownerId: string) => Memory;
