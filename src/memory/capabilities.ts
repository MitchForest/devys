import { ClaimSchema, ChangeSchema } from "./schema.ts";
import { Effect, Schema } from "effect";
import { capability, CapabilityError, Invocation, Text } from "../protocol/capability.ts";
import type { MemoryFactory } from "./contract.ts";
const Key = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(200));
const error = <A>(effect: Effect.Effect<A, import("./contract.ts").MemoryError>) =>
  effect.pipe(
    Effect.mapError(
      (e) =>
        new CapabilityError({
          code: e.code === "invalid" ? "invalid_input" : e.code,
          message: e.message,
        }),
    ),
  );
export function memoryCapabilities(factory: MemoryFactory) {
  return [
    capability({
      name: "recall",
      description:
        "Search what the business knows (facts about the business, its owner and the people they work with) with evidence and scope. Empty query lists current knowledge. Use next as after for another page.",
      effect: "read",
      replay: "read",
      core: true,
      input: Schema.Struct({ query: Text, after: Schema.optional(Key) }),
      output: Schema.Struct({
        items: Schema.Array(ClaimSchema),
        next: Schema.NullOr(Schema.String),
      }),
      execute: (input) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          return yield* error(factory(businessId).search(input));
        }),
    }),
    capability({
      name: "remember",
      description:
        "Immediately save or correct a useful fact about the business, its owner or the people they work with. Use source=user only for an explicit owner statement; trusted host evidence is attached. Preserve temporary scope and exceptions. Pass expectedRevision from recall or the current memory context before correcting.",
      effect: "change",
      replay: "idempotent",
      core: true,
      input: ChangeSchema,
      output: Schema.Struct({ status: Schema.Literal("saved"), claim: ClaimSchema }),
      execute: (input) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          return yield* error(
            factory(invocation.businessId).remember(
              { ...input, evidenceIds: invocation.evidenceIds ?? [] },
              invocation.operationId,
            ),
          );
        }),
    }),
    capability({
      name: "forget",
      description:
        "Forget the selected memory keys and dependent claims. Suppress their source observations from future learning. This does not erase the original conversation transcript.",
      effect: "change",
      replay: "idempotent",
      core: true,
      input: Schema.Struct({
        keys: Schema.Array(Key).check(Schema.isMinLength(1), Schema.isMaxLength(30)),
      }),
      output: Schema.Struct({ status: Schema.Literal("forgotten") }),
      execute: ({ keys }) =>
        Effect.gen(function* () {
          const { businessId, operationId } = yield* Invocation;
          return yield* error(factory(businessId).forget([...keys], operationId));
        }),
    }),
  ];
}
