import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { apiRoute } from "../src/app/http.ts";
import { parseLook } from "../src/identity/looks.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { business, sql } from "./fixtures/postgres.ts";

const bindings = env as unknown as Env;

async function signedIn(person: string) {
  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [await sha256(token), person],
  );
  return async (path: string, init: RequestInit & { type?: string } = {}) =>
    (await apiRoute(
      new Request(`https://devys.test${path}`, {
        ...init,
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": init.type ?? "application/json",
        },
      }),
      bindings,
    )) ?? new Response(null, { status: 404 });
}

it("accepts only known Faces and single emoji; photos come only from an upload", () => {
  expect(parseLook({ kind: "face", palette: "teal", shape: "hexagon", seed: 3 })).toEqual({
    kind: "face",
    palette: "teal",
    shape: "hexagon",
    seed: 3,
  });
  expect(parseLook({ kind: "emoji", emoji: "🧑‍💻", tint: "green" })).toMatchObject({ emoji: "🧑‍💻" });
  expect(parseLook(null)).toBeNull();
  expect(parseLook({ kind: "face", palette: "neon", shape: "hexagon", seed: 3 })).toBeUndefined();
  expect(parseLook({ kind: "emoji", emoji: "🙂🙂", tint: "green" })).toBeUndefined();
  expect(parseLook({ kind: "photo", version: "x" })).toBeUndefined();
});

it("looks are stored on the server, so every client shows the same business and employee", async () => {
  const { person, scope } = await business();
  const as = await signedIn(person);
  const base = `/api/businesses/${scope.businessId}`;
  const employee = `${base}/employees/${scope.employeeId}`;
  const face = { kind: "face", palette: "teal", shape: "hexagon", seed: 3 };
  expect(
    (await as(`${employee}/look`, { method: "POST", body: JSON.stringify({ look: face }) })).status,
  ).toBe(200);
  const emoji = { kind: "emoji", emoji: "🦉", tint: "purple" };
  expect(
    (await as(`${base}/look`, { method: "POST", body: JSON.stringify({ look: emoji }) })).status,
  ).toBe(200);
  const detail = (await (await as(base)).json()) as {
    business: { look: unknown };
    employees: { id: string; look: unknown }[];
  };
  expect(detail.business.look).toEqual(emoji);
  expect(detail.employees.find((e) => e.id === scope.employeeId)?.look).toEqual(face);
  const me = (await (await as("/api/me")).json()) as {
    businesses: { id: string; look: unknown }[];
  };
  expect(me.businesses.find((b) => b.id === scope.businessId)?.look).toEqual(emoji);

  const upload = await as(`${employee}/look/photo`, {
    method: "PUT",
    type: "image/png",
    body: new Uint8Array([137, 80, 78, 71]),
  });
  const { look } = (await upload.json()) as { look: { kind: string; version: string } };
  expect(look.kind).toBe("photo");
  const photo = await as(`${employee}/look/photo`);
  expect(new Uint8Array(await photo.arrayBuffer())).toEqual(new Uint8Array([137, 80, 78, 71]));
  expect(
    (await as(`${employee}/look/photo`, { method: "PUT", type: "image/svg+xml", body: "<svg/>" }))
      .status,
  ).toBe(415);

  // Resetting restores the default and deletes the stored photo.
  expect(
    (await as(`${employee}/look`, { method: "POST", body: JSON.stringify({ look: null }) })).status,
  ).toBe(200);
  expect((await as(`${employee}/look/photo`)).status).toBe(404);
  expect(
    (
      await sql.row<{ look: unknown }>("SELECT look FROM employees WHERE id = $1", [
        scope.employeeId,
      ])
    )?.look,
  ).toBeNull();
  expect(
    (await as(`${base}/look`, { method: "POST", body: JSON.stringify({ look: { kind: "face" } }) }))
      .status,
  ).toBe(400);
});
