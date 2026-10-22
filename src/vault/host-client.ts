import { hostDown, hostFailure } from "../protocol/host.ts";
import type { Keyring, Sealed, SendWithSecret } from "./contract.ts";

/** The vault's side of the Mac host (local mode): it seals, and sends connection requests. */
export function hostVault(host: { url: string; token: string }) {
  async function call<T>(path: string, body: Record<string, unknown>): Promise<T> {
    let response: Response;
    try {
      response = await fetch(`${host.url}/vault/${path}`, {
        method: "POST",
        headers: { authorization: `Bearer ${host.token}`, "content-type": "application/json" },
        body: JSON.stringify(body),
      });
    } catch {
      throw hostDown("secrets are");
    }
    if (!response.ok) throw await hostFailure(response);
    return (await response.json()) as T;
  }
  const keyring: Keyring = {
    seal: (business, name, kind, value) => call<Sealed>("seal", { business, name, kind, value }),
  };
  const send: SendWithSecret = (secret, request, placeholder) =>
    call("request", { secret, request, placeholder });
  return { keyring, send };
}
