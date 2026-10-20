/**
 * The trusted Mac host's shared request plumbing (local mode). Each component that runs on
 * the host answers JSON POSTs under its own path prefix; `src/host.ts` composes them behind
 * one loopback server and its token.
 */

/** Ids the host accepts in a scope, a path segment or an assignment. */
export const hostId = /^[A-Za-z0-9-]{1,64}$/;

/** A request's business and employee, or a 400 refusal. */
export function scopeOf(value: unknown): { businessId: string; employeeId: string } {
  const scope = value as Partial<{ businessId: string; employeeId: string }> | undefined;
  if (!scope || !hostId.test(scope.businessId ?? "") || !hostId.test(scope.employeeId ?? ""))
    throw new HostRefusal(400, "Missing or invalid scope");
  return { businessId: scope.businessId!, employeeId: scope.employeeId! };
}

/** A refusal the host answers with this HTTP status and message. */
export class HostRefusal extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

/** One component's routes on the host. */
export interface HostRoutes {
  /** For example `/delegates/`. */
  readonly prefix: string;
  /** Answers a JSON POST to `path` (which starts with the prefix) with a JSON value. */
  handle(path: string, input: Record<string, unknown>): Promise<unknown>;
  /**
   * Answers a streaming GET under the prefix, or returns false if it isn't one. `write(null)`
   * ends the response; `closed` settles when the client goes away. Returning true means the
   * response is complete; "open" means it stays open until written to completion or closed.
   */
  stream?(
    path: string,
    url: URL,
    write: (chunk: Uint8Array | null) => void,
    closed: Promise<void>,
  ): boolean | "open";
  close(): Promise<void>;
}
