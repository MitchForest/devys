import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { artifactCapabilities } from "../src/apps/documents/capabilities.ts";
import { artifactText, listArtifacts } from "../src/apps/documents/service.ts";
import { browserCapabilities } from "../src/browser/capabilities.ts";
import type { Browser } from "../src/browser/contract.ts";
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
  const ambiguous = await Effect.runPromise(
    named("artifactEdit")
      .execute({ page: edited.ref, find: "<", replace: "" })
      .pipe(as(scope), Effect.flip),
  );
  expect(ambiguous).toMatchObject({ code: "invalid_input" });
});

it("browser actions name the work they serve, so the owner sees the browser there", async () => {
  const calls: { method: string; driver: string }[] = [];
  const browser = {
    open: async (_url: string, driver: string) => (
      calls.push({ method: "open", driver }),
      { url: "https://a.example/", title: "A" }
    ),
    read: async (driver: string) => (
      calls.push({ method: "read", driver }),
      { url: "", title: "", snapshot: '- heading "A"' }
    ),
  } as unknown as Browser;
  const named = (name: string) =>
    browserCapabilities(() => browser).find((item) => item.name === name)!;
  const scope = { businessId: "b", employeeId: "e" };
  await Effect.runPromise(
    named("browserOpen")
      .execute({ url: "https://a.example/" })
      .pipe(as(scope, { workItemId: "work-7" })),
  );
  await Effect.runPromise(
    named("browserRead")
      .execute({})
      .pipe(as(scope, { conversation: "direct:e" })),
  );
  expect(calls).toEqual([
    { method: "open", driver: "work-7" },
    { method: "read", driver: "direct:e" },
  ]);
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
  expect(of(first)).toMatchObject({ title: "Launch plan", version: 1, versions: 2 });
  expect(of(second)).toMatchObject({ title: "Launch plan", version: 2, versions: 2 });
  expect(of(other)).toMatchObject({ title: "notes.md", version: 1, versions: 1 });
});
