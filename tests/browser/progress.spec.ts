import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { bearer, insertMessage, openWork, signIn, stubPosting, workView } from "./helpers.ts";

test("a work item opens beside the conversation: its card heads its conversation, updated in place", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Quinn", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const work = await post<{ id: string }>(`${path}/work`, {
    title: "Set up acme-widgets.com",
    owner: owner.chiefOfStaff,
  });
  const show = (steps: unknown[], results: unknown[]) =>
    sql.run(
      `UPDATE work_items SET steps = $2, results = $3, state = 'in_progress',
         revision = revision + 1, updated_at = now() WHERE id = $1`,
      [work.id, JSON.stringify(steps), JSON.stringify(results)],
    );
  await show(
    [
      { title: "Register the domain", state: "done" },
      { title: "Set up email", state: "doing" },
      { title: "Send a test email", state: "todo" },
    ],
    [{ label: "Registered acme-widgets.com", value: "expires 2027-10-22", ok: true }],
  );
  // A card message in the work's own conversation is drawn once, as the card heading it.
  await insertMessage(sql, owner.business, `work:${work.id}`, {
    author: "system",
    kind: "card",
    text: "Set up acme-widgets.com",
    ref: `devys:work/item/${work.id}`,
  });
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    await openWork(page, owner.business, work.id);
    // Beside Home: the conversation in the middle stays the Chief of Staff's.
    await expect(page.getByTestId("place-title")).toHaveText("Chief of Staff");
    const card = workView(page).getByTestId("work-card");
    await expect(card).toHaveCount(1);
    await expect(card.getByTestId("work-step")).toHaveText("Step 2 of 3");
    await expect(card.getByRole("list", { name: "Steps" }).getByRole("listitem")).toHaveText([
      "Register the domain",
      "Set up email",
      "Send a test email",
    ]);
    await expect(card.getByRole("list", { name: "Results" })).toHaveText(
      "Registered acme-widgets.com · expires 2027-10-22 ✓",
    );
    await expect(
      workView(page).getByRole("textbox", { name: "Reply to Chief of Staff" }),
    ).toBeVisible();
    // The sidebar lists it under Work, where it stands, marked as the one open.
    const row = page.getByTestId("work-row");
    await expect(row).toHaveAccessibleName("Set up acme-widgets.com, Step 2 of 3");
    await expect(row).toHaveAttribute("aria-current", "true");

    // A later change updates the same card in place: no new message. A link shows as its site.
    await show(
      [
        { title: "Register the domain", state: "done" },
        { title: "Set up email", state: "done" },
        { title: "Send a test email", state: "done" },
      ],
      [
        { label: "Live at", url: "https://www.acme-widgets.com/welcome?from=card", ok: true },
        { label: "MX records", ok: true },
        { label: "Payment", value: "uncertain", ok: null },
      ],
    );
    await expect(card.getByTestId("work-step")).toHaveText("Step 3 of 3", { timeout: 15_000 });
    await expect(page.getByTestId("work-card")).toHaveCount(1);
    const results = card.getByRole("list", { name: "Results" }).getByRole("listitem");
    await expect(results).toHaveText([
      "Live at · acme-widgets.com ✓",
      "MX records ✓",
      "Payment · uncertain ?",
    ]);
    await expect(results.first().getByRole("link", { name: "acme-widgets.com" })).toHaveAttribute(
      "href",
      "https://www.acme-widgets.com/welcome?from=card",
    );
  } finally {
    // Stop the page's polling before its business is removed.
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
