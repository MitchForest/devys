/**
 * The trusted Mac host's shared request plumbing (local mode). Each component that runs on
 * the host answers JSON POSTs under its own path prefix; `src/host.ts` composes them behind
 * one loopback server and its token.
 */

/**
 * Removes the host's own settings (its token, ports, folders: every `DEVYS_` variable) from an
 * environment in place, so the shells, coding sessions and terminals that inherit it never see
 * them. The launcher already leaves out everything `.env` holds.
 */
export function forgetHostSettings(env: Record<string, string | undefined>) {
  for (const name of Object.keys(env)) if (name.startsWith("DEVYS_")) delete env[name];
  return env;
}

/**
 * What this deployment does not have, such as terminals in cloud mode or a Mac host that is
 * not configured. The API answers it as 503 with its message.
 */
export class Unavailable extends Error {}

/** Ids the host accepts in a scope, a path segment or a coding session. */
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

/**
 * What a host client throws for the host's non-OK answer. A refusal (4xx) is the host's own
 * text, so it stays a `HostRefusal` that employees may read (bounded); anything else is a plain
 * error whose detail is not shown to models.
 */
export async function hostFailure(response: Response) {
  const text = (await response.text()).slice(0, 500);
  if (response.status >= 400 && response.status < 500 && text)
    return new HostRefusal(response.status, text);
  return new Error(text || `Mac host error ${response.status}`);
}

/** What a host client throws when the Mac host does not answer at all. */
export const hostDown = (what: string) =>
  new Unavailable(`The Mac host is not running, so ${what} unavailable.`);

/** One component's routes on the host. */
export interface HostRoutes {
  /** For example `/coding/`. */
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
