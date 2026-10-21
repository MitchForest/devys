/**
 * The browser component (.docs/COMPONENTS.md#browser): each business has its own browser,
 * signed in once by the owner, that employees drive and the owner watches and takes over.
 */

/** What an element is, by its accessible role and name (from `read`), its text, or a CSS selector. */
export interface Target {
  role?: string;
  name?: string;
  text?: string;
  selector?: string;
}

/** Where the browser is now. */
export interface PageState {
  url: string;
  title: string;
}

/** The business's browser at a glance: whether it is open, where, and which work drives it. */
export interface BrowserStatus {
  open: boolean;
  url: string | null;
  title: string | null;
  /** The work item (or conversation) the last employee action served. */
  driver: string | null;
}

/** The owner acting on the page directly: input goes to it and is not recorded. */
export type OwnerInput =
  | { kind: "click"; x: number; y: number }
  | { kind: "type"; text: string }
  | { kind: "key"; key: string }
  | { kind: "open"; url: string };

/** One business's browser. `driver` names the work an employee's action serves. */
export interface Browser {
  open(url: string, driver: string): Promise<PageState>;
  /** The page's accessibility tree (roles and names to act on), cut to a readable size. */
  read(driver: string): Promise<PageState & { snapshot: string }>;
  click(target: Target, driver: string): Promise<PageState>;
  type(target: Target, text: string, submit: boolean, driver: string): Promise<PageState>;
  press(key: string, driver: string): Promise<PageState>;
  status(): Promise<BrowserStatus>;
  /** A JPEG of the visible page, base64, in CSS pixels (so clicks map 1:1). */
  screenshot(): Promise<{ jpeg: string; width: number; height: number }>;
  input(action: OwnerInput): Promise<PageState>;
}
