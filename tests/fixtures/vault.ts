import type { Sealed, SecretKind, SecretStore } from "../../src/vault/contract.ts";
import type { EnvelopeKeyring } from "../../src/vault/envelope.ts";

/**
 * A vault store kept in memory over a real keyring, for tests of the paths that hand sealed
 * secrets to the host (commands, deploys, fills): the same sealing, without Postgres.
 */
export function memorySecrets(
  keyring: EnvelopeKeyring,
): SecretStore & { stored: Map<string, Sealed> } {
  const stored = new Map<string, Sealed>();
  const key = (business: string, name: string) => `${business}/${name}`;
  return {
    stored,
    async put(business, name, kind, value) {
      stored.set(key(business, name), await keyring.seal(business, name, kind, value));
    },
    async putSealed(sealed) {
      stored.set(key(sealed.business, sealed.name), sealed);
    },
    list: async (business) =>
      [...stored.values()]
        .filter((sealed) => sealed.business === business && sealed.kind !== "connection")
        .map((sealed) => ({
          name: sealed.name,
          kind: sealed.kind as "secret" | "spend",
          added_by: "owner",
          added_at: new Date(0).toISOString(),
          last_used_at: null,
        })),
    remove: async (business, name) => stored.delete(key(business, name)),
    async sealed(business, names, kinds: readonly SecretKind[]) {
      return names.map((name) => {
        const sealed = stored.get(key(business, name));
        if (!sealed || !kinds.includes(sealed.kind)) throw new Error(`No secret named ${name}`);
        return sealed;
      });
    },
  };
}
