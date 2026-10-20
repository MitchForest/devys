import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { profilePhoto } from "../src/identity/profile.ts";

const bindings = env as unknown as Env;
const put = (owner: string, body: BodyInit, type = "image/png") =>
  profilePhoto(
    new Request("https://devys.test/api/profile/photo", {
      method: "PUT",
      body,
      headers: { "content-type": type },
    }),
    bindings,
    owner,
  );
const get = (owner: string) =>
  profilePhoto(new Request("https://devys.test/api/profile/photo"), bindings, owner);

it("stores a profile photo under its owner and serves it back only to that owner", async () => {
  const owner = crypto.randomUUID();
  const other = crypto.randomUUID();
  expect((await get(owner)).status).toBe(404);
  expect((await put(owner, new Uint8Array([137, 80, 78, 71]))).status).toBe(200);
  const photo = await get(owner);
  expect(photo.headers.get("content-type")).toBe("image/png");
  expect(new Uint8Array(await photo.arrayBuffer())).toEqual(new Uint8Array([137, 80, 78, 71]));
  expect((await get(other)).status).toBe(404);
});

it("rejects non-images and oversized photos, and removes on delete", async () => {
  const owner = crypto.randomUUID();
  expect((await put(owner, "<svg/>", "image/svg+xml")).status).toBe(415);
  expect((await put(owner, new Uint8Array(2_000_001))).status).toBe(413);
  await put(owner, new Uint8Array([1]));
  const removed = await profilePhoto(
    new Request("https://devys.test/api/profile/photo", { method: "DELETE" }),
    bindings,
    owner,
  );
  expect(removed.status).toBe(200);
  expect((await get(owner)).status).toBe(404);
});
