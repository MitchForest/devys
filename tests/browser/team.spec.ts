import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import {
  fromPalette,
  hash,
  hex,
  openAbout,
  openSettings,
  sidebar,
  signIn,
  stubPosting,
  workView,
} from "./helpers.ts";

test("the owner hires from a template, edits and retires, and talks to any employee", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Morgan", "Acme");
  // This business has let its standard Growth go, so the owner hires one.
  await sql.run("UPDATE employees SET revoked_at = now() WHERE id = $1", [owner.team.growth]);
  const sent = await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);

    // Hire Growth from its template: the name comes prefilled, its responsibilities with it.
    await fromPalette(page, "New employee");
    const sheet = page.getByRole("dialog", { name: "New employee" });
    await sheet.getByLabel("Role").selectOption({ label: "Growth" });
    await expect(sheet.getByLabel("Name")).toHaveValue("Growth");
    await sheet.getByRole("button", { name: "Create", exact: true }).click();
    await expect(sheet).toBeHidden();

    // The new hire's direct chat opens; its desk is closed until the owner opens it.
    await expect(page.getByTestId("place-title")).toHaveText("Growth");
    await expect(page.getByRole("region", { name: "Growth's desk" })).toHaveCount(0);
    const growth = (await sql.row<{ id: string; responsibilities: string }>(
      "SELECT id, responsibilities FROM employees WHERE business_id = $1 AND template = 'growth' AND revoked_at IS NULL",
      [owner.business],
    ))!;
    expect(growth.responsibilities).toMatch(/^Grow the business\./);

    // The template's responsibilities show on the desk, and edits are saved.
    await openAbout(page);
    const desk = page.getByRole("region", { name: "Growth's desk" });
    await desk.getByText("Responsibilities", { exact: true }).click();
    const responsibilities = desk.getByLabel("Responsibilities");
    await expect(responsibilities).toHaveValue(growth.responsibilities);
    await responsibilities.fill("Own launch marketing for Acme. Report weekly with sources.");
    await desk.getByRole("button", { name: "Save responsibilities" }).click();
    await expect(desk.getByRole("status").filter({ hasText: "Saved" })).toBeVisible();
    expect(
      (await sql.row<{ responsibilities: string }>(
        "SELECT responsibilities FROM employees WHERE id = $1",
        [growth.id],
      ))!.responsibilities,
    ).toBe("Own launch marketing for Acme. Report weekly with sources.");

    // The direct chat sends to Growth.
    await page.getByLabel("Message Growth").fill("Draft three launch headlines.");
    await page.getByRole("button", { name: "Send" }).click();
    await expect(page.getByText("Draft three launch headlines.")).toBeVisible();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.key).toBe(`direct:${growth.id}`);
    expect(sent[0]!.body).toMatchObject({
      text: "Draft three launch headlines.",
    });

    // The Chief of Staff is Home; the pill opens their desk, and they can't be retired.
    await page.keyboard.press("Escape");
    await sidebar(page).getByRole("link", { name: "Chief of Staff" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Chief of Staff");
    await openAbout(page);
    const chiefOfStaffDesk = page.getByRole("region", {
      name: "Chief of Staff's desk",
    });
    await expect(chiefOfStaffDesk).toBeVisible();
    await expect(chiefOfStaffDesk.getByRole("button", { name: "Retire…" })).toHaveCount(0);

    // A project's details start a thread in it, owned by whoever the owner picks.
    await page.keyboard.press("Escape");
    await fromPalette(page, "New project");
    const create = page.getByRole("dialog", { name: "New project" });
    await create.getByLabel("Name").fill("Launch");
    await create.getByRole("button", { name: "Create project" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    const project = (await sql.row<{ id: string }>(
      "SELECT id FROM projects WHERE business_id = $1 AND name = 'Launch'",
      [owner.business],
    ))!;
    await openAbout(page);
    const overview = page.getByRole("region", { name: "Launch overview" });
    await overview.getByRole("button", { name: "Work" }).click();
    const dialog = page.getByRole("dialog", { name: "New work item" });
    await dialog.getByLabel("Title").fill("Write the launch post");
    await dialog.getByLabel("Owner").selectOption({ label: "Growth" });
    await dialog.getByLabel("Objective").fill("A post the owner approves before Friday");
    await expect(dialog.getByLabel("Project")).toHaveValue(project.id);
    await dialog.getByRole("button", { name: "Create work item" }).click();
    await expect(dialog).toBeHidden();
    const workItem = (await sql.row<{
      id: string;
      owner_employee_id: string;
      project_id: string;
    }>(
      "SELECT id, owner_employee_id, project_id FROM work_items WHERE business_id = $1 AND title = 'Write the launch post'",
      [owner.business],
    ))!;
    expect(workItem.owner_employee_id).toBe(growth.id);
    expect(workItem.project_id).toBe(project.id);

    // It opens beside the project's channel, which stays in the middle.
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    const card = workView(page).getByTestId("work-card");
    await expect(card.getByText("Growth", { exact: true })).toBeVisible();
    await workView(page)
      .getByRole("textbox", { name: "Reply to Growth" })
      .fill("Start with the outline.");
    await workView(page).getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(2);
    expect(sent[1]!.key).toBe(`work:${workItem.id}`);
    await openAbout(page);
    await expect(overview.getByText("Write the launch post")).toBeVisible();
    await page.keyboard.press("Escape");

    // Retiring Growth, from its row's menu, hands its open work to the chosen successor.
    await sidebar(page)
      .getByRole("link", { name: /^Growth/ })
      .click({ button: "right" });
    await page.getByRole("menuitem", { name: "Retire…" }).click();
    const retire = page.getByRole("dialog", { name: "Retire Growth?" });
    await expect(retire).toContainText("1 open work item moves");
    await retire.getByLabel("Hand open work to").selectOption({ label: "Chief of Staff" });
    await retire.getByRole("button", { name: "Retire", exact: true }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Chief of Staff");
    await expect(sidebar(page).getByRole("link", { name: "Growth" })).toHaveCount(0);
    expect(
      (await sql.row<{ owner_employee_id: string }>(
        "SELECT owner_employee_id FROM work_items WHERE id = $1",
        [workItem.id],
      ))!.owner_employee_id,
    ).toBe(owner.chiefOfStaff);
    expect(
      (await sql.row<{ retired: boolean }>(
        "SELECT revoked_at IS NOT NULL AS retired FROM employees WHERE id = $1",
        [growth.id],
      ))!.retired,
    ).toBe(true);
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("Settings → Devices lists signed-in devices and signs one out", async ({ page }) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Quinn", "Acme");
  await stubPosting(page);
  // Another device already signed in as Quinn.
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at, label) VALUES ($1, $2, now() + interval '1 day', $3)",
    [hash(hex()), owner.person, "Quinn's iPad"],
  );
  try {
    await signIn(page, sql, owner.person);
    await openSettings(page);
    const settings = page.getByRole("dialog", { name: "Settings" });
    await settings.getByRole("button", { name: "Devices", exact: true }).click();

    const devices = settings.getByRole("list", { name: "Devices" });
    await expect(devices.getByRole("listitem")).toHaveCount(3);
    await expect(devices.getByText(/^This device · Added/)).toHaveCount(1);
    await expect(devices.getByText("Quinn's iPad")).toBeVisible();
    // No codes: devices join from their own sign-in screen.
    await expect(settings.getByText(/code/i)).toHaveCount(0);

    // Signing out one device signs only that device out.
    await settings.getByRole("button", { name: "Sign out Quinn's iPad" }).click();
    await expect(devices.getByText("Quinn's iPad")).toHaveCount(0);
    expect(
      (await sql.row<{ n: number }>(
        "SELECT count(*)::int AS n FROM web_sessions WHERE person_id = $1 AND label = $2",
        [owner.person, "Quinn's iPad"],
      ))!.n,
    ).toBe(0);
  } finally {
    await stores.remove([owner]);
    await stores.dispose();
  }
});
