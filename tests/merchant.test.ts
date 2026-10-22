import { expect, it } from "vitest";
import { merchantRefusal, merchantSite } from "../src/browser/host/merchant.ts";
import { redact } from "../src/vault/contract.ts";

it("a spend approval's merchant is the registrable domain its counterparty names", () => {
  expect(merchantSite("namecheap.com")).toBe("namecheap.com");
  expect(merchantSite("Namecheap (www.namecheap.com)")).toBe("namecheap.com");
  expect(merchantSite("https://ap.www.namecheap.com/cart?x=1")).toBe("namecheap.com");
  expect(merchantSite("Acme Ltd, acme.co.uk.")).toBe("acme.co.uk");
  expect(merchantSite("Namecheap")).toBeUndefined();
  expect(merchantSite("co.uk")).toBeUndefined();
  expect(merchantSite("127.0.0.1:5173")).toBe("127.0.0.1");
});

it("a card is filled only on an https page of that merchant's site", () => {
  expect(merchantRefusal("https://www.namecheap.com/checkout", "namecheap.com")).toBeUndefined();
  expect(
    merchantRefusal("https://ap.www.namecheap.com/pay", "Namecheap (namecheap.com)"),
  ).toBeUndefined();
  for (const page of [
    "https://namecheap.com.evil.example/checkout",
    "https://evilnamecheap.com/checkout",
    "https://shop.example/checkout",
  ])
    expect(merchantRefusal(page, "namecheap.com")).toMatch(/not namecheap\.com/);
  expect(merchantRefusal("http://www.namecheap.com/checkout", "namecheap.com")).toMatch(/https/);
  expect(merchantRefusal("https://www.namecheap.com/", "Namecheap")).toMatch(/doesn't name/);
  // Different registrable domains under one public suffix are different merchants.
  expect(merchantRefusal("https://other.co.uk/", "acme.co.uk")).toMatch(/not acme\.co\.uk/);
  expect(merchantRefusal("http://127.0.0.1:4000/checkout", "127.0.0.1")).toBeUndefined();
});

it("output is redacted of a secret as is, URL-encoded, and cut at either end", () => {
  const secret = "p@ss word/42";
  expect(redact(`a ${secret} b ${encodeURIComponent(secret)}`, [secret])).toBe(
    "a [redacted] b [redacted]",
  );
  expect(redact(`${secret.slice(5)} then`, [secret])).toBe("[redacted] then");
  expect(redact(`starts ${secret.slice(0, 6)}`, [secret])).toBe("starts [redacted]");
  expect(redact("abc", ["abc"])).toBe("abc");
});
