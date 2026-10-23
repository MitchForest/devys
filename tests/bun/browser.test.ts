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
import { hostKeyring, openFor } from "../../src/vault/host/server.ts";
import { cardIssuer } from "../../src/connections/host/card.ts";
import { mcpHost } from "../../src/connections/host/mcp.ts";
import type { Sealed } from "../../src/vault/contract.ts";
import { fakeMcp, issuedCard } from "../fixtures/mcp.ts";

setDefaultTimeout(90_000);
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const token = "test-token";

/** What the test checkout received when paid. */
const paid: Record<string, string>[] = [];
// A tiny site: a button and a field at known places, an upload, frames, a sign-in cookie and a
// checkout.
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
  // A checkout: name and postal code on the merchant's page, the card in another site's frame
  // (as a payment provider's). Pay collects the frame's fields by message and goes to /paid.
  if (url.pathname === "/checkout")
    return response.end(`<title>Checkout</title><body style="margin:0">
      <input id="name" style="position:absolute;left:20px;top:20px;width:200px;height:30px">
      <input id="postal" style="position:absolute;left:20px;top:70px;width:200px;height:30px">
      <iframe src="${url.searchParams.get("frame")}/card-frame" style="position:absolute;left:20px;top:120px;width:400px;height:200px;border:0"></iframe>
      <button id="pay" style="position:absolute;left:20px;top:360px;width:120px;height:40px"
        onclick="frames[0].postMessage('collect', '*')">Pay</button>
      <script>
        addEventListener("message", (event) => {
          const query = new URLSearchParams({ ...event.data, name: document.getElementById("name").value, postal: postal.value });
          location.href = "/paid?" + query;
        });
      </script></body>`);
  if (url.pathname === "/card-frame")
    return response.end(`<title>Card</title><body style="margin:0">
      <input id="number" style="position:absolute;left:0;top:0;width:200px;height:30px">
      <input id="exp" style="position:absolute;left:0;top:50px;width:80px;height:30px">
      <input id="cvc" style="position:absolute;left:0;top:100px;width:60px;height:30px">
      <script>
        addEventListener("message", () =>
          parent.postMessage({ number: number.value, exp: exp.value, cvc: cvc.value }, "*"));
      </script></body>`);
  if (url.pathname === "/paid") {
    paid.push(Object.fromEntries(url.searchParams));
    return response.end("<title>Paid</title><h1>Thank you</h1>");
  }
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
const keyring = await hostKeyring(join(root, "data"));
// A card app (Ramp's agent card tool, faked): an MCP server behind its own sign-in.
const cards = Bun.serve({ port: 0, fetch: (request) => cardApp.fetch(request) });
const cardApp = fakeMcp(`http://127.0.0.1:${cards.port}`);
const mcp = mcpHost({
  open: (business, sealed, kinds) => openFor(keyring, business, sealed, kinds),
  seal: (...args) => keyring.seal(...args),
});
const pauseMs = 3_000;
const host = await startHost({
  token,
  data: join(root, "data"),
  work,
  port: 0,
  routes: [
    browsersHost({
      data: join(root, "data"),
      work,
      headless: true,
      pauseMs,
      open: (business, sealed, kinds) => openFor(keyring, business, sealed, kinds),
      issueCard: cardIssuer(mcp.call),
    }),
  ],
});
afterAll(async () => {
  await host.close();
  site.close();
  cards.stop(true);
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
    expect(await acme.status()).toMatchObject({
      open: true,
      url: `${base}/`,
      driver: "work-1",
      driving: true,
    });

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

const card = {
  number: "4242424242424242",
  expiry: "04/31",
  cvc: "737",
  name: "Sam Owner",
  postal: "94107",
};
const value = (selector: string) =>
  `return (await session.Runtime.evaluate({ expression: "document.querySelector('${selector}').value", returnByValue: true })).result.value;`;

it.skipIf(!existsSync(chrome))(
  "the host fills a card into a checkout and its payment frame only on the approved merchant's site, hides the page meanwhile, and clears a failed fill",
  async () => {
    const acme = browser("acme");
    const sealedCard = await keyring.seal("acme", "RAMP_CARD", "spend", JSON.stringify(card));
    await script(acme, open(`${base}/checkout?frame=${encodeURIComponent(other)}`));
    const frame = (await script(
      acme,
      `const { targetInfos } = await session.Target.getTargets({});
      return targetInfos.find((t) => t.type === "iframe" && t.url.startsWith(${JSON.stringify(other)})).targetId;`,
    )) as string;
    const fields = [
      { selector: "#name", part: "name" as const },
      { selector: "#postal", part: "postal" as const },
      { target: frame, selector: "#number", part: "number" as const },
      { target: frame, x: 40, y: 185, part: "expiry" as const },
      { target: frame, selector: "#cvc", part: "cvc" as const },
    ];

    // Not on the site the approval names, and not without one: nothing is filled.
    await expect(
      acme.fill({ secret: sealedCard, merchant: "Namecheap (namecheap.com)", fields }, "work-1"),
    ).rejects.toThrow(/127\.0\.0\.1, not namecheap\.com/);
    await expect(
      acme.fill({ secret: sealedCard, merchant: null, fields }, "work-1"),
    ).rejects.toThrow(/doesn't name the merchant's site/);
    expect(await script(acme, value("#name"))).toBe("");
    // A card sealed for another business does not open here.
    const theirs = await keyring.seal("globex", "RAMP_CARD", "spend", JSON.stringify(card));
    await expect(
      acme.fill({ secret: theirs, merchant: "127.0.0.1", fields }, "work-1"),
    ).rejects.toThrow(/another business/);

    // A failed fill clears what it filled and hides nothing afterwards.
    await expect(
      acme.fill(
        {
          secret: sealedCard,
          merchant: "127.0.0.1",
          fields: [
            { selector: "#name", part: "name" },
            { selector: "#missing", part: "postal" },
          ],
        },
        "work-1",
      ),
    ).rejects.toThrow(/Nothing on the page matches #missing/);
    expect(await script(acme, value("#name"))).toBe("");

    // On the merchant's own page: every field, in the page and in the payment frame.
    expect(
      await acme.fill({ secret: sealedCard, merchant: "127.0.0.1", fields }, "work-1"),
    ).toEqual({
      origin: base,
      submitted: false,
      last4: "4242",
    });
    // Until the page moves on, employees see and read nothing of it; the owner still watches.
    await expect(acme.screenshot("employee")).rejects.toThrow(/hidden from you/);
    await expect(script(acme, value("#name"))).rejects.toThrow(/hidden from you/);
    await expect(acme.events(0, null, 0)).rejects.toThrow(/hidden from you/);
    await expect(acme.tabs({ action: "list" }, "work-1")).rejects.toThrow(/hidden from you/);
    expect((await acme.screenshot("owner")).jpeg.length).toBeGreaterThan(100);
    // The owner pays; the page moves on, and the employee sees it again.
    await acme.input({ kind: "click", x: 80, y: 380 });
    for (let tries = 0; tries < 100 && !paid.length; tries++)
      await new Promise((resolve) => setTimeout(resolve, 50));
    expect(paid.at(-1)).toEqual({
      number: card.number,
      exp: card.expiry,
      cvc: card.cvc,
      name: card.name,
      postal: card.postal,
    });
    let shot;
    for (let tries = 0; tries < 50 && !shot; tries++)
      shot = await acme
        .screenshot("employee")
        .catch(() => new Promise((resolve) => setTimeout(resolve, 50)).then(() => undefined));
    expect(shot).toBeDefined();
    // What happened while the card was on the page is not kept for a later script to read.
    const { events } = await acme.events(0, null, 0);
    expect(JSON.stringify(events)).not.toContain(card.number);

    // A fill that submits: the page moves on at once.
    await script(acme, open(`${base}/checkout?frame=${encodeURIComponent(other)}`));
    const again = (await script(
      acme,
      `const { targetInfos } = await session.Target.getTargets({});
      return targetInfos.find((t) => t.type === "iframe" && t.url.startsWith(${JSON.stringify(other)})).targetId;`,
    )) as string;
    expect(
      await acme.fill(
        {
          secret: sealedCard,
          merchant: "https://127.0.0.1/cart",
          fields: fields.map((field) => ("target" in field ? { ...field, target: again } : field)),
          submit: { selector: "#pay" },
        },
        "work-1",
      ),
    ).toMatchObject({ submitted: true });
    for (let tries = 0; tries < 100 && paid.length < 2; tries++)
      await new Promise((resolve) => setTimeout(resolve, 50));
    expect(paid).toHaveLength(2);
    // The pause lifts when Chrome reports the navigation, which can trail the payment itself.
    let visible = false;
    for (let tries = 0; tries < 100 && !visible; tries++)
      visible = await acme
        .screenshot("employee")
        .then(() => true)
        .catch(() => new Promise((resolve) => setTimeout(resolve, 50)).then(() => false));
    expect(visible).toBe(true);

    // A password needs no approval; left on a page that doesn't move on, it is cleared when the
    // pause ends.
    const password = await keyring.seal("acme", "SITE_PASSWORD", "secret", "correct horse");
    await script(acme, open(`${base}/checkout?frame=${encodeURIComponent(other)}`));
    await acme.fill(
      { secret: password, merchant: null, fields: [{ selector: "#name", part: "value" }] },
      "work-1",
    );
    await expect(script(acme, value("#name"))).rejects.toThrow(/hidden from you/);
    await new Promise((resolve) => setTimeout(resolve, pauseMs + 500));
    expect(await script(acme, value("#name"))).toBe("");
    // A plain secret has no card parts; a card is not a password.
    await expect(
      acme.fill(
        { secret: password, merchant: null, fields: [{ selector: "#name", part: "number" }] },
        "work-1",
      ),
    ).rejects.toThrow(/part value/);
  },
);

it.skipIf(!existsSync(chrome))(
  "a card from a card app: asked for only on the approved merchant's page, filled, never returned",
  async () => {
    // The owner connected the card app: its sign-in, sealed for the business.
    const redirect = "http://127.0.0.1:8787/api/apps/callback";
    const begun = (await mcp.routes.handle("/mcp/begin", {
      business: "acme",
      url: cardApp.url,
      redirect,
      state: "state-1",
    })) as { authorize: string; pending: unknown };
    const back = new URL(
      (await fetch(begun.authorize, { redirect: "manual" })).headers.get("location")!,
    );
    const { sealed } = (await mcp.routes.handle("/mcp/finish", {
      business: "acme",
      url: cardApp.url,
      name: "app-ramp",
      redirect,
      code: back.searchParams.get("code"),
      iss: back.searchParams.get("iss"),
      pending: begun.pending,
    })) as { sealed: Sealed };
    const issue = {
      app: "ramp",
      url: cardApp.url,
      sealed,
      tool: "ramp_get_agent_card_creds",
      arguments: {
        fund_id: "fund-1",
        amount: "12.99",
        currency_code: "USD",
        merchant_name: "Shop (127.0.0.1)",
        merchant_url: "https://127.0.0.1",
        merchant_country_code: "US",
        idempotency_key: "devys-approval-1",
      },
    };
    const acme = browser("acme");
    const paidBefore = paid.length;
    await script(acme, open(`${base}/checkout?frame=${encodeURIComponent(other)}`));
    const frame = (await script(
      acme,
      `const { targetInfos } = await session.Target.getTargets({});
      return targetInfos.find((t) => t.type === "iframe" && t.url.startsWith(${JSON.stringify(other)})).targetId;`,
    )) as string;
    const fields = [
      { selector: "#name", part: "name" as const },
      { selector: "#postal", part: "postal" as const },
      { target: frame, selector: "#number", part: "number" as const },
      { target: frame, selector: "#exp", part: "expiry" as const },
      { target: frame, selector: "#cvc", part: "cvc" as const },
    ];
    // Not the merchant's page: refused before the card app is ever asked.
    await expect(
      acme.fill({ issue, merchant: "Namecheap (namecheap.com)", fields }, "work-1"),
    ).rejects.toThrow(/not namecheap\.com/);
    expect(cardApp.calls.filter((call) => call.tool === "ramp_get_agent_card_creds")).toEqual([]);

    // On the merchant's page: the app issues the card for exactly what was approved; it is filled
    // and submitted, and only its last four and the app's reference come back.
    const filled = await acme.fill(
      { issue, merchant: "Shop (127.0.0.1)", fields, submit: { selector: "#pay" } },
      "work-1",
    );
    expect(filled).toEqual({
      origin: base,
      submitted: true,
      last4: "4242",
      reference: "ramp-token-77",
    });
    expect(JSON.stringify(filled)).not.toContain(issuedCard.card_number);
    expect(cardApp.calls.at(-1)).toEqual({
      tool: "ramp_get_agent_card_creds",
      args: issue.arguments,
    });
    for (let tries = 0; tries < 100 && paid.length === paidBefore; tries++)
      await new Promise((resolve) => setTimeout(resolve, 50));
    expect(paid.at(-1)).toEqual({
      number: issuedCard.card_number,
      exp: "12/31",
      cvc: issuedCard.cvv,
      name: issuedCard.cardholder_name,
      postal: issuedCard.billing_address.postal_code,
    });
    // What happened while the card was on the page is not kept for a later script to read.
    let events: unknown;
    for (let tries = 0; tries < 100 && !events; tries++)
      events = await acme
        .events(0, null, 0)
        .catch(() => new Promise((resolve) => setTimeout(resolve, 50)).then(() => undefined));
    expect(JSON.stringify(events)).not.toContain(issuedCard.card_number);
  },
);
