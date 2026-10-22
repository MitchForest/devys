/**
 * The envelope vault's cryptography (WebCrypto only, so the Mac host runs it now and a Worker can
 * in cloud mode): each value is encrypted with AES-256-GCM under its own random data key; the data
 * key is encrypted (wrapped) under the master key. Both carry the business, name and kind as
 * additional data, so a ciphertext moved to another business, name or kind fails to open.
 */
import type { Sealed, SecretKind } from "./contract.ts";

const encoder = new TextEncoder();

const base64 = (bytes: Uint8Array) => {
  let text = "";
  for (const byte of bytes) text += String.fromCharCode(byte);
  return btoa(text);
};
const bytesOf = (text: string) => Uint8Array.from(atob(text), (char) => char.charCodeAt(0));

const boundTo = (business: string, name: string, kind: SecretKind) =>
  encoder.encode(JSON.stringify(["devys-vault", business, name, kind]));

const aes = (raw: Uint8Array<ArrayBuffer>, use: KeyUsage) =>
  crypto.subtle.importKey("raw", raw, "AES-GCM", false, [use]);

/** `iv || ciphertext` under `key`. */
async function encrypt(key: CryptoKey, plain: Uint8Array<ArrayBuffer>, data: Uint8Array) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv, additionalData: data as Uint8Array<ArrayBuffer> },
      key,
      plain,
    ),
  );
  const out = new Uint8Array(12 + cipher.length);
  out.set(iv);
  out.set(cipher, 12);
  return out;
}

async function decrypt(key: CryptoKey, sealed: Uint8Array<ArrayBuffer>, data: Uint8Array) {
  return new Uint8Array(
    await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: sealed.subarray(0, 12),
        additionalData: data as Uint8Array<ArrayBuffer>,
      },
      key,
      sealed.subarray(12),
    ),
  );
}

/** Seals and opens with a 32-byte master key. */
export async function envelopeKeyring(master: Uint8Array<ArrayBuffer>) {
  if (master.length !== 32) throw new Error("The vault's master key is 32 bytes");
  const wrapping = await crypto.subtle.importKey("raw", master, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
  return {
    async seal(business: string, name: string, kind: SecretKind, value: string): Promise<Sealed> {
      const bound = boundTo(business, name, kind);
      const dataKey = crypto.getRandomValues(new Uint8Array(32));
      const data = await encrypt(await aes(dataKey, "encrypt"), encoder.encode(value), bound);
      const key = await encrypt(wrapping, dataKey, bound);
      dataKey.fill(0);
      return { business, name, kind, key: base64(key), data: base64(data) };
    },
    /** The value; throws when the envelope was changed, moved or sealed under another key. */
    async open(sealed: Sealed): Promise<string> {
      const bound = boundTo(sealed.business, sealed.name, sealed.kind);
      const dataKey = await decrypt(wrapping, bytesOf(sealed.key), bound);
      const value = await decrypt(await aes(dataKey, "decrypt"), bytesOf(sealed.data), bound);
      dataKey.fill(0);
      return new TextDecoder().decode(value);
    },
  };
}
export type EnvelopeKeyring = Awaited<ReturnType<typeof envelopeKeyring>>;
