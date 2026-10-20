import { Schema } from "effect";
const string = (max: number) => Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(max));
export const Key = string(200);
const DateString = Schema.String.check(
  Schema.makeFilter(
    (value) =>
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) &&
      Number.isFinite(Date.parse(value)),
  ),
);
export const EvidenceSchema = Schema.Struct({
  id: Key,
  kind: Schema.Literals(["owner", "external"]),
  observedAt: DateString,
});
export const ClaimSchema = Schema.Struct({
  key: Key,
  content: string(64000),
  subject: string(300),
  scope: string(300),
  source_kind: Schema.Literals(["user", "inference"]),
  source_operation_id: string(200),
  revision: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)),
  updated_at: DateString,
  validFrom: Schema.NullOr(DateString),
  validUntil: Schema.NullOr(DateString),
  evidence: Schema.Array(EvidenceSchema).check(Schema.isMaxLength(20)),
  relations: Schema.Array(Schema.Struct({ predicate: Key, target: Key })).check(
    Schema.isMaxLength(10),
  ),
  truncated: Schema.optional(Schema.Boolean),
});
export const PortableSchema = Schema.Union([
  Schema.Struct({
    version: Schema.Literal(1),
    kind: Schema.Literal("excluded-before"),
    before: DateString,
  }),
  Schema.Struct({ version: Schema.Literal(1), kind: Schema.Literal("claim"), claim: ClaimSchema }),
  Schema.Struct({
    version: Schema.Literal(1),
    kind: Schema.Literal("evidence-link"),
    key: Key,
    evidence: EvidenceSchema,
  }),
  Schema.Struct({ version: Schema.Literal(1), kind: Schema.Literal("excluded-key"), key: Key }),
  Schema.Struct({ version: Schema.Literal(1), kind: Schema.Literal("excluded-source"), id: Key }),
]);
export const ImportSchema = Schema.Array(PortableSchema).check(Schema.isMaxLength(30));
export const ChangeSchema = Schema.Struct({
  key: Key,
  content: string(4000),
  source: Schema.Literals(["user", "inference"]),
  subject: Schema.optional(Key),
  scope: Schema.optional(string(300)),
  validFrom: Schema.optional(Schema.NullOr(DateString)),
  validUntil: Schema.optional(Schema.NullOr(DateString)),
  expectedRevision: Schema.optional(Schema.Int.check(Schema.isGreaterThanOrEqualTo(0))),
});
