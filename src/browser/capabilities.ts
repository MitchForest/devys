import { DynamicWorkerExecutor } from "@cloudflare/codemode";
import { Effect, Exit, Schema } from "effect";
import { capability, CapabilityError, Image, Invocation } from "../protocol/capability.ts";
import { HostRefusal } from "../protocol/host.ts";
import { rpc } from "../protocol/rpc.ts";
import { SecretName, type Sealed } from "../vault/contract.ts";
import { type Browser, FillAt, FillField, Tab, type TabAction } from "./contract.ts";
import { scriptPrelude } from "./script.ts";

const Url = Schema.String.check(Schema.isPattern(/^https?:\/\/\S{1,2000}$/));
const TabId = Schema.String.check(Schema.isMaxLength(200));

/** The most of a script's result, as JSON, the employee reads back. */
const resultChars = 20_000;
const scriptMs = 120_000;

/** The work an action serves, so the owner sees the browser on that work item. */
const driving = Effect.map(Invocation, (invocation) => ({
  invocation,
  driver: invocation.workItemId ?? invocation.conversation ?? `direct:${invocation.employeeId}`,
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

/** A result the employee can read: JSON, cut to a readable size. */
function bounded(result: unknown) {
  if (result === undefined) return null;
  const json = JSON.stringify(result) ?? "null";
  return json.length > resultChars
    ? `${json.slice(0, resultChars)}… (cut: return less, such as the fields you need)`
    : (JSON.parse(json) as unknown);
}

/** What a fill needs from outside the browser, connected in wiring. */
export interface Filling {
  /** The business's secret or card by name, sealed for the host. */
  sealed(businessId: string, name: string): Promise<Sealed>;
  /**
   * Spends a signed spend approval of this work item on one fill (approved, signed, unexpired,
   * unused; it is then used): the counterparty it names. Refuses (with why) otherwise.
   */
  claim(
    businessId: string,
    workItemId: string,
    approval: string,
  ): Promise<{ counterparty: string }>;
  /** Gives a claimed approval back: the fill failed before anything was submitted. */
  unclaim(businessId: string, approval: string): Promise<void>;
  /** Records a card fill on the work item as evidence. */
  record(businessId: string, workItemId: string, note: string, source: string): Promise<void>;
}

/**
 * The business's own browser (Chrome with its profile, signed in by the owner), driven like
 * browser-harness-js: scripts over the DevTools Protocol, screenshots, tabs. A script runs in an
 * isolate with no network; each of its commands goes to the business's browser only while the
 * employee still holds the work (Take over stops it mid-script).
 */
export function browserCapabilities(
  browserFor: (businessId: string) => Browser,
  loader: WorkerLoader,
  filling: Filling,
) {
  return [
    capability({
      name: "browserScript",
      description:
        "Run a JavaScript snippet against the business's own browser (Chrome on the business's profile, where the owner is signed in to its sites). `session.<Domain>.<method>(params)` sends any Chrome DevTools Protocol command to the current tab (Page.navigate, Runtime.evaluate, Input.dispatchMouseEvent, Input.insertText, DOM.setFileInputFiles, …); `session.use(targetId)` routes to another tab or a cross-origin frame; `session.waitFor(event, predicate?, ms?)` waits for an event after your last command; `listPageTargets()` lists tabs. Await each call; the last expression (or `return`) is the result. Read the using-the-browser skill first. Clicking and typing can submit, buy or send: only do what the work allows; never type passwords or card numbers (browserFill does).",
      effect: "external",
      replay: "reconcile",
      input: Schema.Struct({ script: Schema.String.check(Schema.isMaxLength(32_000)) }),
      output: Schema.Struct({
        result: Schema.Unknown,
        error: Schema.optional(Schema.String),
        logs: Schema.Array(Schema.String),
      }),
      execute: ({ script }) =>
        Effect.gen(function* () {
          const { invocation, driver } = yield* driving;
          const browser = browserFor(invocation.businessId);
          /** Every command first checks the work is still the employee's. */
          const held = async () => {
            if (Exit.isFailure(await Effect.runPromiseExit(invocation.assertActive())))
              throw new Error("This work is no longer yours to act on (taken over or stopped)");
          };
          const ran = yield* page(() =>
            new DynamicWorkerExecutor({ loader, timeout: scriptMs, globalOutbound: null }).execute(
              script,
              [
                {
                  name: "browser",
                  prelude: scriptPrelude,
                  fns: {
                    call: async (args: unknown) => {
                      await held();
                      const { method, params } = args as { method: string; params: unknown };
                      return browser.call(String(method), params, driver);
                    },
                    events: async (args: unknown) => {
                      const { after, method, waitMs } = args as {
                        after: number | null;
                        method: string | null;
                        waitMs: number;
                      };
                      return browser.events(after ?? null, method ?? null, Number(waitMs) || 0);
                    },
                    tabs: async (args: unknown) => {
                      await held();
                      return browser.tabs(args as TabAction, driver);
                    },
                  },
                },
              ],
            ),
          );
          yield* invocation.assertActive();
          return {
            result: bounded(ran.result),
            ...(ran.error ? { error: ran.error } : {}),
            logs: (ran.logs ?? []).slice(-50).map((line) => line.slice(0, 500)),
          };
        }),
    }),
    capability({
      name: "browserScreenshot",
      description:
        "See the current tab of the business's browser: a picture of the visible page in CSS pixels, so a point in it is the x and y Input.dispatchMouseEvent takes in browserScript.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({}),
      output: Schema.Struct({
        url: Schema.String,
        title: Schema.String,
        width: Schema.Number,
        height: Schema.Number,
        image: Image,
      }),
      execute: () =>
        Effect.gen(function* () {
          const { invocation, driver } = yield* driving;
          const browser = browserFor(invocation.businessId);
          const tabs = yield* page(() => browser.tabs({ action: "list" }, driver));
          const shot = yield* page(() => browser.screenshot("employee"));
          const tab = tabs.find((each) => each.current);
          return {
            url: tab?.url ?? "",
            title: tab?.title ?? "",
            width: shot.width,
            height: shot.height,
            image: { mimeType: "image/jpeg" as const, data: shot.jpeg },
          };
        }),
    }),
    capability({
      name: "browserTabs",
      description:
        "List the business's browser tabs, or switch to, open (a URL) or close one. The current tab is the one browserScript and browserScreenshot act on and the owner watches.",
      effect: "change",
      replay: "reconcile",
      input: Schema.Union([
        Schema.Struct({ action: Schema.Literal("list") }),
        Schema.Struct({ action: Schema.Literal("switch"), tab: TabId }),
        Schema.Struct({ action: Schema.Literal("open"), url: Url }),
        Schema.Struct({ action: Schema.Literal("close"), tab: TabId }),
      ]),
      output: Schema.Struct({ tabs: Schema.Array(Tab) }),
      execute: (action) =>
        Effect.gen(function* () {
          const { invocation, driver } = yield* driving;
          return {
            tabs: yield* page(() => browserFor(invocation.businessId).tabs(action, driver)),
          };
        }),
    }),
    capability({
      name: "browserFill",
      description:
        "Fill a secret into the business's browser without ever seeing it: a password (part value) or a card (parts number, expiry MM/YY, month, year, cvc, name, postal), each field found by CSS selector or by clicking its x,y; a field inside another site's payment frame names its target (from listPageTargets/browserTabs). submit clicks a button afterwards. A card needs approval: the request id of the owner's signed spend approval in this work item's thread (askOwner approve with the amount and the merchant's site as counterparty, e.g. namecheap.com); the page must be on that site, and one approval is one fill. After a fill, scripts and screenshots wait until the page moves on (at most two minutes); a failed fill clears what it filled.",
      effect: "external",
      replay: "reconcile",
      input: Schema.Struct({
        secret: SecretName,
        fields: Schema.Array(FillField).check(Schema.isMinLength(1), Schema.isMaxLength(10)),
        submit: Schema.optional(FillAt),
        approval: Schema.optional(Schema.String.check(Schema.isPattern(/^[A-Za-z0-9-]{1,64}$/))),
      }),
      output: Schema.Struct({
        filled: Schema.Number,
        submitted: Schema.Boolean,
        origin: Schema.String,
      }),
      execute: ({ secret, fields, submit, approval }) =>
        Effect.gen(function* () {
          const { invocation, driver } = yield* driving;
          const { businessId, workItemId } = invocation;
          const sealed = yield* rpc(() => filling.sealed(businessId, secret));
          let claimed: { counterparty: string } | undefined;
          if (sealed.kind === "spend") {
            if (!workItemId)
              return yield* new CapabilityError({
                code: "conflict",
                message:
                  "A card is filled in a work item's thread, against the owner's signed spend approval there.",
              });
            if (!approval)
              return yield* new CapabilityError({
                code: "forbidden",
                message: `${secret} is a card: ask with askOwner {kind: "approve", action, counterparty: the merchant's site, amount} in this thread, and once it is approved pass its request id as approval.`,
              });
            // Still the employee's work (not taken over) before the approval is spent on it.
            yield* invocation.assertActive();
            claimed = yield* rpc(() => filling.claim(businessId, workItemId, approval));
          }
          yield* invocation.assertActive();
          const filled = yield* Effect.tryPromise({
            try: () =>
              browserFor(businessId).fill(
                {
                  secret: sealed,
                  merchant: claimed?.counterparty ?? null,
                  fields,
                  ...(submit ? { submit } : {}),
                },
                driver,
              ),
            catch: (error) => error,
          }).pipe(
            Effect.catch((error) =>
              Effect.gen(function* () {
                // The host refused before submitting: nothing was sent, so the approval stands.
                // Anything else (the host gone mid-fill) leaves it spent: inspect the page.
                if (claimed && approval && error instanceof HostRefusal)
                  yield* rpc(() => filling.unclaim(businessId, approval));
                return yield* rpc(() => Promise.reject(error));
              }),
            ),
          );
          if (claimed && workItemId)
            yield* rpc(() =>
              filling.record(
                businessId,
                workItemId,
                `Card ${secret} ending ${filled.last4} filled at ${filled.origin}${filled.submitted ? " and submitted" : ""}, against spend approval ${approval}.`,
                `fill:${approval}`,
              ),
            );
          return { filled: fields.length, submitted: filled.submitted, origin: filled.origin };
        }),
    }),
  ];
}
