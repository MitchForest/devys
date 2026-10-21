import { Effect, Schema } from "effect";
import { capability, CapabilityError, Invocation } from "../protocol/capability.ts";
import type { Browser, PageState } from "./contract.ts";

const Url = Schema.String.check(Schema.isPattern(/^https?:\/\/\S{1,2000}$/));
const Target = Schema.Struct({
  role: Schema.optional(Schema.String.check(Schema.isMaxLength(40))),
  name: Schema.optional(Schema.String.check(Schema.isMaxLength(300))),
  text: Schema.optional(Schema.String.check(Schema.isMaxLength(300))),
  selector: Schema.optional(Schema.String.check(Schema.isMaxLength(300))),
});
const Page = Schema.Struct({ url: Schema.String, title: Schema.String });

/** The work an action serves, so the owner sees the browser on that work item. */
const driving = Effect.map(Invocation, (invocation) => ({
  businessId: invocation.businessId,
  driver: invocation.commitmentId ?? invocation.conversation ?? `direct:${invocation.employeeId}`,
}));

const page = <T>(run: () => Promise<T>) =>
  Effect.tryPromise({
    try: run,
    catch: (error) =>
      new CapabilityError({
        code: "unavailable",
        message: error instanceof Error ? error.message : "The browser couldn't do that",
      }),
  });

/**
 * The business's own browser (Chrome with its profile, signed in by the owner), driven like
 * Playwright MCP's core tools: open a URL, read the page's roles and names, act on an element.
 * Acting on a work item someone has taken over is fenced like every other capability.
 */
export function browserCapabilities(browserFor: (businessId: string) => Browser) {
  return [
    capability({
      name: "browserOpen",
      description:
        "Open a URL in the business's browser (its own Chrome, where the owner is signed in to the business's sites). Then read the page with browserRead.",
      effect: "read",
      replay: "idempotent",
      input: Schema.Struct({ url: Url }),
      output: Page,
      execute: ({ url }) =>
        Effect.gen(function* () {
          const { businessId, driver } = yield* driving;
          return yield* page<PageState>(() => browserFor(businessId).open(url, driver));
        }),
    }),
    capability({
      name: "browserRead",
      description:
        "Read the page open in the business's browser: its URL, title and accessibility tree (each element's role and name, which browserClick and browserType take).",
      effect: "read",
      replay: "read",
      input: Schema.Struct({}),
      output: Schema.Struct({ url: Schema.String, title: Schema.String, snapshot: Schema.String }),
      execute: () =>
        Effect.gen(function* () {
          const { businessId, driver } = yield* driving;
          return yield* page(() => browserFor(businessId).read(driver));
        }),
    }),
    capability({
      name: "browserClick",
      description:
        "Click an element in the business's browser, named by its role and name from browserRead (preferred), its visible text, or a CSS selector. Clicking can submit, buy or send: only do what the work allows.",
      effect: "external",
      replay: "reconcile",
      input: Schema.Struct({ target: Target }),
      output: Page,
      execute: ({ target }) =>
        Effect.gen(function* () {
          const { businessId, driver } = yield* driving;
          return yield* page<PageState>(() => browserFor(businessId).click(target, driver));
        }),
    }),
    capability({
      name: "browserType",
      description:
        "Fill a field in the business's browser (named like browserClick) with text, optionally pressing Enter to submit. Never type passwords or card numbers: the owner signs in through the live view.",
      effect: "external",
      replay: "reconcile",
      input: Schema.Struct({
        target: Target,
        text: Schema.String.check(Schema.isMaxLength(4000)),
        submit: Schema.optional(Schema.Boolean),
      }),
      output: Page,
      execute: ({ target, text, submit }) =>
        Effect.gen(function* () {
          const { businessId, driver } = yield* driving;
          return yield* page<PageState>(() =>
            browserFor(businessId).type(target, text, submit === true, driver),
          );
        }),
    }),
    capability({
      name: "browserPress",
      description:
        "Press a key in the business's browser (Enter, Escape, Tab, PageDown, ArrowDown, …).",
      effect: "external",
      replay: "reconcile",
      input: Schema.Struct({ key: Schema.String.check(Schema.isPattern(/^[A-Za-z0-9+]{1,40}$/)) }),
      output: Page,
      execute: ({ key }) =>
        Effect.gen(function* () {
          const { businessId, driver } = yield* driving;
          return yield* page<PageState>(() => browserFor(businessId).press(key, driver));
        }),
    }),
  ];
}
