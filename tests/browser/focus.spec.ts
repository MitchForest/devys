import { test, expect, type Page } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";
import {
  bearer,
  insertMessage,
  openAbout,
  sidebar,
  signIn,
  stubPosting,
  type Sql,
} from "./helpers.ts";

// F1: a work item is one live card with one line of state and at most one ask; Home's pill opens
// the Chief of Staff's desk, and a thread's card is pinned right above the reply.

/** What an employee asked with askOwner on a work item, in its thread. */
async function ask(
  sql: Sql,
  owner: { business: string; chiefOfStaff: string },
  work: string,
  input: { kind: string } & Record<string, unknown>,
) {
  const grant = await sql.row<{ id: string }>(
    "SELECT id FROM grants WHERE employee_id = $1 AND capability = 'askOwner' AND revoked_at IS NULL",
    [owner.chiefOfStaff],
  );
  const id = randomUUID();
  await sql.run(
    `INSERT INTO decisions (id, kind, business_id, employee_id, grant_id, capability, input,
       input_hash, work_item_id, conversation, expires_at)
     VALUES ($1, $2, $3, $4, $5, 'askOwner', $6, $1, $7, $8, now() + interval '1 hour')`,
    [
      id,
      input.kind,
      owner.business,
      owner.chiefOfStaff,
      grant!.id,
      JSON.stringify(input),
      work,
      `work:${work}`,
    ],
  );
  return id;
}

const statusOf = async (sql: Sql, id: string) =>
  (await sql.row<{ status: string }>("SELECT status FROM decisions WHERE id = $1", [id]))?.status;

/** The employee's runtime as the stub says it is: idle, or running in one conversation. */
async function stubRuntime(page: Page, running: () => string | null) {
  const stops: string[] = [];
  await page.route(/\/employees\/[^/]+\/status$/, (route) => {
    const conversation = running();
    return route.fulfill({
      json: {
        state: {
          run: conversation
            ? {
                id: "run",
                stopped: false,
                deadline: null,
                conversation,
                doing: "Opening example.com",
              }
            : null,
          inbox: [],
          outbox: [],
        },
      },
    });
  });
  await page.route(/\/employees\/[^/]+\/stop$/, (route) => {
    stops.push(new URL(route.request().url()).pathname);
    return route.fulfill({ json: { stopped: true } });
  });
  return stops;
}

