import { hostPost } from "../protocol/host.ts";
import type { Keyring, Sealed, SendWithSecret } from "./contract.ts";

/** The vault's side of the Mac host (local mode): it seals, and sends connection requests. */
export function hostVault(host: { url: string; token: string }) {
  const call = <T>(path: string, body: Record<string, unknown>) =>
    hostPost<T>(host, `/vault/${path}`, body, "secrets are");
  const keyring: Keyring = {
    seal: (business, name, kind, value) => call<Sealed>("seal", { business, name, kind, value }),
  };
  const send: SendWithSecret = (secret, request, placeholder) =>
    call("request", { secret, request, placeholder });
  return { keyring, send };
}
