/**
 * Device signatures (.docs/AUTHORITY.md#bringing-the-owner-in-askowner-and-signed-spend-approvals):
 * the canonical payloads an owner's Mac or iPhone signs with its Secure Enclave P-256 key, and
 * their verification with WebCrypto. The native apps build the same bytes
 * (`SpendApproval.canonical` in DevysClient), checked against a golden file.
 *
 * A payload is JSON with its keys in sorted order and no whitespace, strings escaped as
 * `JSON.stringify` escapes them, and every field present (`null` when absent; `[]` for no steps). The device signs
 * its UTF-8 bytes with ECDSA over SHA-256; the signature is DER (X9.62), as the Secure Enclave
 * produces it, and the public key is X9.63 uncompressed (65 bytes), both base64.
 */

/**
 * What a spend approval binds: the request, where it is spent, the steps and draft it covers
 * (the draft by its ref and the hash of its content when asked), and until when.
 */
export interface SpendTerms {
  decision: string;
  business: string;
  workItem: string;
  action: string;
  counterparty: string;
  amountCents: number;
  currency: string;
  renewal: string | null;
  steps: readonly string[];
  preview: string | null;
  previewHash: string | null;
  expiresAt: string;
}

/** The exact text a spend approval's signature covers. */
export const spendPayload = (terms: SpendTerms) =>
  JSON.stringify({
    action: terms.action,
    amount_cents: terms.amountCents,
    business: terms.business,
    counterparty: terms.counterparty,
    currency: terms.currency,
    decision: terms.decision,
    expires_at: terms.expiresAt,
    preview: terms.preview,
    preview_hash: terms.previewHash,
    renewal: terms.renewal,
    steps: terms.steps,
    type: "spend_approval",
    work_item: terms.workItem,
  });

/** The exact text an active key signs to let another of the person's devices sign. */
export const endorsementPayload = (terms: {
  person: string;
  key: string;
  device: string;
  publicKey: string;
}) =>
  JSON.stringify({
    device: terms.device,
    key: terms.key,
    person: terms.person,
    public_key: terms.publicKey,
    type: "device_key",
  });

/** Standard base64 to bytes, or undefined when it isn't base64. */
export function fromBase64(text: string): Uint8Array<ArrayBuffer> | undefined {
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(text) || text.length % 4 !== 0) return undefined;
  return Uint8Array.from(atob(text), (char) => char.charCodeAt(0));
}

/** A P-256 public key as the devices send it: X9.63 uncompressed, base64. */
export const isPublicKey = (text: string) => {
  const bytes = fromBase64(text);
  return bytes?.length === 65 && bytes[0] === 4;
};

/**
 * A DER ECDSA signature (`SEQUENCE { INTEGER r, INTEGER s }`) as the 64-byte `r || s` WebCrypto
 * verifies; undefined when it is not exactly that.
 */
export function rawSignature(der: Uint8Array): Uint8Array<ArrayBuffer> | undefined {
  let at = 0;
  const byte = () => (at < der.length ? der[at++]! : -1);
  if (byte() !== 0x30) return;
  const length = byte();
  if (length < 0 || length >= 0x80 || length !== der.length - 2) return;
  const out = new Uint8Array(64);
  for (const offset of [0, 32]) {
    if (byte() !== 0x02) return;
    const size = byte();
    if (size < 1 || size > 33 || at + size > der.length) return;
    let value = der.subarray(at, at + size);
    at += size;
    // A positive INTEGER is minimal: a leading zero only before a high bit.
    if (value.length > 1 && value[0] === 0 && (value[1]! & 0x80) === 0) return;
    if (value[0]! & 0x80) return;
    if (value[0] === 0 && value.length > 1) value = value.subarray(1);
    if (value.length > 32) return;
    out.set(value, offset + 32 - value.length);
  }
  return at === der.length ? out : undefined;
}

/** Whether `signature` (DER, base64) is this key's signature of `payload`. */
export async function verifySignature(publicKey: string, payload: string, signature: string) {
  const key = fromBase64(publicKey);
  const der = fromBase64(signature);
  const raw = der && rawSignature(der);
  if (!key || !raw || !isPublicKey(publicKey)) return false;
  try {
    const imported = await crypto.subtle.importKey(
      "raw",
      key,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    return await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      imported,
      raw,
      new TextEncoder().encode(payload),
    );
  } catch {
    return false;
  }
}
