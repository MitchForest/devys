import { Effect } from "effect";
import { CapabilityError } from "./capability.ts";

const failed = () =>
  new CapabilityError({
    code: "unavailable",
    message: "Operation failed; inspect state before retrying a write.",
  });

/** A promise whose rejection is a typed `unavailable`, never a defect. */
export const rpc = <A>(operation: () => Promise<A>) =>
  Effect.tryPromise({ try: operation, catch: failed });

/** A store's effect whose failure is a typed `unavailable`. */
export const stored = <A, E, R>(effect: Effect.Effect<A, E, R>) =>
  effect.pipe(Effect.mapError(failed));
