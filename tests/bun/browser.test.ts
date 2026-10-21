// The business's browser on a real host with real Chrome (windowless): employees' scripts as
// browserScript runs them, screenshots, tabs, the owner's input, and two businesses' profiles
// kept apart. Run by `bun test tests/bun`.
import { afterAll, expect, it, setDefaultTimeout } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Browser, TabAction } from "../../src/browser/contract.ts";
import { hostBrowser } from "../../src/browser/host-client.ts";
import { browsersHost } from "../../src/browser/host/server.ts";
import { scriptPrelude } from "../../src/browser/script.ts";
import { startHost } from "../../src/workspace/host/server.ts";

setDefaultTimeout(90_000);
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const token = "test-token";

// A tiny site: a button and a field at known places, an upload, frames, and a sign-in cookie.
const site = createServer((request, response) => {
  const url = new URL(request.url ?? "/", "http://site");
  const cookie = request.headers.cookie ?? "";
  response.setHeader("content-type", "text/html");
  if (url.pathname === "/sign-in") {
    response.setHeader("set-cookie", "user=owner; Path=/");
    return response.end("<title>Signed in</title><h1>Signed in</h1>");
  }
  if (url.pathname === "/account")
    return response.end(
      `<title>Account</title><h1>${cookie.includes("user=owner") ? "Hello, owner" : "Please sign in"}</h1>`,
    );
  if (url.pathname === "/upload")
    return response.end(
      `<title>Upload</title><input type="file" onchange="document.title = this.files[0].name">`,
    );
  if (url.pathname === "/inner") return response.end(`<title>Inner</title><h1>Inside</h1>`);
  if (url.pathname === "/frames")
    return response.end(
      `<title>Frames</title><iframe src="/inner"></iframe><iframe src="${url.searchParams.get("other")}/inner"></iframe>`,
    );
  response.end(
    `<title>Acme</title><body style="margin:0">
      <button style="position:absolute;left:100px;top:100px;width:120px;height:40px" onclick="document.title = 'clicked'">Go</button>
      <input id="q" style="position:absolute;left:100px;top:200px;width:200px;height:30px">
    </body>`,
  );
});
await new Promise<void>((resolve) => site.listen(0, "127.0.0.1", resolve));
const port = (site.address() as { port: number }).port;
const base = `http://127.0.0.1:${port}`;
// Another site, so its frame is cross-origin (its own target).
const other = `http://localhost:${port}`;

const root = realpathSync(mkdtempSync(join(tmpdir(), "devys-browser-")));
const work = join(root, "work");
const host = await startHost({
  token,
  data: join(root, "data"),
  work,
  port: 0,
  routes: [browsersHost({ data: join(root, "data"), work, headless: true })],
});
afterAll(async () => {
  await host.close();
  site.close();
});
const browser = (business: string) =>
  hostBrowser({ url: `http://127.0.0.1:${host.port}`, token }, business);

/** A snippet as browserScript runs it: the same prelude, the same calls, without the isolate. */
function script(target: Browser, code: string): Promise<unknown> {
  const calls = {
    call: ({ method, params }: { method: string; params: unknown }) =>
      target.call(method, params, "work-1"),
    events: ({ after, method, waitMs }: { after: number | null; method: string; waitMs: number }) =>
      target.events(after, method, waitMs),
    tabs: (action: TabAction) => target.tabs(action, "work-1"),
  };
  const run = new (Object.getPrototypeOf(async () => {}).constructor)(
    "browser",
    `${scriptPrelude}\n${code}`,
  ) as (browser: unknown) => Promise<unknown>;
  return run(calls);
}

const title = `return (await session.Runtime.evaluate({ expression: "document.title", returnByValue: true })).result.value;`;
const open = (url: string) => `
  const loaded = session.waitFor("Page.loadEventFired");
  await session.Page.navigate({ url: ${JSON.stringify(url)} });
  await loaded;`;
const click = (x: number, y: number) => `
  for (const type of ["mousePressed", "mouseReleased"])
    await session.Input.dispatchMouseEvent({ type, x: ${x}, y: ${y}, button: "left", clickCount: 1 });`;

