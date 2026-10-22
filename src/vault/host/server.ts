/**
 * The vault on the trusted Mac host (local mode): the only holder of the master key. It seals what
 * the Worker stores, and opens a secret only inside an injection path on this host (a command's
 * environment, a deploy, a browser fill, a connection's request), never back to the Worker.
 *
 * The master key is a 0600 file in the host's data folder, which every process started for an
 * employee is denied by Seatbelt (../../workspace/host/seatbelt.ts). Not the login Keychain:
 * employees' processes run as the owner, and a Keychain item readable by the host's `bun` (or by
 * `/usr/bin/security`) is readable by the same binary run from a confined process, silently
 * (.docs/AUTHORITY.md#credentials, with the test that proves the file is out of reach).
 */
import { randomBytes } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { HostRefusal, hostId, type HostRoutes } from "../../protocol/host.ts";
import { redact, type Sealed, type SecretKind } from "../contract.ts";
import { envelopeKeyring, type EnvelopeKeyring } from "../envelope.ts";

/** The master key, created on first start: 32 random bytes as hex in `<data>/vault.key`. */
export function masterKey(data: string): Uint8Array<ArrayBuffer> {
  mkdirSync(data, { recursive: true });
  const file = join(data, "vault.key");
  if (!existsSync(file))
    writeFileSync(file, Buffer.from(randomBytes(32)).toString("hex"), { mode: 0o600, flag: "wx" });
  chmodSync(file, 0o600);
  const hex = readFileSync(file, "utf8").trim();
  if (!/^[a-f0-9]{64}$/.test(hex)) throw new Error(`${file} is not a vault key`);
  return Uint8Array.from(hex.match(/../g)!, (pair) => parseInt(pair, 16));
}

/** The host's keyring from its data folder. */
export const hostKeyring = (data: string) => envelopeKeyring(masterKey(data));

const kinds: readonly SecretKind[] = ["secret", "spend", "connection"];

/** A sealed secret as the Worker sends it, or a refusal. */
export function sealedFrom(value: unknown): Sealed {
  const sealed = value as Partial<Sealed> | null;
  if (
    !sealed ||
    typeof sealed !== "object" ||
    !hostId.test(sealed.business ?? "") ||
    typeof sealed.name !== "string" ||
    !/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(sealed.name) ||
    !kinds.includes(sealed.kind as SecretKind) ||
    typeof sealed.key !== "string" ||
    typeof sealed.data !== "string" ||
    sealed.key.length > 200 ||
    sealed.data.length > 32_000
  )
    throw new HostRefusal(400, "Invalid sealed secret");
  return {
    business: sealed.business!,
    name: sealed.name,
    kind: sealed.kind!,
    key: sealed.key,
    data: sealed.data,
  };
}

/**
 * Opens secrets for one injection: each must belong to `business` and be one of `allowed` kinds
 * (a card is never opened into a command). The kind is bound into the ciphertext, so a relabelled
 * secret fails to open.
 */
export async function openFor(
  keyring: EnvelopeKeyring,
  business: string,
  given: unknown,
  allowed: readonly SecretKind[],
) {
  if (given === undefined) return new Map<string, string>();
  if (!Array.isArray(given) || given.length > 20)
    throw new HostRefusal(400, "Name at most 20 secrets");
  const opened = new Map<string, string>();
  for (const each of given) {
    const sealed = sealedFrom(each);
    if (sealed.business !== business)
      throw new HostRefusal(403, "That secret belongs to another business");
    if (!allowed.includes(sealed.kind))
      throw new HostRefusal(
        403,
        sealed.kind === "spend"
          ? `${sealed.name} is a card: it is filled at a checkout (browserFill) against a signed spend approval, never put in a command`
          : `${sealed.name} can't be used here`,
      );
    try {
      opened.set(sealed.name, await keyring.open(sealed));
    } catch {
      throw new HostRefusal(403, `${sealed.name} could not be opened`);
    }
  }
  return opened;
}

const placeholderPattern = /^[A-Za-z0-9_-]{16,64}$/;
const responseBytes = 1_000_000;

/**
 * The vault's host routes: `/vault/seal` seals a value for the Worker to store; `/vault/request`
 * sends one HTTPS request with a connection's secret where the placeholder stands (in a header as
 * is, in a form body URL-encoded, in a JSON body JSON-escaped) and returns the answer with the
 * secret redacted.
 */
export function vaultHost(keyring: EnvelopeKeyring): HostRoutes {
  return {
    prefix: "/vault/",
    async handle(path, input) {
      if (path === "/vault/seal") {
        const { business, name, kind, value } = input as Record<string, unknown>;
        if (
          typeof business !== "string" ||
          !hostId.test(business) ||
          typeof name !== "string" ||
          !/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(name) ||
          !kinds.includes(kind as SecretKind) ||
          typeof value !== "string" ||
          !value ||
          value.length > 16_000
        )
          throw new HostRefusal(400, "Seal a named value of a known kind");
        return keyring.seal(business, name, kind as SecretKind, value);
      }
      if (path === "/vault/request") {
        const sealed = sealedFrom(input.secret);
        const [value] = (
          await openFor(keyring, sealed.business, [sealed], ["connection"])
        ).values();
        const request = input.request as Record<string, unknown> | undefined;
        const placeholder = input.placeholder;
        const url = typeof request?.url === "string" ? request.url : "";
        if (
          !/^https:\/\/[^\s]{1,2000}$/.test(url) ||
          (request?.method !== "GET" && request?.method !== "POST") ||
          typeof placeholder !== "string" ||
          !placeholderPattern.test(placeholder)
        )
          throw new HostRefusal(400, "Send an https GET or POST with a placeholder");
        const headers = Object.fromEntries(
          Object.entries((request.headers as Record<string, unknown>) ?? {})
            .filter((entry): entry is [string, string] => typeof entry[1] === "string")
            .map(([name, text]) => [name, text.split(placeholder).join(value!)]),
        );
        const type = Object.entries(headers).find(([name]) => /^content-type$/i.test(name))?.[1];
        const fill = /x-www-form-urlencoded/i.test(type ?? "")
          ? encodeURIComponent(value!)
          : /json/i.test(type ?? "")
            ? JSON.stringify(value).slice(1, -1)
            : value!;
        const body =
          typeof request.body === "string" ? request.body.split(placeholder).join(fill) : undefined;
        const response = await fetch(url, {
          method: request.method,
          headers,
          ...(body !== undefined ? { body } : {}),
          redirect: "manual",
          signal: AbortSignal.timeout(20_000),
        }).catch(() => {
          throw new HostRefusal(502, "The request didn't reach its server");
        });
        const text = (await response.text()).slice(0, responseBytes);
        return {
          status: response.status,
          type: response.headers.get("content-type"),
          body: redact(text, [value!]),
        };
      }
      throw new HostRefusal(404, "Not found");
    },
    close: async () => {},
  };
}
