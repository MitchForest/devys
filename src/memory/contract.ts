import { Effect, Schema } from "effect";

export class MemoryError extends Schema.TaggedError<MemoryError>()("MemoryError", {
  code: Schema.Literals(["invalid", "conflict", "unavailable"]),
  message: Schema.String,
}) {}
export interface Evidence {
  id: string;
  kind: "owner" | "external";
  observedAt: string;
}
export interface Claim {
  /** Search may return a marked excerpt; inspect/export return complete claims. */
  truncated?: boolean;
  key: string;
  content: string;
  source_kind: "user" | "inference";
  source_operation_id: string;
  revision: number;
  updated_at: string;
  subject: string;
  scope: string;
  validFrom: string | null;
  validUntil: string | null;
  evidence: Evidence[];
  relations: { predicate: string; target: string }[];
}
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
