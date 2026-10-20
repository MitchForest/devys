import type { Scope } from "../identity/contract.ts";
import type { Delegates } from "./contract.ts";

/**
 * Coding delegates on the trusted Mac host (local mode). The host owns worktrees, sessions
 * and checks; this side only speaks to it, always naming the business it acts for.
 */
export function hostDelegates(host: { url: string; token: string }, scope: Scope): Delegates {
  async function call<T>(path: string, body: Record<string, unknown>): Promise<T> {
    let response: Response;
    try {
      response = await fetch(`${host.url}/delegates/${path}`, {
        method: "POST",
        headers: { authorization: `Bearer ${host.token}`, "content-type": "application/json" },
        body: JSON.stringify({ scope, ...body }),
      });
    } catch {
      throw new Error("The Mac host is not running, so coding delegates are unavailable.");
    }
    if (!response.ok)
      throw new Error((await response.text()) || `Mac host error ${response.status}`);
    return (await response.json()) as T;
  }
  return {
    start: (request) => call("start", { request }),
    inspect: (id) => call("inspect", { id }),
    diff: (id) => call("diff", { id }),
    transcript: (id) => call("transcript", { id }),
    send: (id, text) => call("send", { id, text }),
    interrupt: async (id) => {
      await call("interrupt", { id });
    },
    accept: (id, request) => call("accept", { id, ...request }),
    publish: (id, request) => call("publish", { id, ...request }),
  };
}

/** Cloud mode has no delegate runner yet; every call says so. */
export function unavailableDelegates(): Delegates {
  const refuse = () =>
    Promise.reject(
      new Error(
        "Coding delegates run in local mode only until a cloud runner with API keys exists.",
      ),
    );
  return {
    start: refuse,
    inspect: refuse,
    diff: refuse,
    transcript: refuse,
    send: refuse,
    interrupt: refuse,
    accept: refuse,
    publish: refuse,
  };
}
