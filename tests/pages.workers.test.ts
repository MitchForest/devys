import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { artifactCapabilities } from "../src/artifacts/capabilities.ts";
import { artifactText } from "../src/artifacts/service.ts";
import { browserCapabilities } from "../src/browser/capabilities.ts";
import type { Browser } from "../src/browser/contract.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { business } from "./fixtures/postgres.ts";

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
      .pipe(as(scope, { conversation: "space:launch" })),
  )) as { id: string };
  expect(cards).toEqual([
    {
      conversation: "space:launch",
      text: "Published a page: Signups by week",
      ref: `artifact:${published.id}`,
    },
  ]);
  const stored = await Effect.runPromise(artifactText(bindings, scope.businessId, published.id));
  expect(stored).toMatchObject({ filename: "Signups by week.html", content_type: "text/html" });
  // Refused pages are said plainly; nothing is stored.
  const refused = await Effect.runPromise(
    named("artifactPage")
      .execute({ title: "Bad", html: '<form action="https://x"></form>' })
      .pipe(as(scope), Effect.flip),
  );
  expect(refused).toMatchObject({ code: "invalid_input" });
  const edited = (await Effect.runPromise(
    named("artifactEdit")
      .execute({ page: published.id, find: "<p>12</p>", replace: "<p>14</p>" })
      .pipe(as(scope)),
  )) as { id: string };
  expect(edited.id).not.toBe(published.id);
  expect((await Effect.runPromise(artifactText(bindings, scope.businessId, edited.id)))?.text).toBe(
    "<h1>Signups</h1><p>14</p>",
  );
  const ambiguous = await Effect.runPromise(
    named("artifactEdit")
      .execute({ page: edited.id, find: "<", replace: "" })
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
      .pipe(as(scope, { commitmentId: "work-7" })),
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
