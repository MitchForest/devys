import { Context, Effect, Schema } from "effect";

export class CapabilityError extends Schema.TaggedError<CapabilityError>()("CapabilityError", {
  code: Schema.Literals([
    "invalid_input",
    "conflict",
    "forbidden",
    "cancelled",
    "limit",
    "unavailable",
    "uncertain",
    "approval_required",
  ]),
  message: Schema.String,
}) {}

/** What a capability does to the world. It suggests a default mode; grants decide. */
type EffectClass = "read" | "change" | "external";

/** Supplied by the trusted host. Never decoded from model arguments. */
export class Invocation extends Context.Service<
  Invocation,
  {
    /** The business whose authority and records this call uses. */
    readonly businessId: string;
    /** The employee acting. Its runtime and workspace are named by both ids. */
    readonly employeeId: string;
    readonly operationId: string;
    readonly evidenceIds?: string[];
    /** The work item this run serves, when the dispatcher handed it over. */
    readonly workItemId?: string;
    /** The conversation the running turn answers (`direct:`, `project:` or `work:` key). */
    readonly conversation?: string;
    /** Re-reads the employee's grant for this exact input; fails when it isn't allowed now. */
    readonly authorize: (
      capability: Capability,
      input: unknown,
    ) => Effect.Effect<void, CapabilityError>;
    readonly assertActive: () => Effect.Effect<void, CapabilityError>;
  }
>()("devys/Invocation") {}

/** Limits a grant can place on this capability, as fields only it understands. */
export interface Constraints {
  readonly schema: Schema.ConstraintDecoder<unknown>;
  readonly allows: (constraints: unknown, input: unknown) => boolean;
}

export interface Capability {
  readonly name: string;
  readonly description: string;
  readonly effect: EffectClass;
  readonly constraints?: Constraints;
  readonly replay: "read" | "idempotent" | "reconcile";
  readonly input: Schema.Top;
  readonly output: Schema.Top;
  /** A direct tool for every employee; the rest are found with describe_capabilities. */
  readonly core?: true;
  readonly execute: (args: unknown) => Effect.Effect<unknown, CapabilityError, Invocation>;
}

/** Runtime implementations close over their services; contracts remain Effect-native. */
export function capability<I, O, C = never>(definition: {
  name: string;
  description: string;
  effect: EffectClass;
  constraints?: { schema: Schema.Codec<C>; allows: (constraints: C, input: I) => boolean };
  replay: Capability["replay"];
  /** Decoded types may be branded (such as `Ref`); the encoded side is plain JSON. */
  input: Schema.Codec<I, unknown>;
  output: Schema.Codec<O, unknown>;
  core?: true;
  execute: (input: I) => Effect.Effect<O, CapabilityError, Invocation>;
}): Capability {
  const contract: Capability = {
    ...definition,
    constraints: definition.constraints && {
      schema: definition.constraints.schema,
      allows: (constraints, input) => definition.constraints!.allows(constraints as C, input as I),
    },
    execute: (args) =>
      Effect.gen(function* () {
        const invocation = yield* Invocation;
        yield* invocation.assertActive();
        const input = yield* Schema.decodeUnknownEffect(definition.input)(args).pipe(
          Effect.mapError(
            () =>
              new CapabilityError({
                code: "invalid_input",
                message: `Invalid arguments for ${definition.name}`,
              }),
          ),
        );
        yield* invocation.authorize(contract, input);
        const result = yield* definition.execute(input);
        return yield* Schema.decodeUnknownEffect(definition.output)(result).pipe(
          Effect.mapError(
            () =>
              new CapabilityError({
                code: "unavailable",
                message: `Invalid result from ${definition.name}`,
              }),
          ),
        );
      }),
  };
  return contract;
}

export const Text = Schema.String.check(Schema.isMaxLength(64_000));

/** A picture the model sees: a capability's output field `image` reaches the model as one. */
export const Image = Schema.Struct({
  mimeType: Schema.Literals(["image/jpeg", "image/png"]),
  /** Base64. */
  data: Schema.String,
});
export type Image = typeof Image.Type;

/** The output's `image`, when it has one. */
export const imageOf = (output: unknown): Image | undefined => {
  const image = (output as { image?: unknown } | null)?.image;
  return Schema.is(Image)(image) ? image : undefined;
};
/**
 * An absolute file path. The runner decides where it may point: the cloud sandbox keeps
 * paths under /workspace; the trusted Mac host allows the owner's whole filesystem.
 */
export const FilePath = Schema.String.check(
  Schema.isPattern(/^\//),
  Schema.isMaxLength(1024),
  Schema.makeFilter(
    (path) =>
      !path.includes("\u0000") && !path.split("/").some((part) => part === "." || part === ".."),
  ),
);