it.skipIf(!existsSync(chrome))(
  "an employee's scripts navigate, click by coordinates, type, upload, reach frames and tabs, and see the page",
  async () => {
    const acme = browser("acme");
    expect(await script(acme, `${open(base)} ${title}`)).toBe("Acme");
    expect(await acme.status()).toMatchObject({ open: true, url: `${base}/`, driver: "work-1" });

    // A click and typing by coordinates, as read from a screenshot.
    expect(await script(acme, `${click(160, 120)} ${title}`)).toBe("clicked");
    expect(
      await script(
        acme,
        `${click(200, 215)}
        await session.Input.insertText({ text: "tip calculators" });
        return (await session.Runtime.evaluate({ expression: "document.querySelector('#q').value", returnByValue: true })).result.value;`,
      ),
    ).toBe("tip calculators");

    // The screenshot is CSS pixels of the visible page.
    const shot = await acme.screenshot();
    expect(shot.jpeg.length).toBeGreaterThan(100);
    expect(shot).toMatchObject({ width: 1280 });

    // A file from the business's folder; one from elsewhere is refused.
    mkdirSync(join(work, "acme"), { recursive: true });
    writeFileSync(join(work, "acme", "invoice.txt"), "an invoice");
    const upload = (path: string) => `${open(`${base}/upload`)}
      const { root } = await session.DOM.getDocument({ depth: -1 });
      const { nodeId } = await session.DOM.querySelector({ nodeId: root.nodeId, selector: "input" });
      await session.DOM.setFileInputFiles({ nodeId, files: [${JSON.stringify(path)}] });
      ${title}`;
    expect(await script(acme, upload(join(work, "acme", "invoice.txt")))).toBe("invoice.txt");
    mkdirSync(join(work, "globex"), { recursive: true });
    writeFileSync(join(work, "globex", "secret.txt"), "not Acme's");
    await expect(script(acme, upload(join(work, "globex", "secret.txt")))).rejects.toThrow(
      /business's own folder/,
    );
    // Only web pages open.
    await expect(
      script(acme, `await session.Page.navigate({ url: "file:///etc/hosts" })`),
    ).rejects.toThrow(/http or https/);

    // A same-origin frame through the page; a cross-origin frame by routing to its target.
    expect(
      await script(
        acme,
        `${open(`${base}/frames?other=${encodeURIComponent(other)}`)}
        return (await session.Runtime.evaluate({ expression: "document.querySelector('iframe').contentDocument.title", returnByValue: true })).result.value;`,
      ),
    ).toBe("Inner");
    expect(
      await script(
        acme,
        `const { targetInfos } = await session.Target.getTargets({});
        const frame = targetInfos.find((t) => t.type === "iframe" && t.url.startsWith(${JSON.stringify(other)}));
        await session.use(frame.targetId);
        const inside = (await session.Runtime.evaluate({ expression: "document.querySelector('h1').textContent", returnByValue: true })).result.value;
        await session.use((await listPageTargets()).find((t) => t.current).targetId);
        return inside;`,
      ),
    ).toBe("Inside");

    // A second tab: opened, current, listed; closing it returns to the first.
    const tabs = await acme.tabs({ action: "open", url: `${base}/inner` }, "work-1");
    expect(tabs).toHaveLength(2);
    const second = tabs.find((tab) => tab.current)!;
    expect(
      await script(
        acme,
        `await session.waitFor("Page.loadEventFired", undefined, 2000).catch(() => null); ${title}`,
      ),
    ).toBe("Inner");
    const left = await acme.tabs({ action: "close", tab: second.id }, "work-1");
    expect(left).toHaveLength(1);
    expect(left[0]).toMatchObject({ current: true, title: "Frames" });
  },
);

it.skipIf(!existsSync(chrome))(
  "the owner clicks, types and opens pages through the live view; businesses don't share sign-ins",
  async () => {
    const acme = browser("acme");
    await script(acme, open(base));
    await acme.input({ kind: "click", x: 200, y: 215 });
    await acme.input({ kind: "type", text: "by the owner" });
    expect(
      await script(
        acme,
        `return (await session.Runtime.evaluate({ expression: "document.querySelector('#q').value", returnByValue: true })).result.value;`,
      ),
    ).toBe("by the owner");
    expect(await acme.input({ kind: "click", x: 160, y: 120 })).toMatchObject({ title: "clicked" });
    await expect(acme.input({ kind: "open", url: "file:///etc/hosts" })).rejects.toThrow();

    // The owner signs in through the live view; the employee finds the session there later.
    await acme.input({ kind: "open", url: `${base}/sign-in` });
    expect(await script(acme, `${open(`${base}/account`)} ${title}`)).toBe("Account");
    expect(
      await script(
        acme,
        `return (await session.Runtime.evaluate({ expression: "document.querySelector('h1').textContent", returnByValue: true })).result.value;`,
      ),
    ).toBe("Hello, owner");

    // Another business has its own Chrome and profile: not signed in.
    const globex = browser("globex");
    await script(globex, open(`${base}/account`));
    expect(
      await script(
        globex,
        `return (await session.Runtime.evaluate({ expression: "document.querySelector('h1').textContent", returnByValue: true })).result.value;`,
      ),
    ).toBe("Please sign in");
    expect(await browser("initech").status()).toMatchObject({ open: false });
  },
);

it.skipIf(!existsSync(chrome))(
  "a business's Chrome is driven over a pipe and listens on no DevTools port",
  async () => {
    const acme = browser("acme");
    expect(await script(acme, `${open(base)} ${title}`)).toBe("Acme");
    const profile = join(root, "data", "browser", "acme");
    expect(existsSync(join(profile, "DevToolsActivePort"))).toBe(false);
    // Every process of that Chrome (browser, GPU, renderers) carries its profile directory.
    const pids = spawnSync("pgrep", ["-f", `user-data-dir=${profile}`], { encoding: "utf8" })
      .stdout.trim()
      .split("\n")
      .filter(Boolean);
    expect(pids.length).toBeGreaterThan(0);
    const listening = spawnSync(
      "lsof",
      ["-nP", "-a", "-iTCP", "-sTCP:LISTEN", "-p", pids.join(",")],
      { encoding: "utf8" },
    ).stdout.trim();
    expect(listening).toBe("");
  },
);
