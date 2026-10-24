import { Effect, Schema } from "effect";
import { describe, expect, it } from "vitest";
import type { Grant } from "../src/authority/contract.ts";
import { decide } from "../src/authority/service.ts";
import { allowedHost } from "../src/egress/capabilities.ts";
import { capability } from "../src/protocol/capability.ts";

const read = capability({
  name: "readPublicUrl",
  activity: "Reading a web page",
  description: "Read a public page",
  effect: "read",
  constraints: {
    schema: Schema.Struct({ hosts: Schema.optional(Schema.Array(Schema.String)) }),
    allows: ({ hosts }, { url }: { url: string }) => !hosts || allowedHost(url, hosts),
  },
  replay: "read",
  input: Schema.Struct({ url: Schema.String }),
  output: Schema.Struct({}),
  execute: () => Effect.succeed({}),
});
const plain = capability({
  name: "remember",
  activity: "Doing it",
  description: "Save a fact",
  effect: "change",
  replay: "idempotent",
  input: Schema.Struct({}),
  output: Schema.Struct({}),
  execute: () => Effect.succeed({}),
});
const grant = (overrides: Partial<Grant> = {}): Grant => ({
  id: "g1",
  capability: "readPublicUrl",
  mode: "auto",
  constraints: {},
  responsibility: null,
  created_at: "2026-10-19T00:00:00.000Z",
  ...overrides,
});

describe("authority", () => {
  it("denies without a grant, allows inside one, and asks when the grant says so", () => {
    expect(decide(undefined, plain, {})).toMatchObject({ outcome: "deny" });
    expect(decide(grant({ capability: "remember" }), plain, {})).toEqual({
      outcome: "allow",
      grantId: "g1",
    });
    expect(decide(grant({ capability: "remember", mode: "ask" }), plain, {})).toEqual({
      outcome: "ask",
      grantId: "g1",
    });
  });

  it("constraints only narrow: an input outside the grant's limits is denied, even in ask mode", () => {
    const limited = grant({ constraints: { hosts: ["acme.example"] } });
    expect(decide(limited, read, { url: "https://acme.example/a" }).outcome).toBe("allow");
    expect(decide(limited, read, { url: "https://www.acme.example/a" }).outcome).toBe("allow");
    expect(decide(limited, read, { url: "https://evil-acme.example/a" }).outcome).toBe("deny");
    expect(decide({ ...limited, mode: "ask" }, read, { url: "https://other.org" }).outcome).toBe(
      "deny",
    );
    expect(decide(grant(), read, { url: "https://anywhere.org" }).outcome).toBe("allow");
  });

  it("a grant whose stored limits no longer fit the capability denies instead of widening", () => {
    expect(
      decide(grant({ constraints: { hosts: "acme.example" } }), read, { url: "https://x" }),
    ).toMatchObject({
      outcome: "deny",
    });
  });

  it("host matching rejects malformed URLs and look-alike domains", () => {
    expect(allowedHost("not a url", ["acme.example"])).toBe(false);
    expect(allowedHost("https://acme.example.evil.com", ["acme.example"])).toBe(false);
    expect(allowedHost("https://ACME.example", [".acme.example"])).toBe(true);
  });
});
