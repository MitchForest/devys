import { test, expect, type Page } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";
import {
  bearer,
  fromPalette,
  insertMessage,
  openAbout,
  sidebar,
  signIn,
  stubPosting,
} from "./helpers.ts";

// G (2026-10-23): the sidebar after Grok Bot. Pinned tiles (the Chief of Staff pinned: face and
// name, no card or mark), Projects only while there are any, Chats as Messages rows with a menu; the header's pill
// opens a desk or a project's details; Connect apps; question cards; New employee.

/** The team's rows, top first, by the first word of their names. */
const teamOrder = async (page: Page) =>
  (await sidebar(page).getByRole("link").allInnerTexts()).map((text) => text.split("\n")[0]);
const mark = async (sql: Awaited<ReturnType<typeof localStores>>["sql"], key: string) =>
  await sql.row<{ pinned: boolean; hidden: boolean; unread: boolean }>(
    `SELECT pinned_at IS NOT NULL AS pinned, hidden_at IS NOT NULL AS hidden,
       marked_unread AS unread FROM conversation_marks WHERE conversation = $1`,
    [key],
  );

test("Team, with what is pinned at its top, and each row's menu: pin, unpin, mark unread, hide", async ({
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
    // Team heads the sidebar, the Chief of Staff (pinned) at its top; no tiles, no Chats.
    await expect(sidebar(page).getByRole("heading", { name: "Team" })).toBeVisible();
    await expect(sidebar(page).getByRole("heading", { name: "Chats" })).toHaveCount(0);
    await expect(sidebar(page).getByTestId("pinned")).toHaveCount(0);
    await expect
      .poll(() => teamOrder(page))
      .toEqual(["Chief of Staff", "Growth", "Admin", "Finance", "Engineering"]);
    for (const name of ["Home", "Apps", "Documents", "Code"])
      await expect(sidebar(page).getByText(name, { exact: true })).toHaveCount(0);
    await expect(sidebar(page).getByRole("heading", { name: "Projects" })).toHaveCount(0);

    // Everyone else is a row: face, name, last line; unread shows.
    const growthRow = sidebar(page).getByRole("link", { name: "Growth, 1 unread" });
    await expect(growthRow).toBeVisible();
    await expect(growthRow).toContainText("Drafted three launch headlines for you.");
    await expect(sidebar(page).getByRole("link", { name: "Finance" })).toBeVisible();

    // Pin Finance from its row's menu: it moves up, under the Chief of Staff.
    await sidebar(page).getByRole("link", { name: "Finance" }).click({ button: "right" });
    await page.getByRole("menuitem", { name: "Pin", exact: true }).click();
    await expect
      .poll(() => teamOrder(page))
      .toEqual(["Chief of Staff", "Finance", "Growth", "Admin", "Engineering"]);
    await expect.poll(async () => (await mark(sql, `direct:${finance.id}`))?.pinned).toBe(true);
    await page.mouse.move(0, 0);
    // Animations settle (popovers zoom in, faces draw) before the picture.
    await page.waitForTimeout(600);
    await page.screenshot({ path: "/tmp/g-sidebar.png" });

    // Unpin the Chief of Staff: it takes its place by the latest word, after what is pinned.
    await sidebar(page)
      .getByRole("link", { name: /^Chief of Staff/ })
      .click({ button: "right" });
    await page.getByRole("menuitem", { name: "Unpin" }).click();
    await expect.poll(async () => (await teamOrder(page))[0]).toBe("Finance");
    await expect
      .poll(async () => (await mark(sql, `direct:${owner.chiefOfStaff}`))?.pinned)
      .toBe(false);
    // Finance unpinned again, for what follows.
    await sidebar(page).getByRole("link", { name: "Finance" }).click({ button: "right" });
    await page.getByRole("menuitem", { name: "Unpin" }).click();
    await expect.poll(async () => (await mark(sql, `direct:${finance.id}`))?.pinned).toBe(false);

    // Mark Finance unread. Hovering a row adds no button: its actions are on right-click alone.
    const financeRow = sidebar(page).getByRole("link", { name: "Finance", exact: true });
    await financeRow.hover();
    await expect(sidebar(page).getByRole("button", { name: /^More for/ })).toHaveCount(0);
    await financeRow.click({ button: "right" });
    await page.getByRole("menuitem", { name: "Mark as unread" }).click();
    await expect(sidebar(page).getByRole("link", { name: "Finance, 1 unread" })).toBeVisible();
    await expect.poll(async () => (await mark(sql, `direct:${finance.id}`))?.unread).toBe(true);

    // Hide Finance: gone until something new is said there.
    await sidebar(page)
      .getByRole("link", { name: /^Finance/ })
      .click({ button: "right" });
    await page.getByRole("menuitem", { name: "Hide from sidebar" }).click();
    await expect(sidebar(page).getByRole("link", { name: /^Finance/ })).toHaveCount(0);
    // The hide is stored before the next message, which then brings the row back.
    await expect.poll(async () => (await mark(sql, `direct:${finance.id}`))?.hidden).toBe(true);
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

test("work pins to the top of Work, and stays there while pinned, even done; unpinned, done work leaves", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Rowan", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const first = await post<{ id: string }>(`${path}/work`, {
    title: "Set up payroll",
    owner: owner.team.finance,
  });
  const second = await post<{ id: string }>(`${path}/work`, {
    title: "Buy acme-widgets.com",
    owner: owner.team.admin,
  });
  await sql.run("UPDATE work_items SET updated_at = now() - interval '1 minute' WHERE id = $1", [
    second.id,
  ]);
  const rows = () => sidebar(page).getByTestId("work-row");
  try {
    await signIn(page, sql, owner.person);
    await expect(rows().first()).toHaveAccessibleName(/^Set up payroll, /);
    // Pinned from its menu, it heads Work.
    await rows().filter({ hasText: "Buy acme-widgets.com" }).click({ button: "right" });
    await page.getByRole("menuitem", { name: "Pin" }).click();
    await expect(rows().first()).toHaveAccessibleName(/^Buy acme-widgets\.com, /);
    await expect.poll(async () => (await mark(sql, `work:${second.id}`))?.pinned).toBe(true);
    // Done and seen, it stays while pinned.
    await sql.run("UPDATE work_items SET state = 'completed' WHERE id = $1", [second.id]);
    await expect(rows().first()).toHaveAccessibleName("Buy acme-widgets.com, Done", {
      timeout: 15_000,
    });
    // Unpinned, done work it has nothing unread in leaves.
    await rows().first().click({ button: "right" });
    await page.getByRole("menuitem", { name: "Unpin" }).click();
    await expect(rows()).toHaveCount(1);
    await expect(rows().first()).toHaveAccessibleName(/^Set up payroll, /);
    void first;
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

    // A click outside the sheet, on the dim backdrop, closes it, as Esc does.
    await page.mouse.click(8, 8);
    await expect(page.getByRole("dialog", { name: /Connect/ })).toHaveCount(0);
    await button.click();
    await expect(sheet).toBeVisible();
    await page.mouse.click(8, 8);
    await expect(sheet).toBeHidden();
    await button.click();
    await expect(sheet).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(sheet).toBeHidden();
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
    await fromPalette(page, "New employee");
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

test("Search: the toolbar's search and ⌘K open the palette; its rows run by click, keys and ⌘1…⌘9", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Iris", "Acme");
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    // Nothing is created or searched from the sidebar itself: the toolbar has Search.
    for (const name of ["Search", "New"])
      await expect(sidebar(page).getByRole("button", { name, exact: true })).toHaveCount(0);
    await page.getByRole("toolbar").getByRole("button", { name: "Search" }).click();
    const palette = page.getByRole("dialog", { name: "Search" });
    await expect(palette.getByPlaceholder("Search")).toBeFocused();
    const rows = palette.getByRole("option");
    // The Chief of Staff, then the actions and Settings, each with its shortcut.
    await expect(rows.nth(0)).toContainText("Chief of Staff");
    await expect(rows.nth(0)).toContainText("⌘1");
    const titles = [
      "New employee",
      "New project",
      "Connect apps",
      "Keyboard shortcuts",
      "Settings: Account",
    ];
    for (const [index, title] of titles.entries()) {
      await expect(rows.nth(index + 1)).toContainText(title);
      await expect(rows.nth(index + 1)).toContainText(`⌘${index + 2}`);
    }
    await expect(palette.getByRole("option", { name: /Settings: Voice/ })).toContainText(
      "Settings",
    );
    // The other employees follow.
    await expect(palette.getByRole("option", { name: /^Growth/ })).toBeVisible();
    await page.mouse.move(0, 0);
    await page.waitForTimeout(600);
    await page.screenshot({ path: "/tmp/palette-web.png" });

    // ⌘2 runs New employee.
    await page.keyboard.press("Meta+2");
    await expect(palette).toBeHidden();
    const hire = page.getByRole("dialog", { name: "New employee" });
    await expect(hire).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(hire).toBeHidden();

    // ⌘K, typing and Enter: a Settings row opens Settings at that section.
    await page.keyboard.press("Meta+k");
    await expect(palette).toBeVisible();
    await page.keyboard.type("voice");
    await expect(rows.first()).toContainText("Settings: Voice");
    await page.keyboard.press("Enter");
    const settings = page.getByRole("dialog", { name: "Settings" });
    await expect(settings).toBeVisible();
    await expect(settings.getByRole("button", { name: "Voice", exact: true })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await page.keyboard.press("Escape");
    await expect(settings).toBeHidden();

    // ↓ and Enter; Keyboard shortcuts lists the web's shortcuts.
    await page.keyboard.press("Meta+k");
    for (let step = 0; step < 4; step++) await page.keyboard.press("ArrowDown");
    await page.keyboard.press("Enter");
    const sheet = page.getByRole("dialog", { name: "Keyboard shortcuts" });
    await expect(sheet.getByText("⌘K")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(sheet).toBeHidden();

    // A click outside the palette closes it.
    await page.keyboard.press("Meta+k");
    await expect(palette).toBeVisible();
    await page.mouse.click(8, 8);
    await expect(palette).toBeHidden();
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
