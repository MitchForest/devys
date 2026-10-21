import { readFileSync, writeFileSync } from "node:fs";
import { expect, it } from "vitest";
import {
  endorsementPayload,
  fromBase64,
  isPublicKey,
  rawSignature,
  spendPayload,
  verifySignature,
} from "../src/authority/signing.ts";
import { base64, deviceKey } from "./fixtures/signing.ts";

const terms = {
  decision: "00000000-0000-4000-8000-000000000001",
  business: "00000000-0000-4000-8000-000000000002",
  workItem: "00000000-0000-4000-8000-000000000003",
  // Quotes, a backslash, a slash, controls and non-ASCII: escaped exactly as JSON.stringify does.
  action: 'Register "acme.example" for 1 year\\2 — café ☕ a/b\n\ttab \u0001 \u001f',
  counterparty: "Namecheap",
  amountCents: 1299,
  currency: "USD",
  renewal: "Renews yearly at $12.99",
  expiresAt: "2026-10-22T09:30:00.000Z",
};

it("a spend approval's payload is canonical JSON: sorted keys, every field, no whitespace", () => {
  expect(spendPayload({ ...terms, action: "Buy", renewal: null })).toBe(
    '{"action":"Buy","amount_cents":1299,"business":"00000000-0000-4000-8000-000000000002","counterparty":"Namecheap","currency":"USD","decision":"00000000-0000-4000-8000-000000000001","expires_at":"2026-10-22T09:30:00.000Z","renewal":null,"type":"spend_approval","work_item":"00000000-0000-4000-8000-000000000003"}',
  );
  expect(
    endorsementPayload({ person: "p", key: "k", device: "0123456789abcdef", publicKey: "AQ==" }),
  ).toBe(
    '{"device":"0123456789abcdef","key":"k","person":"p","public_key":"AQ==","type":"device_key"}',
  );
});

it("a device's DER signature verifies; a changed payload, another key or a malformed one does not", async () => {
  const device = await deviceKey();
  const other = await deviceKey();
  expect(isPublicKey(device.publicKey)).toBe(true);
  expect(isPublicKey(base64(new Uint8Array(33)))).toBe(false);
  const payload = spendPayload(terms);
  const signature = await device.sign(payload);
  expect(await verifySignature(device.publicKey, payload, signature)).toBe(true);
  expect(
    await verifySignature(
      device.publicKey,
      spendPayload({ ...terms, amountCents: 1300 }),
      signature,
    ),
  ).toBe(false);
  expect(
    await verifySignature(
      device.publicKey,
      spendPayload({ ...terms, counterparty: "GoDaddy" }),
      signature,
    ),
  ).toBe(false);
  expect(await verifySignature(other.publicKey, payload, signature)).toBe(false);
  expect(await verifySignature(device.publicKey, payload, "not base64!")).toBe(false);
  // The raw form WebCrypto makes is not what devices send.
  const der = fromBase64(signature)!;
  expect(await verifySignature(device.publicKey, payload, base64(rawSignature(der)!))).toBe(false);
  // Trailing bytes and a non-minimal integer are refused.
  expect(rawSignature(new Uint8Array([...der, 0]))).toBeUndefined();
  expect(rawSignature(new Uint8Array([0x30, 6, 0x02, 2, 0, 1, 0x02, 1, 1]))).toBeUndefined();
});

/**
 * The golden file the native client's `SpendApproval` is checked against: the Swift mirror
 * must build the same payload from the decision, and verify this signature with CryptoKit.
 * `DEVYS_WRITE_WIRE=1 bunx vitest run tests/signing.test.ts` writes a new one.
 */
const golden =
  "apple/Packages/DevysKit/Tests/DevysClientTests/Fixtures/signing/spend-approval.json";

it("the native client's golden spend approval matches the server's payload and signature", async () => {
  const payload = spendPayload(terms);
  const decision = {
    id: terms.decision,
    kind: "approve",
    employee_id: "00000000-0000-4000-8000-000000000004",
    capability: "askOwner",
    input: {
      kind: "approve",
      action: terms.action,
      counterparty: terms.counterparty,
      amount: { cents: terms.amountCents, currency: terms.currency },
      renewal: terms.renewal,
    },
    work_item_id: terms.workItem,
    conversation: `work:${terms.workItem}`,
    status: "pending",
    requested_at: "2026-10-21T09:30:00.000Z",
    expires_at: terms.expiresAt,
    signed_by: null,
  };
  if (process.env.DEVYS_WRITE_WIRE === "1") {
    const device = await deviceKey();
    writeFileSync(
      golden,
      `${JSON.stringify(
        {
          business_id: terms.business,
          decision,
          payload,
          public_key: device.publicKey,
          signature: await device.sign(payload),
        },
        null,
        2,
      )}\n`,
    );
  }
  const committed = JSON.parse(readFileSync(golden, "utf8")) as {
    business_id: string;
    decision: unknown;
    payload: string;
    public_key: string;
    signature: string;
  };
  expect(committed.decision).toEqual(decision);
  expect(committed.business_id).toBe(terms.business);
  expect(committed.payload).toBe(payload);
  expect(await verifySignature(committed.public_key, payload, committed.signature)).toBe(true);
});
