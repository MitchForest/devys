import { Schema } from "effect";
import { Timestamp } from "../protocol/time.ts";
import { Claim, Evidence } from "./contract.ts";
const string = (max: number) => Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(max));
export const Key = string(200);
/** The contract's evidence, with the limits a stored or imported record keeps. */
const EvidenceSchema = Schema.Struct({ ...Evidence.fields, id: Key });
/** The contract's claim, with the limits a stored or imported record keeps. */
export const ClaimSchema = Schema.Struct({
  ...Claim.fields,
  key: Key,
  content: string(64000),
  subject: string(300),
  scope: string(300),
  source_operation_id: string(200),
  revision: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)),
  evidence: Schema.Array(EvidenceSchema).check(Schema.isMaxLength(20)),
  relations: Schema.Array(Schema.Struct({ predicate: Key, target: Key })).check(
    Schema.isMaxLength(10),
  ),
});
export const PortableSchema = Schema.Union([
  Schema.Struct({
    version: Schema.Literal(1),
    kind: Schema.Literal("excluded-before"),
    before: Timestamp,
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
  validFrom: Schema.optional(Schema.NullOr(Timestamp)),
  validUntil: Schema.optional(Schema.NullOr(Timestamp)),
  expectedRevision: Schema.optional(Schema.Int.check(Schema.isGreaterThanOrEqualTo(0))),
});
/** `POST …/memory/remember`: the same change in the API's field names. */
export const RememberRequest = Schema.Struct({
  key: ChangeSchema.fields.key,
  content: ChangeSchema.fields.content,
  source: ChangeSchema.fields.source,
  subject: ChangeSchema.fields.subject,
  scope: ChangeSchema.fields.scope,
  valid_from: ChangeSchema.fields.validFrom,
  valid_until: ChangeSchema.fields.validUntil,
  expected_revision: ChangeSchema.fields.expectedRevision,
});
