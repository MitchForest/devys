import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { artifactCapabilities } from "../src/apps/documents/capabilities.ts";
import { artifactText, listArtifacts } from "../src/apps/documents/service.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { parseRef } from "../src/protocol/ref.ts";
import { business, sql } from "./fixtures/postgres.ts";

const bindings = env as unknown as Env;
const as = (
  scope: { businessId: string; employeeId: string },
  extra: Record<string, string> = {},
) =>
  Effect.provideService(Invocation, {
    ...scope,
    operationId: crypto.randomUUID(),
    ...extra,
    authorize: () => Effect.void,
    assertActive: () => Effect.void,
  });

it("an employee publishes a page, sees it announced where it is answering, and edits it", async () => {
  const { scope } = await business("Pages");
  const cards: { conversation?: string; text: string; ref: string }[] = [];
  const named = (name: string) =>
    artifactCapabilities(
      bindings,
      () => ({}) as never,
      async (invocation, card) => {
        cards.push({ conversation: invocation.conversation, text: card.text, ref: card.ref });
      },
      (businessId, id) => `https://devys.test/api/businesses/${businessId}/artifacts/${id}`,
    ).find((item) => item.name === name)!;
  const published = (await Effect.runPromise(
    named("artifactPage")
      .execute({ title: "Signups by week", html: "<h1>Signups</h1><p>12</p>" })
      .pipe(as(scope, { conversation: "project:launch" })),
  )) as { ref: string };
  // The page it created is returned as its ref (only), the same one the card carries.
  expect(Object.keys(published)).toEqual(["ref"]);
  const publishedId = parseRef(published.ref)?.id ?? "";
  expect(parseRef(published.ref)).toMatchObject({ app: "documents", kind: "artifact" });
  expect(cards).toEqual([
    {
      conversation: "project:launch",
      text: "Published a page: Signups by week",
      ref: published.ref,
    },
  ]);
  const stored = await Effect.runPromise(artifactText(bindings, scope.businessId, publishedId));
  expect(stored).toMatchObject({ filename: "Signups by week.html", content_type: "text/html" });
  // Refused pages are said plainly; nothing is stored.
  const refused = await Effect.runPromise(
    named("artifactPage")
      .execute({ title: "Bad", html: '<form action="https://x"></form>' })
      .pipe(as(scope), Effect.flip),
  );
  expect(refused).toMatchObject({ code: "invalid_input" });
  // A page is named by its ref; its bare id is refused.
  const bare = await Effect.runPromise(
    named("artifactEdit")
      .execute({ page: publishedId, find: "<p>12</p>", replace: "<p>14</p>" })
      .pipe(as(scope), Effect.flip),
  );
  expect(bare).toMatchObject({ code: "invalid_input" });
  const edited = (await Effect.runPromise(
    named("artifactEdit")
      .execute({ page: published.ref, find: "<p>12</p>", replace: "<p>14</p>" })
      .pipe(as(scope)),
  )) as { ref: string };
  expect(edited.ref).not.toBe(published.ref);
  const editedId = parseRef(edited.ref)?.id ?? "";
  expect((await Effect.runPromise(artifactText(bindings, scope.businessId, editedId)))?.text).toBe(
    "<h1>Signups</h1><p>14</p>",
  );
  // Reading either version says what it is and which version is the page now.
  const read = (artifact: string) =>
    Effect.runPromise(named("artifactRead").execute({ artifact }).pipe(as(scope)));
  expect(await read(published.ref)).toEqual({
    ref: published.ref,
    title: "Signups by week",
    version: 1,
    versions: 2,
    latest: edited.ref,
    contentType: "text/html",
    text: "<h1>Signups</h1><p>12</p>",
    truncated: false,
  });
  expect(await read(edited.ref)).toMatchObject({ version: 2, text: "<h1>Signups</h1><p>14</p>" });
  // Another business's artifact is not there to read.
  const elsewhere = await business("Elsewhere");
  expect(
    await Effect.runPromise(
      named("artifactRead")
        .execute({ artifact: published.ref })
        .pipe(as(elsewhere.scope), Effect.flip),
    ),
  ).toMatchObject({ code: "invalid_input" });
  const ambiguous = await Effect.runPromise(
    named("artifactEdit")
      .execute({ page: edited.ref, find: "<", replace: "" })
      .pipe(as(scope), Effect.flip),
  );
  expect(ambiguous).toMatchObject({ code: "invalid_input" });
});

it("artifacts carry their title and their version among pages of the same name", async () => {
  const { business: acme } = await business("Versions");
  const add = (filename: string, at: string) => {
    const id = crypto.randomUUID();
    return sql
      .run(
        `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length, created_at)
         VALUES ($1, $2, $1, $1, $3, 'text/html', 1, $4)`,
        [id, acme.id, filename, at],
      )
      .then(() => id);
  };
  const first = await add("Launch plan.html", "2026-10-01T00:00:00Z");
  const second = await add("Launch plan.html", "2026-10-02T00:00:00Z");
  const other = await add("notes.md", "2026-10-03T00:00:00Z");
  const listed = await Effect.runPromise(listArtifacts(bindings.HYPERDRIVE, acme.id));
  const of = (id: string) => listed.find((a) => a.id === id);
  expect(of(first)).toMatchObject({
    title: "Launch plan",
    version: 1,
    versions: 2,
    latest_id: second,
  });
  expect(of(second)).toMatchObject({
    title: "Launch plan",
    version: 2,
    versions: 2,
    latest_id: second,
  });
  expect(of(other)).toMatchObject({ title: "notes.md", version: 1, versions: 1, latest_id: other });
});

it("artifactRead refuses bytes that aren't text and bounds long text", async () => {
  const { scope } = await business("Reading");
  const capability = artifactCapabilities(
    bindings,
    () => ({}) as never,
    async () => {},
    () => "",
  ).find((item) => item.name === "artifactRead")!;
  const read = (artifact: string) =>
    Effect.runPromise(capability.execute({ artifact }).pipe(as(scope))) as Promise<{
      text: string;
      truncated: boolean;
    }>;
  const add = async (filename: string, type: string, bytes: Uint8Array) => {
    const id = crypto.randomUUID();
    const key = `${scope.businessId}/artifacts/${id}`;
    await bindings.FILES.put(key, bytes);
    await sql.run(
      `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length)
       VALUES ($1, $2, $1, $3, $4, $5, $6)`,
      [id, scope.businessId, key, filename, type, bytes.byteLength],
    );
    return `devys:documents/artifact/${id}`;
  };
  const image = await add("chart.png", "image/png", new Uint8Array([137, 80, 78, 71]));
  expect(
    await Effect.runPromise(capability.execute({ artifact: image }).pipe(as(scope), Effect.flip)),
  ).toMatchObject({ code: "invalid_input" });
  const long = await add("log.txt", "text/plain", new TextEncoder().encode("a".repeat(250_000)));
  const bounded = await read(long);
  expect(bounded.truncated).toBe(true);
  expect(bounded.text).toHaveLength(200_000);
});
