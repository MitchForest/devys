/**
 * The browser component (.docs/COMPONENTS.md#browser): each business has its own browser,
 * signed in once by the owner, that employees drive with scripts over the Chrome DevTools
 * Protocol and the owner watches and takes over.
 */
import { Schema } from "effect";
import type { Sealed } from "../vault/contract.ts";

/** Where the browser is now. */
export const PageState = Schema.Struct({ url: Schema.String, title: Schema.String });
export type PageState = typeof PageState.Type;

/** The business's browser at a glance: whether it is open, where, and which work drives it. */
export const BrowserStatus = Schema.Struct({
  open: Schema.Boolean,
  url: Schema.NullOr(Schema.String),
  title: Schema.NullOr(Schema.String),
  /** The work item (or conversation) the last employee action served. */
  driver: Schema.NullOr(Schema.String),
});
export type BrowserStatus = typeof BrowserStatus.Type;

/** A JPEG of the visible page, base64, in CSS pixels (so clicks map 1:1). */
export const Screenshot = Schema.Struct({
  jpeg: Schema.String,
  width: Schema.Number,
  height: Schema.Number,
});
export type Screenshot = typeof Screenshot.Type;

/** The owner acting on the page directly: input goes to it and is not recorded. */
export const OwnerInput = Schema.Union([
  Schema.Struct({ kind: Schema.Literal("click"), x: Schema.Finite, y: Schema.Finite }),
  Schema.Struct({ kind: Schema.Literal("type"), text: Schema.String }),
  Schema.Struct({ kind: Schema.Literal("key"), key: Schema.String }),
  Schema.Struct({ kind: Schema.Literal("open"), url: Schema.String }),
]);
export type OwnerInput = typeof OwnerInput.Type;

/** A tab: `current` is the one scripts, screenshots and the live view act on. */
export const Tab = Schema.Struct({
  id: Schema.String,
  url: Schema.String,
  title: Schema.String,
  current: Schema.Boolean,
});
export type Tab = typeof Tab.Type;

export type TabAction =
  | { action: "list" }
  | { action: "switch"; tab: string }
  | { action: "open"; url: string }
  | { action: "close"; tab: string };

/**
 * Which part of a secret goes in a field: a card's number, expiry (`MM/YY`), month (`MM`), year
 * (`YYYY`, or `YY` where the field takes two characters), security code, name or postal code; or a
 * plain secret's whole value (a password).
 */
export const FillPart = Schema.Literals([
  "number",
  "expiry",
  "month",
  "year",
  "cvc",
  "name",
  "postal",
  "value",
]);
const Target = Schema.optionalKey(Schema.String.check(Schema.isMaxLength(200)));
const Selector = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(500));
/** Where to click: a CSS selector in the page (or frame), or a point in the tab's CSS pixels. */
export const FillAt = Schema.Union([
  Schema.Struct({ selector: Selector }),
  Schema.Struct({ x: Schema.Finite, y: Schema.Finite }),
]);
export type FillAt = typeof FillAt.Type;
/**
 * One field to fill: found by selector, or focused by clicking a point; `target` is the frame
 * (another site's payment frame) it is in, as `browserTabs`/`listPageTargets` name it.
 */
export const FillField = Schema.Union([
  Schema.Struct({ target: Target, selector: Selector, part: FillPart }),
  Schema.Struct({ target: Target, x: Schema.Finite, y: Schema.Finite, part: FillPart }),
]);
export type FillField = typeof FillField.Type;

/**
 * A one-time card from a card app (Ramp's agent card tool), asked for by the host only after the
 * page is found on the merchant's site: the app's address, its sealed sign-in, the tool and its
 * arguments (the signed approval's exact amount, currency and merchant).
 */
export interface CardSource {
  app: string;
  url: string;
  sealed: Sealed;
  tool: string;
  arguments: Record<string, unknown>;
}

/**
 * A fill for the host: a sealed secret or a card to issue, the merchant a card's approval names,
 * the fields.
 */
export type FillRequest = ({ secret: Sealed } | { issue: CardSource }) & {
  /** For a card: the signed spend approval's counterparty, which the page's site must match. */
  merchant: string | null;
  fields: readonly FillField[];
  submit?: FillAt;
};

/**
 * What a fill did: the top-level page's origin, whether it submitted, and a card's last four; for
 * an issued card, the app's reference for it and the app's sign-in when a refresh changed it.
 */
export interface Filled {
  origin: string;
  submitted: boolean;
  last4: string | null;
  reference?: string | null;
  sealed?: Sealed;
}

/** A DevTools Protocol event; `seq` orders every event the business's browser sent. */
export interface BrowserEvent {
  seq: number;
  method: string;
  params: unknown;
}

/**
 * One business's browser. `driver` names the work an employee's action serves. `cursor` is
 * the last event's `seq` before the command ran, so a script waits only for what followed.
 */
export interface Browser {
  /** One DevTools Protocol command, on the current tab unless it is browser-wide. */
  call(
    method: string,
    params: unknown,
    driver: string,
  ): Promise<{ result: unknown; cursor: number }>;
  /** Events after `after` (from now when null), waiting up to `waitMs` for the first. */
  events(
    after: number | null,
    method: string | null,
    waitMs: number,
  ): Promise<{ events: BrowserEvent[]; cursor: number }>;
  tabs(action: TabAction, driver: string): Promise<Tab[]>;
  status(): Promise<BrowserStatus>;
  /**
   * The current tab. While a filled card or password is on the page the employee's view is
   * paused; the owner's live view is not.
   */
  screenshot(viewer: "owner" | "employee"): Promise<Screenshot>;
  input(action: OwnerInput): Promise<PageState>;
  /**
   * The host fills a secret into the page's fields (a card only on the merchant's site), may
   * submit, and pauses employees' scripts, events and screenshots until the page moves on; the
   * filled fields are cleared on failure. The value never comes back.
   */
  fill(request: FillRequest, driver: string): Promise<Filled>;
}
