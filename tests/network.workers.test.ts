import { expect, it } from "vitest";
import { publicAddress, publicUrl } from "../src/egress/public.ts";

it.each([
  "http://example.com",
  "https://127.0.0.1",
  "https://0x7f000001",
  "https://[::1]",
  "https://a.local",
  "https://a.internal",
  "https://user:pass@example.com",
  "https://example.com:8080",
])("rejects non-public or credential-bearing URL %s", (url) => {
  expect(() => publicUrl(url)).toThrow();
});
it("blocks application endpoints and private DNS answers", () => {
  expect(() => publicUrl("https://devys.example.com/api/status", ["devys.example.com"])).toThrow();
  for (const ip of [
    "10.0.0.1",
    "169.254.169.254",
    "127.0.0.1",
    "172.16.1.1",
    "192.168.1.1",
    "100.64.0.1",
    "::1",
    "fc00::1",
    "fe80::1",
    "2001:db8::1",
  ])
    expect(publicAddress(ip)).toBe(false);
  expect(publicAddress("1.1.1.1")).toBe(true);
  expect(publicUrl("https://example.com/a").pathname).toBe("/a");
});
