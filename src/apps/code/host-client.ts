import type { Scope } from "../../identity/contract.ts";
import { hostCallMs, hostPost, Unavailable } from "../../protocol/host.ts";
import type { Sealed } from "../../vault/contract.ts";
import type { CodingHost } from "./contract.ts";

/**
 * Coding sessions on the trusted Mac host (local mode). The host owns worktrees, sessions
 * and checks; this side only speaks to it, always naming the business it acts for.
 */
export function hostCoding(
  host: {
    url: string;
    token: string;
    /** The business's named secrets, sealed, for the host to put in a deploy (the vault). */
    sealed?: (businessId: string, names: readonly string[]) => Promise<Sealed[]>;
  },
  scope: Scope,
): CodingHost {
  // Starting a provider's session or pushing a branch can take longer than a plain host call.
  const call = <T>(path: string, body: Record<string, unknown>) =>
    hostPost<T>(host, `/coding/${path}`, { scope, ...body }, "coding sessions are", 2 * hostCallMs);
  /** A deploy request with the secrets it names sealed for the host. */
  async function sealing<T extends { secrets?: readonly string[] }>({
    secrets = [],
    ...request
  }: T) {
    if (secrets.length && !host.sealed) throw new Error("Secrets are not available here");
    return {
      ...request,
      ...(secrets.length ? { secrets: await host.sealed!(scope.businessId, secrets) } : {}),
    };
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
    deploy: async (id, request) => call("deploy", { id, ...(await sealing(request)) }),
    deployRepository: async (request) => call("deploy-repository", await sealing(request)),
  };
}

/** Cloud mode has no coding runner yet; every call says so. */
export function unavailableCoding(): CodingHost {
  const refuse = () =>
    Promise.reject(
      new Unavailable(
        "Coding sessions run in local mode only until a cloud runner with API keys exists.",
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
    deploy: refuse,
    deployRepository: refuse,
  };
}
