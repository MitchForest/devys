import { hostCallMs, hostPost, Unavailable } from "../protocol/host.ts";
import type { RemoteApps } from "./contract.ts";

/** Remote apps' MCP client on the Mac host (local mode), which alone opens their tokens. */
export function hostRemoteApps(host: { url: string; token: string }): RemoteApps {
  const call = <T>(path: string, body: unknown, ms?: number) =>
    hostPost<T>(host, `/mcp/${path}`, body, "remote apps are", ms);
  return {
    begin: (input) => call("begin", input),
    finish: (input) => call("finish", input),
    tools: (input) => call("tools", input),
    // A remote app's own work (a report, a search) may take longer than a host call.
    call: (input) => call("call", input, 2 * hostCallMs),
  };
}

/** Where no one holds the vault's key (cloud mode until CM): remote apps can't be reached. */
export function unavailableRemoteApps(why: string): RemoteApps {
  const refuse = () => Promise.reject(new Unavailable(why));
  return { begin: refuse, finish: refuse, tools: refuse, call: refuse };
}
