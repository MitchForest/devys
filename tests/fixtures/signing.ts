/** A device signing key for tests: WebCrypto P-256, signing as the Secure Enclave does (DER). */
export const base64 = (bytes: ArrayBuffer | Uint8Array) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes)));

/** WebCrypto's `r || s` as the DER the Secure Enclave produces. */
export function derSignature(raw: Uint8Array) {
  const integer = (value: Uint8Array) => {
    let at = 0;
    while (at < value.length - 1 && value[at] === 0) at++;
    const trimmed = value.subarray(at);
    const bytes = trimmed[0]! & 0x80 ? [0, ...trimmed] : [...trimmed];
    return [0x02, bytes.length, ...bytes];
  };
  const body = [...integer(raw.subarray(0, 32)), ...integer(raw.subarray(32))];
  return new Uint8Array([0x30, body.length, ...body]);
}

/** A fresh key: its X9.63 public key (base64) and a signer of payload text. */
export async function deviceKey() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ]);
  const publicKey = base64(await crypto.subtle.exportKey("raw", pair.publicKey));
  const sign = async (payload: string) =>
    base64(
      derSignature(
        new Uint8Array(
          await crypto.subtle.sign(
            { name: "ECDSA", hash: "SHA-256" },
            pair.privateKey,
            new TextEncoder().encode(payload),
          ),
        ),
      ),
    );
  return { publicKey, sign };
}
