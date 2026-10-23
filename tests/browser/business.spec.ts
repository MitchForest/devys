import { test, expect } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";
import { sidebar, signIn } from "./helpers.ts";

test("Home asks once, inline, and approves an exact request; new work opens its thread with its card pinned", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Jordan", "Acme");
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
  try {
    await signIn(page, sql, owner.person);

    // The request waits on Home: counted on its row and shown once, inline in the chat.
    await expect(sidebar(page).getByRole("link", { name: /^Chief of Staff/ })).toHaveAccessibleName(
      "Chief of Staff, 1",
    );
    await expect(page.getByRole("region", { name: "Needs you" })).toHaveCount(0);
    const request = page.getByTestId("request-card");
    await expect(request).toHaveCount(1);
    await expect(request.getByText("Chief of Staff asked to run this exactly:")).toBeVisible();
    await expect(request.getByText("https://example.com")).toBeVisible();
    await request.getByRole("button", { name: "Approve" }).click();
    await expect(request).toHaveCount(0);
    await expect(sidebar(page).getByRole("link", { name: /^Chief of Staff/ })).toHaveAccessibleName(
      "Chief of Staff",
    );
    await expect
      .poll(
        async () =>
          (
            await sql.row<{ status: string }>("SELECT status FROM decisions WHERE id = $1", [
              decision,
            ])
          )?.status,
      )
      .toBe("approved");

    // New → New work item opens the work item's thread with its card pinned above the reply.
    await sidebar(page).getByRole("button", { name: "New", exact: true }).click();
    await page.getByRole("menuitem", { name: "New work item" }).click();
    const dialog = page.getByRole("dialog", { name: "New work item" });
    await dialog.getByLabel("Title").fill("Draft the PR inquiry");
    await dialog.getByRole("button", { name: "Create work item" }).click();
    await expect(dialog).toBeHidden();
    await expect(page.getByTestId("place-title")).toHaveText("Draft the PR inquiry");
    const card = page.getByTestId("work-card");
    await expect(card.getByText("Chief of Staff", { exact: true })).toBeVisible();

    // Right-click takes the work over, which fences its employee; the card says the owner has it.
    await card.getByText("Draft the PR inquiry").click({ button: "right" });
    await page.getByRole("menuitem", { name: "Take over" }).click();
    await expect(card.getByTestId("work-state")).toHaveText("You have it");
    expect(
      (
        await sql.row<{ taken_over_by: string | null }>(
          "SELECT taken_over_by FROM work_items WHERE business_id = $1",
          [owner.business],
        )
      )?.taken_over_by,
    ).toBe(owner.person);

    // Hand back gives it back.
    await card.getByRole("button", { name: "Hand back" }).click();
    await expect(card.getByText("You have it")).toHaveCount(0);
    await expect
      .poll(
        async () =>
          (
            await sql.row<{ taken_over_by: string | null }>(
              "SELECT taken_over_by FROM work_items WHERE business_id = $1",
              [owner.business],
            )
          )?.taken_over_by,
      )
      .toBeNull();
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("Settings → Businesses creates a business with its starting team and switches to it", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Harper", "Acme");
  const created = async () =>
    (
      await sql.row<{ business_id: string }>(
        "SELECT business_id FROM memberships WHERE person_id = $1 AND business_id <> $2",
        [owner.person, owner.business],
      )
    )?.business_id;
  try {
    await signIn(page, sql, owner.person);
    await page.getByRole("button", { name: "Account" }).click();
    await page.getByRole("menuitem", { name: "Settings…" }).click();
    const settings = page.getByRole("dialog", { name: "Settings" });
    await settings.getByRole("button", { name: "Businesses", exact: true }).click();
    await settings.getByRole("button", { name: "New business" }).click();
    const form = settings.getByRole("form", { name: "New business" });
    await form.getByLabel("Name").fill("Globex");
    await form.getByLabel("Brief").fill("Sells widgets online.");
    // A Chief of Staff always; Growth is left out of this starting team.
    await form.getByRole("switch", { name: /^Growth/ }).uncheck({ force: true });
    await form.getByRole("button", { name: "Create business" }).click();
    await expect.poll(created).toBeTruthy();
    await page.keyboard.press("Escape");
    await expect(settings).toBeHidden();

    // The new business is selected: its own Home, sidebar and team.
    await expect(page.getByRole("link", { name: "Switch to Globex" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    await expect(page.getByTestId("place-title")).toHaveText("Chief of Staff");
    await expect(sidebar(page).getByRole("heading", { name: "Globex" })).toBeVisible();
    for (const name of ["Chief of Staff", "Engineering", "Admin"])
      await expect(sidebar(page).getByRole("link", { name, exact: true })).toBeVisible();
    await expect(sidebar(page).getByRole("link", { name: "Growth", exact: true })).toHaveCount(0);
    expect(
      (await sql.row<{ brief: string }>("SELECT brief FROM businesses WHERE id = $1", [
        await created(),
      ]))!.brief,
    ).toBe("Sells widgets online.");

    // Switching back shows Acme's own team, nothing shared.
    await page.getByRole("link", { name: "Switch to Acme" }).click();
    await expect(sidebar(page).getByRole("heading", { name: "Acme" })).toBeVisible();
    await expect(sidebar(page).getByRole("link", { name: "Engineering", exact: true })).toHaveCount(
      0,
    );
  } finally {
    await page.close();
    const other = await created();
    await stores.remove(other ? [owner, { person: owner.person, business: other }] : [owner]);
    await stores.dispose();
  }
});
