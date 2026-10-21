import { Schema } from "effect";
import { expect, it } from "vitest";
import { parseRef, ref, Ref, refKinds } from "../src/protocol/ref.ts";

it("a ref round-trips every kind, its id percent-encoded", () => {
  for (const [app, kinds] of Object.entries(refKinds))
    for (const kind of kinds) {
      const made = ref(app as never, kind as never, "a b/ü?#%");
      expect(made).toBe(`devys:${app}/${kind}/a%20b%2F%C3%BC%3F%23%25`);
      expect(parseRef(made)).toEqual({ app, kind, id: "a b/ü?#%" });
    }
  const file = ref("documents", "file", "/Users/o/Devys/b1/plan (v2).md");
  expect(file).toBe("devys:documents/file/%2FUsers%2Fo%2FDevys%2Fb1%2Fplan%20(v2).md");
  expect(parseRef(file)?.id).toBe("/Users/o/Devys/b1/plan (v2).md");
});

it("parseRef is strict: only the closed kinds, a non-empty id in the encoding ref gives it", () => {
  for (const value of [
    "artifact:123",
    "123",
    "devys:documents/artifact/",
    "devys:documents/page/1",
    "devys:code/item/1",
    "devys:mail/thread/1",
    "devys:documents/file//Users/o",
    "devys:documents/file/a%2",
    "devys:documents/file/a%2fb",
    "devys:documents/file/a b",
    "devys:Documents/artifact/1",
    "devys:documents/artifact/1/2",
    " devys:work/item/1",
    42,
    undefined,
  ])
    expect(parseRef(value), String(value)).toBeUndefined();
});

it("the Ref schema accepts only refs", () => {
  const decode = Schema.decodeUnknownSync(Ref);
  expect(decode("devys:work/item/w1")).toBe("devys:work/item/w1");
  expect(() => decode("artifact:1")).toThrow();
  expect(() => decode("devys:work/session/1")).toThrow();
});
