/**
 * Each business's browser on the trusted Mac host: the owner's Google Chrome, visible, on its
 * own profile (a site signed in once stays signed in for that business only). The host starts
 * it on first use and drives it with Browser Use's browser-harness-js `Session` (a typed wrapper
 * for every DevTools Protocol method) over Chrome's DevTools pipe (./pipe.ts): Chrome listens on
 * no port, so no other process on the Mac can reach a business's browser. Employees'
 * scripts reach it one command at a time through `/browser/call`, which keeps them to web pages
 * and to files in the business's own folder; downloads land there too. The window closes when
 * the host stops; the profile, and its sign-ins, stay.
 *
 * Chrome is not wrapped in the business's Seatbelt policy (../../workspace/host/seatbelt.ts):
 * its profile lives in the server's data, which that policy hides, and Chrome's own sandbox,
 * which guards against the pages it visits, cannot start inside another Seatbelt profile.
 */
import { spawn, type ChildProcess } from "node:child_process";
import { existsSync, mkdirSync, realpathSync } from "node:fs";
import type { Readable, Writable } from "node:stream";
import { basename, dirname, isAbsolute, join } from "node:path";
import type { Session } from "browser-harness-js/sdk/session.ts";
import { HostRefusal, hostId, type HostRoutes } from "../../protocol/host.ts";
import { pipeSession } from "./pipe.ts";
import type {
  BrowserEvent,
  BrowserStatus,
  OwnerInput,
  PageState,
  Screenshot,
  Tab,
} from "../contract.ts";

interface BrowsersHostOptions {
  /** Profiles live in `<data>/browser/<business>`. */
  data: string;
  /** Business folders, `<work>/<business>`: uploads come from there, downloads go there. */
  work: string;
  chrome?: string;
  /** Tests run Chrome without a window. */
  headless?: boolean;
}

interface Running {
  chrome: ChildProcess;
  session: Session;
  /** The tab the live view shows and scripts start on, and its DevTools session. */
  tab: { id: string; session: string } | null;
  driver: string | null;
  /** The latest events, oldest first, for scripts that wait on one. */
  events: BrowserEvent[];
  seq: number;
  wake: Set<() => void>;
}

const keptEvents = 500;
const commandMs = 60_000;

