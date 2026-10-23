import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { bearer, insertMessage, signIn, stubPosting } from "./helpers.ts";

test("a work item's steps and results show as one card in its thread, updated in place, and in its work card", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Quinn", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const work = await post<{ id: string }>(`${path}/work`, {
    title: "Set up acme-widgets.com",
    owner: owner.operations,
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
  // The one card the server posts the first time steps or results are set.
  await insertMessage(sql, owner.business, `work:${work.id}`, {
    author: "system",
    kind: "card",
    text: "Set up acme-widgets.com",
    ref: `devys:work/item/${work.id}`,
  });
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    // Home's moving line says where the steps stand.
    await expect(page.getByText("1 of 3 · Set up email")).toBeVisible();

    await page.goto(`/${owner.business}/thread/${work.id}`);
    const card = page.getByTestId("work-progress");
    await expect(card).toHaveCount(1);
    await expect(card).toContainText("1 of 3 · Set up email");
    await expect(card.getByRole("list", { name: "Steps" }).getByRole("listitem")).toHaveText([
      "Register the domain",
      "Set up email",
      "Send a test email",
    ]);
    await expect(card.getByRole("list", { name: "Results" })).toHaveText(
      "Registered acme-widgets.com· expires 2027-10-22✓",
    );
    // The work card, its permanent view, shows the same.
    const panel = page.getByRole("region", { name: "Work item" });
    await expect(panel.getByTestId("work-results")).toContainText("Registered acme-widgets.com");
    await expect(panel.getByTestId("work-steps")).toContainText("Steps · 1 of 3 · Set up email");

    // A later change updates the same card in place: no new message.
    await show(
      [
        { title: "Register the domain", state: "done" },
        { title: "Set up email", state: "done" },
        { title: "Send a test email", state: "done" },
      ],
      [
        { label: "Live at", url: "https://acme-widgets.com", ok: true },
        { label: "MX records", ok: true },
        { label: "Payment", value: "uncertain", ok: null },
      ],
    );
    await expect(card).toContainText("3 of 3", { timeout: 15_000 });
    await expect(page.getByTestId("work-progress")).toHaveCount(1);
    const results = card.getByRole("list", { name: "Results" }).getByRole("listitem");
    await expect(results).toHaveText([
      "Live athttps://acme-widgets.com✓",
      "MX records✓",
      "Payment· uncertain?",
    ]);
    await expect(results.first().getByRole("link")).toHaveAttribute(
      "href",
      "https://acme-widgets.com",
    );
  } finally {
    // Stop the page's polling before its business is removed.
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
