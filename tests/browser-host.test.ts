import { existsSync, mkdtempSync, realpathSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, expect, it } from "vitest";
import { hostBrowser } from "../src/browser/host-client.ts";
import { browsersHost } from "../src/browser/host/server.ts";
import { startHost } from "../src/workspace/host/server.ts";

const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const token = "test-token";

// A tiny site: a search form, a result page, and a cookie that says who is signed in.
const site = createServer((request, response) => {
  const url = new URL(request.url ?? "/", "http://site");
  const cookie = request.headers.cookie ?? "";
  response.setHeader("content-type", "text/html");
  if (url.pathname === "/sign-in") {
    response.setHeader("set-cookie", "user=owner; Path=/");
    return response.end("<h1>Signed in</h1>");
  }
  if (url.pathname === "/account")
    return response.end(
      `<h1>${cookie.includes("user=owner") ? "Hello, owner" : "Please sign in"}</h1>`,
    );
  if (url.pathname === "/result")
    return response.end(`<h1>Results for ${url.searchParams.get("q")}</h1>`);
  response.end(
    `<title>Acme search</title><form action="/result"><label>Query <input name="q"></label><button>Search</button></form><a href="/account">Account</a>`,
  );
});
await new Promise<void>((resolve) => site.listen(0, "127.0.0.1", resolve));
const base = `http://127.0.0.1:${(site.address() as { port: number }).port}`;

const data = realpathSync(mkdtempSync(join(tmpdir(), "devys-browser-")));
const host = await startHost({
  token,
  data,
  work: join(data, "work"),
  port: 0,
  routes: [browsersHost({ data, headless: true })],
});
afterAll(async () => {
  await host.close();
  site.close();
});
const browser = (business: string) =>
  hostBrowser({ url: `http://127.0.0.1:${host.port}`, token }, business);

it.skipIf(!existsSync(chrome))(
  "an employee opens, reads and acts on a page; the owner watches and clicks; businesses don't share sign-ins",
  async () => {
    const acme = browser("acme");
    expect(await acme.open(base, "work-1")).toEqual({ url: `${base}/`, title: "Acme search" });
    const page = await acme.read("work-1");
    expect(page.snapshot).toContain('textbox "Query"');
    expect(page.snapshot).toContain('button "Search"');
    const result = await acme.type(
      { role: "textbox", name: "Query" },
      "tip calculators",
      true,
      "work-1",
    );
    expect(result.url).toContain("/result?q=tip+calculators");
    expect((await acme.read("work-1")).snapshot).toContain("Results for tip calculators");
    expect(await acme.status()).toMatchObject({ open: true, driver: "work-1" });
    await expect(acme.click({ role: "button", name: "Nowhere" }, "work-1")).rejects.toThrow();

    // The owner signs in through the live view; the employee finds the session there later.
    const shot = await acme.screenshot();
    expect(shot.jpeg.length).toBeGreaterThan(100);
    expect(shot.width).toBeGreaterThan(100);
    await acme.input({ kind: "open", url: `${base}/sign-in` });
    await acme.open(`${base}/account`, "work-1");
    expect((await acme.read("work-1")).snapshot).toContain("Hello, owner");

    // Another business has its own profile: not signed in.
    const globex = browser("globex");
    await globex.open(`${base}/account`, "work-2");
    expect((await globex.read("work-2")).snapshot).toContain("Please sign in");
  },
  60_000,
);
