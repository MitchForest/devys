import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { browserCapabilities } from "../src/browser/capabilities.ts";
import type { Browser, BrowserEvent, TabAction } from "../src/browser/contract.ts";
import { CapabilityError, Invocation } from "../src/protocol/capability.ts";
import { toolContent } from "../src/runtime/codemode.ts";

const bindings = env as unknown as Env;
const scope = { businessId: "b", employeeId: "e" };

/** A browser that records what scripts send and answers like Chrome would. */
function recording() {
  const sent: { method: string; params: unknown; driver: string }[] = [];
  const switched: string[] = [];
  let seq = 0;
  const events: BrowserEvent[] = [];
  const browser: Browser = {
    async call(method, params, driver) {
      sent.push({ method, params, driver });
      const cursor = seq;
      if (method === "Page.navigate")
        events.push({ seq: ++seq, method: "Page.loadEventFired", params: { timestamp: 1 } });
      if (method === "Runtime.evaluate")
        return { result: { result: { value: "x".repeat(30_000) } }, cursor };
      return { result: { frameId: "f1" }, cursor };
    },
    async events(after, method) {
      const found = events.filter(
        (event) => event.seq > (after ?? seq) && (!method || event.method === method),
      );
      return { events: found, cursor: seq };
    },
    async tabs(action: TabAction) {
      if (action.action === "switch") switched.push(action.tab);
      return [{ id: "t1", url: "https://a.example/", title: "A", current: true }];
    },
    status: async () => ({ open: true, url: null, title: null, driver: null }),
    screenshot: async () => ({ jpeg: "AAAA", width: 1280, height: 800 }),
    input: async () => ({ url: "", title: "" }),
    fill: async () => ({ origin: "https://a.example", submitted: false, last4: null }),
  };
  return { browser, sent, switched };
}

/** Fills have their own tests (vault.workers.test.ts); these never fill. */
const noFilling = {
  sealed: () => Promise.reject(new Error("No fills here")),
  claim: () => Promise.reject(new Error("No fills here")),
  unclaim: async () => {},
  record: async () => {},
};
const named = (browser: Browser, name: string) =>
  browserCapabilities(() => browser, bindings.LOADER, noFilling).find(
    (item) => item.name === name,
  )!;

const as = (extra: Record<string, unknown> = {}) =>
  Effect.provideService(Invocation, {
    ...scope,
    operationId: crypto.randomUUID(),
    authorize: () => Effect.void,
    assertActive: () => Effect.void,
    ...extra,
  });

it("a script drives the browser through session, waits for events, routes to tabs, and is cut to size", async () => {
  const { browser, sent, switched } = recording();
  const result = await Effect.runPromise(
    named(browser, "browserScript")
      .execute({
        script: `
          const loaded = session.waitFor("Page.loadEventFired");
          await session.Page.navigate({ url: "https://a.example/" });
          const load = await loaded;
          const tabs = await listPageTargets();
          await session.use(tabs[0].targetId);
          console.log("loaded", load.timestamp);
          return { load, tabs: tabs.length };`,
      })
      .pipe(as({ workItemId: "work-7" })),
  );
  expect(result).toEqual({ result: { load: { timestamp: 1 }, tabs: 1 }, logs: ["loaded 1"] });
  expect(sent).toEqual([
    { method: "Page.navigate", params: { url: "https://a.example/" }, driver: "work-7" },
  ]);
  expect(switched).toEqual(["t1"]);

  // A large result is cut; an error in the script is the employee's to read.
  const large = (await Effect.runPromise(
    named(browser, "browserScript")
      .execute({ script: `(await session.Runtime.evaluate({ expression: "x" })).result.value` })
      .pipe(as({ conversation: "direct:e" })),
  )) as { result: string };
  expect(large.result.length).toBeLessThan(21_000);
  expect(large.result).toMatch(/cut/);
  expect(sent.at(-1)?.driver).toBe("direct:e");
  expect(
    await Effect.runPromise(
      named(browser, "browserScript")
        .execute({ script: `throw new Error("no such button")` })
        .pipe(as()),
    ),
  ).toMatchObject({ error: "no such button" });
});

it("taking over stops a running script at its next command", async () => {
  const { browser, sent } = recording();
  const failure = await Effect.runPromise(
    named(browser, "browserScript")
      .execute({
        script: `
          await session.Page.navigate({ url: "https://a.example/" });
          await session.Input.insertText({ text: "after the owner took over" });`,
      })
      .pipe(
        as({
          // The owner takes over once the script has sent its first command.
          assertActive: () =>
            sent.length
              ? Effect.fail(new CapabilityError({ code: "forbidden", message: "Taken over" }))
              : Effect.void,
        }),
        Effect.flip,
      ),
  );
  expect(failure).toMatchObject({ code: "forbidden" });
  expect(sent.map((call) => call.method)).toEqual(["Page.navigate"]);
});

it("a screenshot reaches the model as a picture", async () => {
  const { browser } = recording();
  const shot = await Effect.runPromise(named(browser, "browserScreenshot").execute({}).pipe(as()));
  expect(toolContent(shot)).toEqual([
    {
      type: "text",
      text: JSON.stringify({ url: "https://a.example/", title: "A", width: 1280, height: 800 }),
    },
    { type: "image", mimeType: "image/jpeg", data: "AAAA" },
  ]);
  expect(toolContent({ ok: true })).toEqual([{ type: "text", text: '{"ok":true}' }]);
});
