import { test, expect, type Page } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";
import { bearer, insertMessage, openAbout, sidebar, signIn, stubPosting } from "./helpers.ts";

// G (2026-10-23): the sidebar after Grok Bot. Pinned tiles (the Chief of Staff pinned, with a
// star), Projects only while there are any, Chats as Messages rows with a menu; the header's pill
// opens a desk or a project's details; Connect apps; question cards; New employee.

const pinned = (page: Page) => sidebar(page).getByTestId("pinned");
const mark = async (sql: Awaited<ReturnType<typeof localStores>>["sql"], key: string) =>
  await sql.row<{ pinned: boolean; hidden: boolean; unread: boolean }>(
    `SELECT pinned_at IS NOT NULL AS pinned, hidden_at IS NOT NULL AS hidden,
       marked_unread AS unread FROM conversation_marks WHERE conversation = $1`,
    [key],
  );

test("pinned tiles, chats as rows, and each row's menu: pin, unpin, mark unread, hide", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Rowan", "Acme");
  const growth = { id: owner.team.growth };
  const finance = { id: owner.team.finance };
  await insertMessage(sql, owner.business, `direct:${growth.id}`, {
    author: `employee:${growth.id}`,
    text: "Drafted three **launch** headlines for you.",
  });
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    // The Chief of Staff alone is pinned, with their star; nothing else heads the sidebar.
    await expect(pinned(page).getByRole("link")).toHaveCount(1);
    await expect(pinned(page).getByRole("link", { name: "Chief of Staff" })).toBeVisible();
    await expect(pinned(page).getByTestId("star")).toBeVisible();
    for (const name of ["Home", "Team", "Apps", "Documents", "Code"])
      await expect(sidebar(page).getByText(name, { exact: true })).toHaveCount(0);
    await expect(sidebar(page).getByRole("heading", { name: "Projects" })).toHaveCount(0);

    // Everyone else is a row: face, name, last line; unread shows.
    const growthRow = sidebar(page).getByRole("link", { name: "Growth, 1 unread" });
    await expect(growthRow).toBeVisible();
    await expect(growthRow).toContainText("Drafted three launch headlines for you.");
    await expect(sidebar(page).getByRole("link", { name: "Finance" })).toBeVisible();

    // Pin Growth from its row's menu: it joins the tiles.
    await growthRow.click({ button: "right" });
    await page.getByRole("menuitem", { name: "Pin", exact: true }).click();
    await expect(pinned(page).getByRole("link", { name: /^Growth/ })).toBeVisible();
    await expect.poll(async () => (await mark(sql, `direct:${growth.id}`))?.pinned).toBe(true);
    await page.mouse.move(0, 0);
    // Animations settle (popovers zoom in, faces draw) before the picture.
    await page.waitForTimeout(600);
    await page.screenshot({ path: "/tmp/g-sidebar.png" });

    // Unpin the Chief of Staff: a row like the others, still the place the workspace opens.
    await pinned(page).getByRole("link", { name: "Chief of Staff" }).click({ button: "right" });
    await page.getByRole("menuitem", { name: "Unpin" }).click();
    await expect(pinned(page).getByRole("link")).toHaveCount(1);
    await expect(sidebar(page).getByRole("heading", { name: "Chats" }).locator("..")).toBeVisible();
    await expect
      .poll(async () => (await mark(sql, `direct:${owner.chiefOfStaff}`))?.pinned)
      .toBe(false);

    // Mark Finance unread, from the hover "…" button this time.
    const financeRow = sidebar(page).getByRole("link", { name: "Finance", exact: true });
    await financeRow.hover();
    await sidebar(page).getByRole("button", { name: "More for Finance" }).click();
    await page.getByRole("menuitem", { name: "Mark as unread" }).click();
    await expect(sidebar(page).getByRole("link", { name: "Finance, 1 unread" })).toBeVisible();
    await expect.poll(async () => (await mark(sql, `direct:${finance.id}`))?.unread).toBe(true);

    // Hide Finance: gone until something new is said there.
    await sidebar(page)
      .getByRole("link", { name: /^Finance/ })
      .click({ button: "right" });
    await page.getByRole("menuitem", { name: "Hide from sidebar" }).click();
    await expect(sidebar(page).getByRole("link", { name: /^Finance/ })).toHaveCount(0);
    await insertMessage(sql, owner.business, `direct:${finance.id}`, {
      author: `employee:${finance.id}`,
      text: "The books are closed for October.",
    });
    await expect(sidebar(page).getByRole("link", { name: /^Finance/ })).toBeVisible({
      timeout: 15_000,
    });
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("Projects show only while there are any; the header's pill opens the desk or the details", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Sage", "Acme");
  const post = await bearer(sql, owner.person);
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    await expect(sidebar(page).getByRole("heading", { name: "Projects" })).toHaveCount(0);
    // No breadcrumb and no panel toggle: the right panel opens only for a layer.
    await expect(page.getByRole("navigation", { name: "Breadcrumb" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: /side panel/ })).toHaveCount(0);

    // The pill opens the Chief of Staff's desk as a popover.
    await openAbout(page);
    const desk = page.getByRole("region", { name: "Chief of Staff's desk" });
    await expect(desk).toBeVisible();
    await expect(desk.getByRole("button", { name: "Retire…" })).toHaveCount(0);
    await page.keyboard.press("Escape");
    await expect(desk).toHaveCount(0);

    // A project appears under Projects, its channel's pill opens its details.
    await post(`/api/businesses/${owner.business}/projects`, {
      name: "Launch",
      goal: "Ship the site by Friday",
    });
    await expect(sidebar(page).getByRole("heading", { name: "Projects" })).toBeVisible({
      timeout: 15_000,
    });
    await sidebar(page).getByRole("link", { name: "Launch" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    await openAbout(page);
    const details = page.getByRole("region", { name: "Launch overview" });
    await expect(details.getByText("Ship the site by Friday")).toBeVisible();
    await page.mouse.move(0, 0);
    // Animations settle (popovers zoom in, faces draw) before the picture.
    await page.waitForTimeout(600);
    await page.screenshot({ path: "/tmp/g-project-details.png" });
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("a question card: one answer sends at once; several are picked and sent with Done", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Kai", "Acme");
  const sent = await stubPosting(page, () => [owner.chiefOfStaff]);
  const direct = `direct:${owner.chiefOfStaff}`;
  const single = await insertMessage(sql, owner.business, direct, {
    author: `employee:${owner.chiefOfStaff}`,
    text: "The launch post is ready.",
    question: "When should it go out?",
    replies: ["Today", "Tomorrow", "Next week"],
  });
  try {
    await signIn(page, sql, owner.person);
    const card = page.getByRole("group", { name: "When should it go out?" });
    await expect(card.getByRole("button")).toHaveText([
      "AToday",
      "BTomorrow",
      "CNext week",
      "Something else",
    ]);
    const field = page.getByLabel("Message Chief of Staff");
    await expect(field).toHaveAttribute(
      "placeholder",
      "Type your answer, or talk about something else",
    );
    // Something else puts the cursor in the composer; with it empty, B answers.
    await card.getByRole("button", { name: "Something else" }).click();
    await expect(field).toBeFocused();
    await page.keyboard.press("b");
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.body).toMatchObject({ text: "Tomorrow", reply_to: single });
    await expect(card).toHaveCount(0);

    // Several may be picked: each toggles; Done sends them together. (The stand-in server
    // stores nothing, so the answer above would wait as unsent; a reload starts clean.)
    await page.reload();
    await insertMessage(sql, owner.business, direct, {
      author: `employee:${owner.chiefOfStaff}`,
      text: "I can connect your money apps.",
      question: "Which should I connect?",
      replies: ["Stripe", "Ramp", "Mercury"],
      pickMany: true,
    });
    const many = page.getByRole("group", { name: "Which should I connect?" });
    await expect(many).toBeVisible({ timeout: 15_000 });
    await many.getByRole("button", { name: /Stripe/ }).click();
    await many.getByRole("button", { name: /Mercury/ }).click();
    await expect(many.getByRole("button", { name: /Stripe/ })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await page.mouse.move(0, 0);
    // Animations settle (popovers zoom in, faces draw) before the picture.
    await page.waitForTimeout(600);
    await page.screenshot({ path: "/tmp/g-question-card.png" });
    await many.getByRole("button", { name: "Done" }).click();
    await expect.poll(() => sent.length).toBe(2);
    expect(sent[1]!.body).toMatchObject({ text: "Stripe, Mercury" });
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("Connect apps: listed apps by category with logos, search, Add, and the connected ones", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Ellis", "Acme");
  await stubPosting(page);
  // Logos come from each app's own site the first time; here they are a stand-in square.
  const logo = Buffer.from(
    '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" rx="14" fill="#5a68f0"/></svg>',
  );
  await page.route(/\/apps\/listed\/[a-z0-9-]+\/logo$/, (route) =>
    route.fulfill({ status: 200, contentType: "image/svg+xml", body: logo }),
  );
  // The provider's sign-in is not part of this check: Add stops at the connecting app.
  await page.route(/\/apps\/[a-z0-9-]+\/connect$/, (route) =>
    route.fulfill({ status: 200, json: { url: null } }),
  );
  try {
    await signIn(page, sql, owner.person);
    const button = sidebar(page).getByRole("button", { name: "Connect apps" });
    await expect(button.locator("img")).toHaveCount(3);
    await button.click();
    const sheet = page.getByRole("dialog", { name: "Connect apps" });
    await expect(sheet.getByRole("region", { name: "Recommended for you" })).toBeVisible();
    await expect(sheet.getByRole("region", { name: "Payments and finance" })).toBeVisible();
    // Built-in abilities are never apps here.
    await expect(sheet.getByText("Documents", { exact: true })).toHaveCount(0);
    // Animations settle (popovers zoom in, faces draw) before the picture.
    await page.waitForTimeout(600);
    await page.screenshot({ path: "/tmp/g-connect-apps.png" });

    // A category chip shows its apps; search finds across them.
    await sheet.getByRole("button", { name: "Payments and finance" }).click();
    await expect(sheet.getByTestId("app-row").filter({ hasText: "Stripe" })).toBeVisible();
    await sheet.getByLabel("Search apps").fill("ramp");
    const ramp = sheet.getByTestId("app-row").filter({ hasText: "Ramp" }).first();
    await expect(ramp).toBeVisible({ timeout: 15_000 });

    // Add starts connecting it; it is then among the connected.
    await ramp.getByRole("button", { name: "Add Ramp" }).click();
    await expect(sheet.getByRole("button", { name: /1 connected/ })).toBeVisible({
      timeout: 15_000,
    });
    await sheet.getByRole("button", { name: /1 connected/ }).click();
    await expect(page.getByRole("dialog", { name: "Connected" }).getByText("Ramp")).toBeVisible();
    await expect(
      page.getByRole("dialog", { name: "Connected" }).getByText("Not connected yet"),
    ).toBeVisible();
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("New employee: a face, a name, a role and a look; Create hires them and opens their chat", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Noor", "Acme");
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    await sidebar(page).getByRole("button", { name: "New", exact: true }).click();
    await page.getByRole("menuitem", { name: "New employee" }).click();
    const sheet = page.getByRole("dialog", { name: "New employee" });
    await sheet.getByLabel("Role").selectOption({ label: "Growth" });
    await expect(sheet.getByLabel("Name")).toHaveValue("Growth");
    await sheet.getByLabel("Name").fill("Nova");
    await sheet.getByRole("button", { name: "hexagon" }).click();
    await sheet.getByRole("button", { name: "Teal" }).click();
    // Animations settle (popovers zoom in, faces draw) before the picture.
    await page.waitForTimeout(600);
    await page.screenshot({ path: "/tmp/g-new-employee.png" });
    await sheet.getByRole("button", { name: "Create" }).click();
    await expect(sheet).toBeHidden();
    await expect(page.getByTestId("place-title")).toHaveText("Nova");
    const hired = async () =>
      await sql.row<{ template: string; look: { shape: string; palette: string } | null }>(
        "SELECT template, look FROM employees WHERE business_id = $1 AND name = 'Nova'",
        [owner.business],
      );
    await expect.poll(async () => (await hired())?.look?.shape).toBe("hexagon");
    expect(await hired()).toMatchObject({ template: "growth", look: { palette: "teal" } });
    await expect(sidebar(page).getByRole("link", { name: /^Nova/ })).toBeVisible();
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("the composer's + uploads a file or attaches a business file or page; it goes with the next message", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Remy", "Acme");
  const id = randomUUID();
  const key = `${owner.business}/artifacts/${id}`;
  await stores.files.put(key, "<h1>Menu</h1>");
  await sql.run(
    `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length)
     VALUES ($1, $2, $3, $4, 'Menu.html', 'text/html', 13)`,
    [id, owner.business, `fixture-${id}`, key],
  );
  const sent = await stubPosting(page, () => [owner.chiefOfStaff]);
  try {
    await signIn(page, sql, owner.person);
    await page.getByRole("button", { name: "Attach a file" }).click();
    await page.getByRole("menuitem", { name: "Choose a business file…" }).click();
    await page
      .getByRole("dialog", { name: "Attach a file" })
      .getByRole("button", { name: "Menu" })
      .click();
    await expect(page.getByTestId("attached-chip")).toHaveText("Menu");
    await page.getByLabel("Message Chief of Staff").fill("Use this for the flyer.");
    await page.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.body).toMatchObject({
      text: "Use this for the flyer.",
      ref: `devys:documents/artifact/${id}`,
    });
    await expect(page.getByTestId("attached-chip")).toHaveCount(0);

    // Upload a file: it goes into the business folder's Uploads and with the next message.
    const uploaded = `devys:documents/file/${encodeURIComponent("/business/Uploads/logo.png")}`;
    const uploads: string[] = [];
    await page.route(/\/files\/upload\?name=/, (route) => {
      uploads.push(new URL(route.request().url()).searchParams.get("name") ?? "");
      return route.fulfill({ json: { ref: uploaded } });
    });
    await page.getByRole("button", { name: "Attach a file" }).click();
    const chooser = page.waitForEvent("filechooser");
    await page.getByRole("menuitem", { name: "Upload a file…" }).click();
    await (
      await chooser
    ).setFiles({
      name: "logo.png",
      mimeType: "image/png",
      buffer: Buffer.from("not really a png"),
    });
    await expect(page.getByTestId("attached-chip")).toHaveText("logo.png");
    expect(uploads).toEqual(["logo.png"]);
    await page.getByLabel("Message Chief of Staff").fill("Our logo.");
    await page.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(2);
    expect(sent[1]!.body).toMatchObject({ text: "Our logo.", ref: uploaded });
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.files.delete(key);
    await stores.dispose();
  }
});
