import { test, expect } from "@playwright/test";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";

test("the web workspace adds work and approves an exact request through the same API", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Jordan", "Acme");
  const token = Array.from(randomBytes(32), (byte) => byte.toString(16).padStart(2, "0")).join("");
  await sql.run(
    "INSERT INTO enrollment_tokens (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [createHash("sha256").update(token).digest("hex"), owner.person],
  );
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
    await page.goto("/");
    await page.getByLabel("Enrollment code").fill(token);
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(page.getByRole("heading", { name: /, Jordan\.$/ })).toBeVisible();
    // The request waits on Today and inline in the DM with Operations.
    await expect(page.getByText("https://example.com")).toHaveCount(1);
    await page
      .getByRole("group", { name: "Direct messages" })
      .getByRole("button", { name: "Head of Operations" })
      .click();
    await expect(page.getByLabel("Message Head of Operations")).toBeVisible();
    await expect(page.getByText("https://example.com")).toHaveCount(1);
    await page.getByRole("button", { name: "Approve once" }).click();
    await page.getByRole("button", { name: /^Approvals/ }).click();
    await expect(page.getByText("Nothing needs your approval.")).toBeVisible();
    expect(
      (await sql.row<{ status: string }>("SELECT status FROM decisions WHERE id = $1", [decision]))
        ?.status,
    ).toBe("approved");
    await page.getByRole("button", { name: "Work", exact: true }).click();
    await page.getByLabel("New commitment").fill("Draft the PR inquiry");
    await page.getByRole("button", { name: "Add" }).click();
    await expect(page.getByText("Draft the PR inquiry")).toBeVisible();
    await page.getByText("Draft the PR inquiry").click({ button: "right" });
    await expect(page.getByRole("menuitem", { name: "Take over" })).toBeVisible();
    await page.keyboard.press("Escape");
    expect(
      (
        await sql.row<{ owner_employee_id: string }>(
          "SELECT owner_employee_id FROM commitments WHERE business_id = $1",
          [owner.business],
        )
      )?.owner_employee_id,
    ).toBe(owner.operations);
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
  } finally {
    await sql.run("DELETE FROM decisions WHERE business_id = $1", [owner.business]);
    await sql.run("DELETE FROM commitments WHERE business_id = $1", [owner.business]);
    await stores.remove([owner]);
    await stores.dispose();
  }
});
