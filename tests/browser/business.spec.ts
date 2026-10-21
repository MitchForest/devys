import { test, expect } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";
import { sidebar, signIn } from "./helpers.ts";

test("Home's Needs you approves an exact request; new work opens its thread and is edited there", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Jordan", "Acme");
  const grant = await sql.row<{ id: string }>(
    "SELECT id FROM grants WHERE employee_id = $1 AND capability = 'readPublicUrl' AND revoked_at IS NULL",
    [owner.operations],
  );
  const decision = randomUUID();
  await sql.run(
    `INSERT INTO decisions (id, business_id, employee_id, grant_id, capability, input, input_hash, expires_at)
     VALUES ($1, $2, $3, $4, 'readPublicUrl', '{"url":"https://example.com"}', 'fixture', now() + interval '1 hour')`,
    [decision, owner.business, owner.operations, grant!.id],
  );
  try {
    await signIn(page, sql, owner.person);

    // The request waits on Home: counted on its row, in Needs you, and inline in the chat.
    await expect(sidebar(page).getByRole("link", { name: /^Home/ })).toHaveAccessibleName(
      "Home, 1",
    );
    const needsYou = page.getByRole("region", { name: "Needs you" });
    await expect(needsYou.getByTestId("panel-title")).toHaveText("Needs you");
    await expect(needsYou.getByText("Head of Operations asks")).toBeVisible();
    // Home lists it once, in Needs you; the conversation beside it doesn't repeat it.
    await expect(page.getByRole("main").getByText("https://example.com")).toHaveCount(0);

    // Its exact input unfolds on demand, and Approve answers it in place.
    await needsYou.getByRole("button", { name: "Details" }).click();
    await expect(needsYou.getByText("https://example.com")).toBeVisible();
    await needsYou.getByRole("button", { name: "Approve" }).click();
    await expect(needsYou).toBeHidden();
    await expect(page.getByRole("main").getByText("https://example.com")).toHaveCount(0);
    await expect(sidebar(page).getByRole("link", { name: /^Home/ })).toHaveAccessibleName("Home");
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

    // New → New work item opens the work item's thread with its card beside it.
    await sidebar(page).getByRole("button", { name: "New", exact: true }).click();
    await page.getByRole("menuitem", { name: "New work item" }).click();
    const dialog = page.getByRole("dialog", { name: "New work item" });
    await dialog.getByLabel("Title").fill("Draft the PR inquiry");
    await dialog.getByRole("button", { name: "Create work item" }).click();
    await expect(dialog).toBeHidden();
    await expect(page.getByTestId("place-title")).toHaveText("Draft the PR inquiry");
    const card = page.getByRole("region", { name: "Work item" });
    await expect(card.getByTestId("work-item-owner")).toHaveText("Head of Operations");

    // The card is read-only until the owner takes the work over, which fences its employee.
    await expect(card.getByRole("button", { name: "Edit next, waiting on and due" })).toHaveCount(
      0,
    );
    await expect(card.getByRole("button", { name: "Mark done" })).toHaveCount(0);
    await card.getByRole("button", { name: "Take over" }).click();
    await expect(card.getByRole("button", { name: "Hand back" })).toBeVisible();
    expect(
      (
        await sql.row<{ taken_over_by: string | null }>(
          "SELECT taken_over_by FROM work_items WHERE business_id = $1",
          [owner.business],
        )
      )?.taken_over_by,
    ).toBe(owner.person);

    // Then they edit what's next and what it waits on at the revision on screen.
    await card.getByRole("button", { name: "Edit next, waiting on and due" }).click();
    await card.getByLabel("Next").fill("Email three editors");
    await card.getByLabel("Waiting on").fill("The press kit");
    await card.getByRole("button", { name: "Save" }).click();
    await expect(card.getByText("Email three editors")).toBeVisible();
    expect(
      await sql.row<{ next_action: string; wait_condition: string | null }>(
        "SELECT next_action, wait_condition FROM work_items WHERE business_id = $1",
        [owner.business],
      ),
    ).toEqual({
      next_action: "Email three editors",
      wait_condition: "The press kit",
    });

    // Hand back gives it back, read-only again.
    await card.getByRole("button", { name: "Hand back" }).click();
    await expect(card.getByRole("button", { name: "Take over" })).toBeVisible();
    await expect(card.getByRole("button", { name: "Edit next, waiting on and due" })).toHaveCount(
      0,
    );
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
    // A Head of Operations always; Growth is left out of this starting team.
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
    await expect(page.getByTestId("place-title")).toHaveText("Home");
    await expect(sidebar(page).getByRole("heading", { name: "Globex" })).toBeVisible();
    for (const name of ["Head of Operations", "Engineering", "Business Operations"])
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