test("Home is the Chief of Staff, its desk the header's popover; work made there is one live card: Ready when you are, Start, then Working with Stop and Watch", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Quinn", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const work = await post<{ id: string }>(`${path}/work`, {
    title: "Buy acme-widgets.com",
    owner: owner.chiefOfStaff,
  });
  const plan = (doing: boolean) => [
    { title: "Find the domain", state: doing ? "doing" : "todo" },
    { title: "Sign in to the registrar", state: "todo", by: "owner" },
    { title: "Buy it", state: "todo" },
  ];
  await sql.run(
    "UPDATE work_items SET state = 'proposed', steps = $2, next_action = 'Find the domain' WHERE id = $1",
    [work.id, JSON.stringify(plan(false))],
  );
  // The Chief of Staff handed the work out from Home: its card is posted there.
  await insertMessage(sql, owner.business, `direct:${owner.chiefOfStaff}`, {
    author: `employee:${owner.chiefOfStaff}`,
    text: "Here is the plan.",
  });
  await insertMessage(sql, owner.business, `direct:${owner.chiefOfStaff}`, {
    author: "system",
    kind: "card",
    text: "Buy acme-widgets.com",
    ref: `devys:work/item/${work.id}`,
  });
  // A request with no work item waits once, inline, where it was asked.
  const grant = await sql.row<{ id: string }>(
    "SELECT id FROM grants WHERE employee_id = $1 AND capability = 'readPublicUrl' AND revoked_at IS NULL",
    [owner.chiefOfStaff],
  );
  const decision = randomUUID();
  await sql.run(
    `INSERT INTO decisions (id, business_id, employee_id, grant_id, capability, input, input_hash, expires_at)
     VALUES ($1, $2, $3, $4, 'readPublicUrl', '{"url":"https://example.com"}', 'fixture', now() + interval '1 hour')`,
    [decision, owner.business, owner.chiefOfStaff, grant!.id],
  );
  await stubPosting(page);
  let running: string | null = null;
  const stops = await stubRuntime(page, () => running);
  // Start hands the work out to a model; here it only becomes ready.
  const starts: string[] = [];
  await page.route(`**${path}/work/${work.id}/start`, async (route) => {
    starts.push(route.request().method());
    await sql.run("UPDATE work_items SET state = 'ready', revision = revision + 1 WHERE id = $1", [
      work.id,
    ]);
    const all = await route.fetch({
      url: `${new URL(route.request().url()).origin}${path}/work`,
      method: "GET",
    });
    const { work_items } = (await all.json()) as { work_items: { id: string }[] };
    await route.fulfill({ json: work_items.find((item) => item.id === work.id) });
  });
  let driving = false;
  await page.route(`**${path}/browser`, (route) =>
    route.fulfill({
      json: {
        open: driving,
        url: "https://registrar.example",
        title: "Registrar",
        driver: work.id,
        driving,
      },
    }),
  );
  try {
    await signIn(page, sql, owner.person);
    // Home is the Chief of Staff: no Needs you; their desk opens from the header's pill; the
    // badge still counts.
    await expect(page.getByRole("region", { name: "Needs you" })).toHaveCount(0);
    await expect(page.getByRole("region", { name: "Chief of Staff's desk" })).toHaveCount(0);
    await openAbout(page);
    await expect(page.getByRole("region", { name: "Chief of Staff's desk" })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.getByRole("region", { name: "Chief of Staff's desk" })).toHaveCount(0);
    await expect(sidebar(page).getByRole("link", { name: /^Chief of Staff/ })).toHaveAccessibleName(
      "Chief of Staff, 1",
    );
    // The request without work shows once, in the chat.
    await expect(page.getByTestId("request-card")).toHaveCount(1);

    const card = page.getByTestId("work-card");
    await expect(card).toHaveCount(1);
    await expect(card.getByText("Buy acme-widgets.com")).toBeVisible();
    await expect(card.getByTestId("work-step")).toHaveText("Step 1 of 3");
    await expect(card.getByRole("list", { name: "Steps" }).getByRole("listitem")).toHaveText([
      "Find the domain",
      "You: Sign in to the registrar",
      "Buy it",
    ]);
    await expect(card.getByTestId("work-state")).toHaveText("Ready when you are");
    await page.screenshot({ path: "/tmp/f1-proposed.png" });

    await card.getByRole("button", { name: "Start" }).click();
    await expect.poll(() => starts).toEqual(["POST"]);
    await expect(card.getByRole("button", { name: "Start" })).toHaveCount(0);
    await expect(card.getByTestId("work-state")).toHaveText("Up next: Find the domain");

    // Its employee runs on it, driving the business's browser: Working, with Stop and Watch.
    await sql.run("UPDATE work_items SET state = 'in_progress', steps = $2 WHERE id = $1", [
      work.id,
      JSON.stringify(plan(true)),
    ]);
    running = `work:${work.id}`;
    driving = true;
    // The plan shows the step; the line says what the employee is doing in it right now.
    await expect(card.getByTestId("work-state")).toHaveText("Opening example.com…", {
      timeout: 15_000,
    });
    await expect(card.getByRole("button", { name: "Watch" })).toBeVisible({ timeout: 15_000 });
    await page.screenshot({ path: "/tmp/f1-working.png" });
    await card.getByRole("button", { name: "Stop" }).click();
    await expect.poll(() => stops).toEqual([`${path}/employees/${owner.chiefOfStaff}/stop`]);

    // Running elsewhere is not working on this card.
    running = `direct:${owner.chiefOfStaff}`;
    await expect(card.getByRole("button", { name: "Stop" })).toHaveCount(0, { timeout: 15_000 });

    // Tapping the card opens its thread, where it is pinned and the browser can be watched.
    running = `work:${work.id}`;
    await card.getByText("Buy acme-widgets.com").click();
    await expect(page.getByTestId("place-title")).toHaveText("Buy acme-widgets.com");
    const pinned = page.getByTestId("work-card");
    await expect(pinned).toHaveCount(1);
    await pinned.getByRole("button", { name: "Watch" }).click();
    await expect(page).toHaveURL(new RegExp(`/thread/${work.id}\\?app=browser`));
    // The in-app browser is a picture to watch; the owner types in the business's Chrome.
    await expect(page.getByTestId("browser-view")).toBeVisible();
    await expect(page.getByLabel("Type into the page")).toHaveCount(0);
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("in its thread the card is pinned above the reply, with one ask at a time: Connect, then Open Chrome and Hand back", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Riley", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const pay = await post<{ id: string }>(`${path}/work`, {
    title: "Pay the paper supplier",
    owner: owner.chiefOfStaff,
  });
  await sql.run(
    `INSERT INTO remote_apps (business_id, id, name, summary, url, added_by)
     VALUES ($1, 'ledger', 'Ledger', 'The books', 'https://ledger.example/mcp', 'person:x')`,
    [owner.business],
  );
  await ask(sql, owner, pay.id, {
    kind: "connect",
    app: "ledger",
    why: "To read and draft the supplier's bills",
  });
  await insertMessage(sql, owner.business, `work:${pay.id}`, {
    author: `employee:${owner.chiefOfStaff}`,
    text: "I need the books to see what we owe.",
  });
  const domain = await post<{ id: string }>(`${path}/work`, {
    title: "Register the domain",
    owner: owner.chiefOfStaff,
  });
  const signInRequest = await ask(sql, owner, domain.id, {
    kind: "take_over",
    reason: "Sign in to the registrar (2FA)",
  });
  const email = await post<{ id: string }>(`${path}/work`, {
    title: "Set up email",
    owner: owner.chiefOfStaff,
  });
  await ask(sql, owner, email.id, { kind: "take_over", reason: "Sign in to the mail host" });
  await stubPosting(page);
  // The Mac host isn't beside the dev server: bringing Chrome to the front is stood in for,
  // working once and then unavailable.
  const fronted: number[] = [];
  await page.route(`**${path}/browser/front`, (route) => {
    fronted.push(Date.now());
    return fronted.length === 1
      ? route.fulfill({ json: { pid: 4242 } })
      : route.fulfill({ status: 503, body: "The Mac host is unavailable" });
  });
  try {
    await signIn(page, sql, owner.person);
    await page.goto(`/${owner.business}/thread/${pay.id}`);
    const card = page.getByTestId("work-card");
    await expect(card).toHaveCount(1);
    // A thread has no permanent view: the card is the work.
    await expect(page.getByRole("button", { name: /side panel/ })).toHaveCount(0);
    await expect(card.getByTestId("work-state")).toHaveText("Your turn: Connect Ledger");
    await expect(card.getByRole("button", { name: "Connect" })).toBeVisible();
    await expect(card.getByText("ledger.example")).toHaveCount(0);
    // Nothing twice: no separate request or app card in the conversation.
    await expect(page.getByTestId("request-card")).toHaveCount(0);
    await expect(page.getByTestId("app-card")).toHaveCount(0);
    // Pinned between the conversation and the reply.
    const said = await page.getByText("I need the books to see what we owe.").boundingBox();
    const pinned = await card.boundingBox();
    const reply = await page.getByRole("textbox", { name: "Reply" }).boundingBox();
    expect(pinned!.y).toBeGreaterThan(said!.y + said!.height);
    expect(pinned!.y + pinned!.height).toBeLessThanOrEqual(reply!.y);
    await page.screenshot({ path: "/tmp/f1-your-turn-connect.png" });
    // Connected: the app's review is the next step, from the same card.
    await sql.run("UPDATE remote_apps SET state = 'review' WHERE business_id = $1", [
      owner.business,
    ]);
    await expect(card.getByRole("button", { name: "Review" })).toBeVisible({ timeout: 15_000 });

    // A sign-in: Open Chrome takes the work over and brings the business's Chrome forward.
    await page.goto(`/${owner.business}/thread/${domain.id}`);
    await expect(card.getByTestId("work-state")).toHaveText(
      "Your turn: Sign in to the registrar (2FA)",
    );
    await page.screenshot({ path: "/tmp/f1-your-turn-chrome.png" });
    await card.getByRole("button", { name: "Open Chrome" }).click();
    await expect.poll(() => fronted.length).toBe(1);
    await expect.poll(() => statusOf(sql, signInRequest)).toBe("approved");
    await expect(card.getByTestId("work-state")).toHaveText("You have it");
    await expect(page).not.toHaveURL(/app=browser/);
    await page.screenshot({ path: "/tmp/f1-you-have-it.png" });
    await card.getByRole("button", { name: "Hand back" }).click();
    await expect
      .poll(
        async () =>
          (
            await sql.row<{ taken_over_by: string | null }>(
              "SELECT taken_over_by FROM work_items WHERE id = $1",
              [domain.id],
            )
          )?.taken_over_by,
      )
      .toBeNull();
    await expect(card.getByText("You have it")).toHaveCount(0);

    // Where Chrome can't come forward, the live browser opens beside the thread instead.
    await page.goto(`/${owner.business}/thread/${email.id}`);
    await card.getByRole("button", { name: "Open Chrome" }).click();
    await expect(page).toHaveURL(new RegExp(`/thread/${email.id}\\?app=browser`));
    await expect(
      page.getByTestId("browser-view").getByRole("button", { name: "Hand back" }),
    ).toBeVisible();
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("while an employee works in a chat it says what it is doing; a reply that took steps opens them", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Quinn", "Acme");
  try {
    const home = `direct:${owner.chiefOfStaff}`;
    await insertMessage(sql, owner.business, home, {
      author: `employee:${owner.chiefOfStaff}`,
      text: "The domain is available.",
      clientId: "reply:turn-1",
      worked: { ms: 80_000, steps: 2 },
    });
    let running: string | null = home;
    await stubRuntime(page, () => running);
    // The steps come from the employee's own record of the turn.
    const asked: string[] = [];
    await page.route(/\/messages\/[^/]+\/steps$/, (route) => {
      asked.push(route.request().method());
      return route.fulfill({
        json: { steps: ["Searching the app directory", "Opening example.com"] },
      });
    });
    await signIn(page, sql, owner.person);

    // Working in Home, though nothing was sent from this browser: its face, dots and the phrase.
    const working = page.getByRole("status").filter({ hasText: "Chief of Staff" });
    await expect(working.getByTestId("doing")).toHaveText("Opening example.com…", {
      timeout: 15_000,
    });
    running = null;
    await expect(working).toHaveCount(0, { timeout: 15_000 });

    // Under the reply, how it was worked out; the steps are read only when opened.
    const disclosure = page.getByRole("button", { name: /^Worked for 1m 20s · 2 steps/ });
    await expect(disclosure).toHaveAttribute("aria-expanded", "false");
    expect(asked).toEqual([]);
    await disclosure.click();
    await expect(page.getByRole("list", { name: "Steps" }).getByRole("listitem")).toHaveText([
      "Searching the app directory",
      "Opening example.com",
    ]);
    await page.screenshot({ path: "/tmp/worked-for.png" });
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
