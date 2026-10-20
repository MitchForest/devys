import { Effect } from "effect";
import { CapabilityError } from "./capability.ts";
export const rpc = <A>(operation: () => Promise<A>) =>
  Effect.tryPromise({
    try: operation,
    catch: () =>
      new CapabilityError({
        code: "unavailable",
        message: "Operation failed; inspect state before retrying a write.",
      }),
  });
