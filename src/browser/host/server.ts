/**
 * Each business's browser on the trusted Mac host: the owner's Chrome, visible, with its own
 * profile (so a site signed in once stays signed in for that business only), launched and
 * driven by Playwright over a pipe. (Attaching to a running Chrome over its debugging socket
 * hangs under Bun, which runs the host; the pipe doesn't.) The window closes when the host
 * stops; the profile, and its sign-ins, stay.
 */
import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { chromium, type BrowserContext, type Locator, type Page } from "playwright-core";
import { HostRefusal, hostId, type HostRoutes } from "../../protocol/host.ts";
import type { BrowserStatus, OwnerInput, PageState, Target } from "../contract.ts";

interface BrowsersHostOptions {
  /** Profiles live in `<data>/browser/<business>`. */
  data: string;
  chrome?: string;
  /** Tests run Chrome without a window. */
  headless?: boolean;
}

interface Open {
  context: BrowserContext;
  page: Page;
  driver: string | null;
}

const snapshotChars = 20_000;
const actionMs = 15_000;

export function browsersHost(options: BrowsersHostOptions): HostRoutes {
  const chrome = options.chrome ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  const open = new Map<string, Open>();
  const starting = new Map<string, Promise<Open>>();

  /** The business's Chrome on its own profile, started on first use. */
  async function launch(business: string): Promise<Open> {
    if (!existsSync(chrome))
      throw new HostRefusal(503, "Google Chrome is not installed on this Mac");
    const profile = join(options.data, "browser", business);
    mkdirSync(profile, { recursive: true });
    const context = await chromium.launchPersistentContext(profile, {
      executablePath: chrome,
      headless: options.headless === true,
      // A real window sizes the page; windowless tests get a fixed one.
      viewport: options.headless ? { width: 1280, height: 800 } : null,
      // The owner's own Chrome, not an automation banner: sites the owner signs in to see a
      // normal browser.
      ignoreDefaultArgs: ["--enable-automation"],
      args: [
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-blink-features=AutomationControlled",
      ],
      timeout: 30_000,
    });
    const page = context.pages()[0] ?? (await context.newPage());
    const session: Open = { context, page, driver: null };
    context.on("close", () => {
      if (open.get(business) === session) open.delete(business);
    });
    // The page employees act on follows the tab most recently opened (a link with a new tab).
    context.on("page", (next) => {
      session.page = next;
    });
    return session;
  }

  async function sessionFor(business: string) {
    const existing = open.get(business);
    if (existing && !existing.page.isClosed()) return existing;
    if (existing) {
      existing.page = existing.context.pages().at(-1) ?? (await existing.context.newPage());
      return existing;
    }
    const pending = starting.get(business) ?? launch(business);
    starting.set(business, pending);
    try {
      const session = await pending;
      open.set(business, session);
      return session;
    } finally {
      starting.delete(business);
    }
  }

  const state = async (page: Page): Promise<PageState> => ({
    url: page.url(),
    title: await page.title(),
  });

  function locate(page: Page, target: Target): Locator {
    if (target.selector) return page.locator(target.selector).first();
    if (target.role)
      return page
        .getByRole(
          target.role as Parameters<Page["getByRole"]>[0],
          target.name ? { name: target.name } : {},
        )
        .first();
    if (target.text) return page.getByText(target.text).first();
    throw new HostRefusal(400, "Name the element by role and name, text, or selector");
  }

  async function act<T>(business: string, driver: unknown, run: (page: Page) => Promise<T>) {
    const session = await sessionFor(business);
    if (typeof driver === "string") session.driver = driver.slice(0, 200);
    try {
      return await run(session.page);
    } catch (error) {
      if (error instanceof HostRefusal) throw error;
      // Playwright's message says what it couldn't do; the employee reads the page again.
      throw new HostRefusal(
        409,
        error instanceof Error ? error.message.split("\n")[0]! : "The page refused that",
      );
    }
  }

  const text = (value: unknown, name: string, max = 4000) => {
    if (typeof value !== "string" || value.length > max)
      throw new HostRefusal(400, `Give the ${name}`);
    return value;
  };
  const web = (value: unknown) => {
    const url = text(value, "URL", 2000);
    if (!/^https?:\/\//.test(url)) throw new HostRefusal(400, "Open an http or https URL");
    return url;
  };

  return {
    prefix: "/browser/",
    async handle(path, input) {
      const business = input.business;
      if (typeof business !== "string" || !hostId.test(business))
        throw new HostRefusal(400, "Missing or invalid business");
      switch (path) {
        case "/browser/open":
          return act(business, input.driver, async (page) => {
            await page.goto(web(input.url), { waitUntil: "domcontentloaded", timeout: 30_000 });
            return state(page);
          });
        case "/browser/read":
          return act(business, input.driver, async (page) => {
            const snapshot = await page.locator("body").ariaSnapshot({ timeout: actionMs });
            return {
              ...(await state(page)),
              snapshot:
                snapshot.length > snapshotChars
                  ? `${snapshot.slice(0, snapshotChars)}\n… (cut; scroll or open a narrower page)`
                  : snapshot,
            };
          });
        case "/browser/click":
          return act(business, input.driver, async (page) => {
            await locate(page, input.target as Target).click({ timeout: actionMs });
            await page.waitForLoadState("domcontentloaded").catch(() => undefined);
            return state(page);
          });
        case "/browser/type":
          return act(business, input.driver, async (page) => {
            const field = locate(page, input.target as Target);
            await field.fill(text(input.text, "text"), { timeout: actionMs });
            if (input.submit === true) await field.press("Enter");
            await page.waitForLoadState("domcontentloaded").catch(() => undefined);
            return state(page);
          });
        case "/browser/press":
          return act(business, input.driver, async (page) => {
            await page.keyboard.press(text(input.key, "key", 40));
            return state(page);
          });
        case "/browser/status": {
          const session = open.get(business);
          if (!session)
            return { open: false, url: null, title: null, driver: null } satisfies BrowserStatus;
          return {
            open: true,
            ...(await state(session.page)),
            driver: session.driver,
          } satisfies BrowserStatus;
        }
        case "/browser/screenshot":
          return act(business, undefined, async (page) => {
            const image = await page.screenshot({ type: "jpeg", quality: 60, scale: "css" });
            const size =
              page.viewportSize() ??
              (await page.evaluate(() => ({ width: innerWidth, height: innerHeight })));
            return {
              jpeg: Buffer.from(image).toString("base64"),
              width: size.width,
              height: size.height,
            };
          });
        case "/browser/input": {
          const action = input.action as OwnerInput;
          return act(business, undefined, async (page) => {
            if (action?.kind === "click")
              await page.mouse.click(Number(action.x), Number(action.y));
            else if (action?.kind === "type") await page.keyboard.type(text(action.text, "text"));
            else if (action?.kind === "key") await page.keyboard.press(text(action.key, "key", 40));
            else if (action?.kind === "open")
              await page.goto(web(action.url), { waitUntil: "domcontentloaded", timeout: 30_000 });
            else throw new HostRefusal(400, "Click, type, press a key or open a URL");
            return state(page);
          });
        }
        default:
          throw new HostRefusal(404, "Not found");
      }
    },
    async close() {
      await Promise.all(
        [...open.values()].map((session) => session.context.close().catch(() => undefined)),
      );
      open.clear();
    },
  };
}
