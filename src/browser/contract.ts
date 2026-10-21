/**
 * The browser component (.docs/COMPONENTS.md#browser): each business has its own browser,
 * signed in once by the owner, that employees drive and the owner watches and takes over.
 */
import { Schema } from "effect";

/** What an element is, by its accessible role and name (from `read`), its text, or a CSS selector. */
export interface Target {
  role?: string;
  name?: string;
  text?: string;
  selector?: string;
}

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

/** The owner acting on the page directly: input goes to it and is not recorded. */
export const OwnerInput = Schema.Union([
  Schema.Struct({ kind: Schema.Literal("click"), x: Schema.Finite, y: Schema.Finite }),
  Schema.Struct({ kind: Schema.Literal("type"), text: Schema.String }),
  Schema.Struct({ kind: Schema.Literal("key"), key: Schema.String }),
  Schema.Struct({ kind: Schema.Literal("open"), url: Schema.String }),
]);
export type OwnerInput = typeof OwnerInput.Type;

/** One business's browser. `driver` names the work an employee's action serves. */
export interface Browser {
  open(url: string, driver: string): Promise<PageState>;
  /** The page's accessibility tree (roles and names to act on), cut to a readable size. */
  read(driver: string): Promise<PageState & { snapshot: string }>;
  click(target: Target, driver: string): Promise<PageState>;
  type(target: Target, text: string, submit: boolean, driver: string): Promise<PageState>;
  press(key: string, driver: string): Promise<PageState>;
  status(): Promise<BrowserStatus>;
  screenshot(): Promise<typeof Screenshot.Type>;
  input(action: OwnerInput): Promise<PageState>;
}