/** The only pages an employee may open: the web, or a blank tab. */
const webUrl = (url: unknown): url is string =>
  typeof url === "string" && (/^https?:\/\//i.test(url) || url === "about:blank");

/**
 * Commands that would reach past the business's web pages: installing extensions or apps,
 * handing the protocol to a page, or sending to a session around the checks below.
 */
const refused =
  /^(Extensions|PWA)\.|^Target\.(exposeDevToolsProtocol|sendMessageToTarget|setRemoteLocations|attachToBrowserTarget)$/;

/** Keys the owner presses through the live view, as DevTools key events. */
const keys: Record<string, { code: string; keyCode: number; text?: string }> = {
  Enter: { code: "Enter", keyCode: 13, text: "\r" },
  Tab: { code: "Tab", keyCode: 9 },
  Escape: { code: "Escape", keyCode: 27 },
  Backspace: { code: "Backspace", keyCode: 8 },
  Delete: { code: "Delete", keyCode: 46 },
  ArrowUp: { code: "ArrowUp", keyCode: 38 },
  ArrowDown: { code: "ArrowDown", keyCode: 40 },
  ArrowLeft: { code: "ArrowLeft", keyCode: 37 },
  ArrowRight: { code: "ArrowRight", keyCode: 39 },
  PageUp: { code: "PageUp", keyCode: 33 },
  PageDown: { code: "PageDown", keyCode: 34 },
  Home: { code: "Home", keyCode: 36 },
  End: { code: "End", keyCode: 35 },
  Space: { code: "Space", keyCode: 32, text: " " },
};

export function browsersHost(options: BrowsersHostOptions): HostRoutes {
  const chrome = options.chrome ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  const open = new Map<string, Running>();
  const starting = new Map<string, Promise<Running>>();

  /** The business's Chrome on its own profile, started on first use. */
  async function launch(business: string): Promise<Running> {
    if (!existsSync(chrome))
      throw new HostRefusal(503, "Google Chrome is not installed on this Mac");
    const profile = join(options.data, "browser", business);
    mkdirSync(profile, { recursive: true });
    const child = spawn(
      chrome,
      [
        `--user-data-dir=${profile}`,
        "--remote-debugging-pipe",
        "--no-first-run",
        "--no-default-browser-check",
        ...(options.headless ? ["--headless=new", "--window-size=1280,800"] : []),
        "about:blank",
      ],
      // fd 3 carries commands to Chrome, fd 4 its replies and events.
      { stdio: ["ignore", "ignore", "ignore", "pipe", "pipe"] },
    );
    const exited = new Promise<"exited">((resolve) => {
      child.once("exit", () => resolve("exited"));
      child.once("error", () => resolve("exited"));
    });
    const session = pipeSession(child.stdio[3] as Writable, child.stdio[4] as Readable);
    const connected = await Promise.race([
      timed(session.domains.Browser.getVersion(), 30_000).then(
        () => "connected" as const,
        () => "failed" as const,
      ),
      exited,
    ]);
    if (connected !== "connected") {
      child.kill();
      session.close();
      throw new HostRefusal(
        503,
        connected === "exited"
          ? "Chrome closed as it started: is this business's browser already open?"
          : "Chrome did not answer on its DevTools pipe",
      );
    }
    const running: Running = {
      chrome: child,
      session,
      tab: null,
      driver: null,
      events: [],
      seq: 0,
      wake: new Set(),
    };
    session.onEvent((method, params) => {
      running.events.push({ seq: ++running.seq, method, params });
      if (running.events.length > keptEvents) running.events.shift();
      for (const wake of running.wake) wake();
    });
    void exited.then(() => {
      if (open.get(business) === running) open.delete(business);
      session.close();
    });
    const downloads = join(options.work, business, "Downloads");
    mkdirSync(downloads, { recursive: true });
    await session.domains.Browser.setDownloadBehavior({
      behavior: "allow",
      downloadPath: downloads,
      eventsEnabled: true,
    });
    return running;
  }

  async function runningFor(business: string) {
    const existing = open.get(business);
    if (existing) return existing;
    const pending = starting.get(business) ?? launch(business);
    starting.set(business, pending);
    try {
      const running = await pending;
      open.set(business, running);
      return running;
    } finally {
      starting.delete(business);
    }
  }

  /** The web tabs, in no particular order (the protocol does not keep the tab strip's). */
  async function webTabs(running: Running) {
    const { targetInfos } = await running.session.domains.Target.getTargets({});
    return targetInfos.filter((target) => target.type === "page" && webUrl(target.url));
  }

  /** Makes `id` the current tab, shown in the window, and routes scripts to it. */
  async function focus(running: Running, id: string) {
    const session = await running.session.use(id);
    running.tab = { id, session };
    await running.session.domains.Page.enable({});
    await running.session.domains.Target.activateTarget({ targetId: id });
  }

  /** The current tab, or another (a new blank one) when it was closed. */
  async function current(running: Running) {
    const tabs = await webTabs(running);
    if (running.tab && tabs.some((tab) => tab.targetId === running.tab!.id)) return running.tab;
    const next =
      tabs.at(-1)?.targetId ??
      (await running.session.domains.Target.createTarget({ url: "about:blank" })).targetId;
    await focus(running, next);
    return running.tab!;
  }

  /** One command on the current tab whatever a script routes to (frames, other tabs). */
  async function onTab<T>(running: Running, send: () => Promise<T>) {
    const tab = await current(running);
    const routed = running.session.getActiveSession();
    // The harness reads the session when the command is sent, synchronously.
    running.session.setActiveSession(tab.session);
    const sent = send();
    running.session.setActiveSession(routed);
    return sent;
  }

  async function pageState(running: Running): Promise<PageState> {
    const tab = await current(running);
    const { targetInfo } = await running.session.domains.Target.getTargetInfo({
      targetId: tab.id,
    });
    return { url: targetInfo.url, title: targetInfo.title };
  }

  async function tabs(running: Running): Promise<Tab[]> {
    const tab = await current(running);
    return (await webTabs(running)).map((target) => ({
      id: target.targetId,
      url: target.url,
      title: target.title,
      current: target.targetId === tab.id,
    }));
  }

  /** A path in the business's own folder (resolved through links), or a refusal. */
  function ownPath(business: string, path: unknown) {
    if (typeof path !== "string" || !isAbsolute(path))
      throw new HostRefusal(400, "Give absolute paths in the business's folder");
    const folder = realpathSync(join(options.work, business));
    const resolve = (at: string): string =>
      existsSync(at) ? realpathSync(at) : join(resolve(dirname(at)), basename(at));
    const resolved = resolve(path);
    if (resolved !== folder && !resolved.startsWith(`${folder}/`))
      throw new HostRefusal(403, "Only files in the business's own folder");
    return path;
  }

  /** What a script may send: web pages, and files in the business's own folder. */
  async function screen(running: Running, business: string, method: string, params: unknown) {
    if (refused.test(method)) throw new HostRefusal(403, `${method} isn't available`);
    const given = (params ?? {}) as Record<string, unknown>;
    if (
      ["Page.navigate", "Target.createTarget", "Network.loadNetworkResource"].includes(method) &&
      !webUrl(given.url)
    )
      throw new HostRefusal(403, "Open http or https pages only");
    if (method === "Target.attachToTarget") await routable(running, given.targetId);
    const files =
      method === "DOM.setFileInputFiles"
        ? given.files
        : method === "Input.dispatchDragEvent"
          ? (given.data as { files?: unknown } | undefined)?.files
          : undefined;
    if (files !== undefined) {
      if (!Array.isArray(files)) throw new HostRefusal(400, "Give files as a list of paths");
      for (const file of files) ownPath(business, file);
    }
    if (method.endsWith(".setDownloadBehavior") && given.downloadPath !== undefined)
      ownPath(business, given.downloadPath);
  }

  /** A tab or frame showing a web page, which a script may route its commands to. */
  async function routable(running: Running, targetId: unknown) {
    if (typeof targetId !== "string") throw new HostRefusal(400, "Name the tab or frame");
    const { targetInfos } = await running.session.domains.Target.getTargets({});
    const target = targetInfos.find((info) => info.targetId === targetId);
    if (!target || !["page", "iframe"].includes(target.type) || !webUrl(target.url))
      throw new HostRefusal(404, "No such tab or frame");
    return target;
  }

  /** Events after `after` (from now when null), waiting up to `waitMs` for a first one. */
  async function events(
    running: Running,
    after: number | null,
    method: string | null,
    waitMs: number,
  ) {
    const from = after ?? running.seq;
    const deadline = Date.now() + Math.min(Math.max(waitMs, 0), 10_000);
    const pick = () =>
      running.events.filter((event) => event.seq > from && (!method || event.method === method));
    let found = pick();
    while (!found.length && Date.now() < deadline) {
      await new Promise<void>((resolve) => {
        const done = () => {
          clearTimeout(timer);
          running.wake.delete(done);
          resolve();
        };
        const timer = setTimeout(done, deadline - Date.now());
        running.wake.add(done);
      });
      found = pick();
    }
    const listed = found.slice(0, 100);
    return {
      events: listed,
      cursor: listed.length < found.length ? listed.at(-1)!.seq : Math.max(from, running.seq),
    };
  }

  const timed = <T>(sent: Promise<T>, ms = commandMs) =>
    Promise.race([
      sent,
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error("The browser didn't answer in time")), ms),
      ),
    ]);

  /** Runs an action, turning the browser's own refusals into one the caller reads. */
  async function act<T>(run: () => Promise<T>) {
    try {
      return await run();
    } catch (error) {
      if (error instanceof HostRefusal) throw error;
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
    // Never file://: the business's browser must not read the Mac's folders.
    if (!webUrl(value)) throw new HostRefusal(400, "Open an http or https URL");
    return value;
  };

  function drive(running: Running, driver: unknown) {
    if (typeof driver === "string") running.driver = driver.slice(0, 200);
  }

  /** The visible part of the current tab as a JPEG in CSS pixels. */
  async function screenshot(running: Running): Promise<Screenshot> {
    const metrics = await onTab(running, () => running.session.domains.Page.getLayoutMetrics());
    const view = metrics.cssVisualViewport;
    const scale = view.clientWidth / metrics.visualViewport.clientWidth || 1;
    const { data } = await timed(
      onTab(running, () =>
        running.session.domains.Page.captureScreenshot({
          format: "jpeg",
          quality: 60,
          clip: {
            x: view.pageX,
            y: view.pageY,
            width: view.clientWidth,
            height: view.clientHeight,
            scale,
          },
        }),
      ),
      15_000,
    );
    return {
      jpeg: data,
      width: Math.round(view.clientWidth),
      height: Math.round(view.clientHeight),
    };
  }

  async function ownerInput(running: Running, action: OwnerInput) {
    const input = running.session.domains.Input;
    if (action?.kind === "click") {
      const at = {
        x: Number(action.x),
        y: Number(action.y),
        button: "left" as const,
        clickCount: 1,
      };
      await onTab(running, () => input.dispatchMouseEvent({ type: "mousePressed", ...at }));
      await onTab(running, () => input.dispatchMouseEvent({ type: "mouseReleased", ...at }));
    } else if (action?.kind === "type") {
      const typed = text(action.text, "text");
      await onTab(running, () => input.insertText({ text: typed }));
    } else if (action?.kind === "key") {
      const name = text(action.key, "key", 40);
      const key =
        keys[name] ?? ([...name].length === 1 ? { code: "", keyCode: 0, text: name } : undefined);
      if (!key) throw new HostRefusal(400, `Unknown key ${name}`);
      const event = {
        key: name,
        code: key.code,
        windowsVirtualKeyCode: key.keyCode,
        ...(key.text ? { text: key.text } : {}),
      };
      await onTab(running, () => input.dispatchKeyEvent({ type: "keyDown", ...event }));
      await onTab(running, () => input.dispatchKeyEvent({ type: "keyUp", ...event }));
    } else if (action?.kind === "open") {
      const url = web(action.url);
      await onTab(running, () => running.session.domains.Page.navigate({ url }));
    } else throw new HostRefusal(400, "Click, type, press a key or open a URL");
    return pageState(running);
  }

  return {
    prefix: "/browser/",
    async handle(path, input) {
      const business = input.business;
      if (typeof business !== "string" || !hostId.test(business))
        throw new HostRefusal(400, "Missing or invalid business");
      if (path === "/browser/status") {
        const running = open.get(business);
        if (!running)
          return { open: false, url: null, title: null, driver: null } satisfies BrowserStatus;
        return act(async () => ({
          open: true,
          ...(await pageState(running)),
          driver: running.driver,
        })) satisfies Promise<BrowserStatus>;
      }
      const running = await runningFor(business);
      switch (path) {
        case "/browser/call":
          return act(async () => {
            const method = text(input.method, "method", 100);
            if (!/^[A-Z][A-Za-z]*\.[a-z][A-Za-z]*$/.test(method))
              throw new HostRefusal(400, "Name a DevTools Protocol method, like Page.navigate");
            drive(running, input.driver);
            await screen(running, business, method, input.params);
            await current(running);
            const cursor = running.seq;
            const result = await timed(running.session._call(method, input.params ?? {}));
            return { result: result ?? null, cursor };
          });
        case "/browser/events":
          return events(
            running,
            typeof input.after === "number" ? input.after : null,
            typeof input.method === "string" ? input.method : null,
            Number(input.waitMs) || 0,
          );
        case "/browser/tabs":
          return act(async () => {
            drive(running, input.driver);
            if (input.action === "switch") {
              const target = await routable(running, input.tab);
              if (target.type === "page") await focus(running, target.targetId);
              // A frame: the tab stays; scripts' commands go to the frame.
              else await running.session.use(target.targetId);
            } else if (input.action === "open") {
              const { targetId } = await running.session.domains.Target.createTarget({
                url: web(input.url),
              });
              await focus(running, targetId);
            } else if (input.action === "close") {
              const target = await routable(running, input.tab);
              await running.session.domains.Target.closeTarget({ targetId: target.targetId });
              // Chrome answers before the tab is gone from its list.
              for (let tries = 0; tries < 40; tries++) {
                if (!(await webTabs(running)).some((tab) => tab.targetId === target.targetId))
                  break;
                await new Promise((resolve) => setTimeout(resolve, 50));
              }
            } else if (input.action !== "list")
              throw new HostRefusal(400, "List, switch, open or close a tab");
            return tabs(running);
          });
        case "/browser/screenshot":
          return act(() => screenshot(running));
        case "/browser/input":
          return act(() => ownerInput(running, input.action as OwnerInput));
        default:
          throw new HostRefusal(404, "Not found");
      }
    },
    async close() {
      await Promise.all(
        [...open.values()].map(
          (running) =>
            new Promise<void>((resolve) => {
              running.session.close();
              if (running.chrome.exitCode !== null) return resolve();
              running.chrome.once("exit", () => resolve());
              running.chrome.kill();
            }),
        ),
      );
      open.clear();
    },
  };
}
