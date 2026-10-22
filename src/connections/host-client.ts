import { hostDown, hostFailure, Unavailable } from "../protocol/host.ts";
import type { RemoteApps } from "./contract.ts";

/** Remote apps' MCP client on the Mac host (local mode), which alone opens their tokens. */
export function hostRemoteApps(host: { url: string; token: string }): RemoteApps {
  async function call<T>(path: string, body: unknown): Promise<T> {
    let response: Response;
    try {
      response = await fetch(`${host.url}/mcp/${path}`, {
        method: "POST",
        headers: { authorization: `Bearer ${host.token}`, "content-type": "application/json" },
        body: JSON.stringify(body),
      });
    } catch {
      throw hostDown("remote apps are");
    }
    if (!response.ok) throw await hostFailure(response);
    return (await response.json()) as T;
  }
  return {
    begin: (input) => call("begin", input),
    finish: (input) => call("finish", input),
    tools: (input) => call("tools", input),
    call: (input) => call("call", input),
  };
}

/** Where no one holds the vault's key (cloud mode until CM): remote apps can't be reached. */
export function unavailableRemoteApps(why: string): RemoteApps {
  const refuse = () => Promise.reject(new Unavailable(why));
  return { begin: refuse, finish: refuse, tools: refuse, call: refuse };
}
