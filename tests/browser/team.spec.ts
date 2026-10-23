import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { hash, hex, sidebar, signIn, stubPosting } from "./helpers.ts";

test("the owner hires from a template, edits and retires, and talks to any employee", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Morgan", "Acme");
  const sent = await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);

    // Hire Growth from its template: name and responsibilities come prefilled.
    await sidebar(page).getByRole("button", { name: "New", exact: true }).click();
    await page.getByRole("menuitem", { name: "Hire" }).click();
    const sheet = page.getByRole("dialog", { name: "Hire" });
    await sheet.getByRole("button", { name: "Growth" }).click();
    await expect(sheet.getByLabel("Name")).toHaveValue("Growth");
    await expect(sheet.getByLabel("Responsibilities")).toHaveValue(/^Grow the business\./);
    await expect(sheet.getByRole("list", { name: "Starting access" })).toContainText(
      "Read public websites",
    );
    await sheet.getByRole("button", { name: "Hire", exact: true }).click();
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
    await page.getByRole("button", { name: /^Show side panel/ }).click();
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

    // Operations can't be retired. The desk stays open for every direct chat.
    await sidebar(page).getByRole("link", { name: "Head of Operations" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Head of Operations");
    const operationsDesk = page.getByRole("region", {
      name: "Head of Operations's desk",
    });
    await expect(operationsDesk).toBeVisible();
    await expect(operationsDesk.getByRole("button", { name: "Retire…" })).toHaveCount(0);

    // A project's overview starts a thread in it, owned by whoever the owner picks.
    await sidebar(page).getByRole("button", { name: "New", exact: true }).click();
    await page.getByRole("menuitem", { name: "New project" }).click();
    const create = page.getByRole("dialog", { name: "New project" });
    await create.getByLabel("Name").fill("Launch");
    await create.getByRole("button", { name: "Create project" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    const project = (await sql.row<{ id: string }>(
      "SELECT id FROM projects WHERE business_id = $1 AND name = 'Launch'",
      [owner.business],
    ))!;
    const overview = page.getByRole("region", { name: "Launch overview" });
    await overview.getByRole("button", { name: "Thread" }).click();
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

    // Its thread opens in the middle, under the project, with its work card.
    await expect(page.getByTestId("place-title")).toHaveText("Write the launch post");
    const card = page.getByRole("region", { name: "Work item" });
    await expect(card.getByTestId("work-item-owner")).toHaveText("Growth");
    await expect(card.getByTestId("panel-title")).toHaveText("Write the launch post");
    await page.getByRole("textbox", { name: "Reply" }).fill("Start with the outline.");
    await page.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(2);
    expect(sent[1]!.key).toBe(`work:${workItem.id}`);
    await page.getByRole("button", { name: "Back (⌘[)" }).click();
    await expect(overview.getByText("Write the launch post")).toBeVisible();

    // Retiring Growth hands its open work to the chosen successor.
    await sidebar(page).getByRole("link", { name: "Growth" }).click();
    await page
      .getByRole("region", { name: "Growth's desk" })
      .getByRole("button", { name: "Retire…" })
      .click();
    const retire = page.getByRole("dialog", { name: "Retire Growth?" });
    await expect(retire).toContainText("1 open work item moves");
    await retire.getByLabel("Hand open work to").selectOption({ label: "Head of Operations" });
    await retire.getByRole("button", { name: "Retire", exact: true }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Head of Operations");
    await expect(sidebar(page).getByRole("link", { name: "Growth" })).toHaveCount(0);
    expect(
      (await sql.row<{ owner_employee_id: string }>(
        "SELECT owner_employee_id FROM work_items WHERE id = $1",
        [workItem.id],
      ))!.owner_employee_id,
    ).toBe(owner.operations);
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
    await page.getByRole("button", { name: "Account" }).click();
    await page.getByRole("menuitem", { name: "Settings…" }).click();
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
