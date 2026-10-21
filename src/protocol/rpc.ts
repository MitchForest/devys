import { Effect } from "effect";
import { CapabilityError } from "./capability.ts";
import { HostRefusal, Unavailable } from "./host.ts";

/**
 * A failure as the model sees it. Devys's own refusals (the Mac host's 4xx answers, an
 * unavailable deployment) keep their text, bounded, so an employee can tell a busy workspace
 * from a path outside the business folder; anything else (driver, library or network errors
 * that may carry internals) stays generic.
 */
const failed = (error: unknown) => {
  const reason =
    error instanceof HostRefusal || error instanceof Unavailable
      ? error.message.slice(0, 300).replace(/[.\s]+$/, "")
      : "";
  return new CapabilityError({
    code: "unavailable",
    message: reason
      ? `Operation failed: ${reason}; inspect state before retrying a write.`
      : "Operation failed; inspect state before retrying a write.",
  });
};

/** A promise whose rejection is a typed `unavailable`, never a defect. */
export const rpc = <A>(operation: () => Promise<A>) =>
  Effect.tryPromise({ try: operation, catch: failed });

/** A store's effect whose failure is a typed `unavailable`. */
export const stored = <A, E, R>(effect: Effect.Effect<A, E, R>) =>
  effect.pipe(Effect.mapError(failed));
