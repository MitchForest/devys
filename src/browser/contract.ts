/**
 * The browser component (.docs/COMPONENTS.md#browser): each business has its own browser,
 * signed in once by the owner, that employees drive with scripts over the Chrome DevTools
 * Protocol and the owner watches and takes over.
 */
import { Schema } from "effect";

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
  screenshot(): Promise<Screenshot>;
  input(action: OwnerInput): Promise<PageState>;
}
