import { test, expect } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";
import { bearer, sidebar, signIn } from "./helpers.ts";

// LP6: a remote app an employee asks the owner to connect. The owner sees the ask on the work's
// card (logo, name, Connect), then its one review (on its own, asks first, never, who uses it),
// and turns it on; no address, scope or tool name shows.
test("a connect request is the work card's one ask; the review turns the app on", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Riley", "Acme");
  const post = await bearer(sql, owner.person);
  const work = await post<{ id: string }>(`/api/businesses/${owner.business}/work`, {
    title: "Pay the paper supplier",
    owner: owner.chiefOfStaff,
  });
  const grant = await sql.row<{ id: string }>(
    "SELECT id FROM grants WHERE employee_id = $1 AND capability = 'askOwner' AND revoked_at IS NULL",
    [owner.chiefOfStaff],
  );
  // Ledger: added and asked for, not connected yet.
  await sql.run(
    `INSERT INTO remote_apps (business_id, id, name, summary, url, added_by)
     VALUES ($1, 'ledger', 'Ledger', 'The books', 'https://ledger.example/mcp', 'person:x')`,
    [owner.business],
  );
  const request = randomUUID();
  const ask = { kind: "connect", app: "ledger", why: "To read and draft the supplier's bills" };
  await sql.run(
    `INSERT INTO decisions (id, kind, business_id, employee_id, grant_id, capability, input,
       input_hash, work_item_id, conversation, expires_at)
     VALUES ($1, 'connect', $2, $3, $4, 'askOwner', $5, $1, $6, $7, now() + interval '1 hour')`,
    [
      request,
      owner.business,
      owner.chiefOfStaff,
      grant!.id,
      JSON.stringify(ask),
      work.id,
      `work:${work.id}`,
    ],
  );
  try {
    await signIn(page, sql, owner.person);
    // Home counts it; the thread's card asks it, with the app's name and Connect.
    await expect(sidebar(page).getByRole("link", { name: /^Chief of Staff/ })).toHaveAccessibleName(
      "Chief of Staff, 1",
    );
    await page.goto(`/${owner.business}/thread/${work.id}`);
    const card = page.getByTestId("work-card");
    await expect(card.getByTestId("work-state")).toHaveText("Your turn: Connect Ledger");
    await expect(card.getByRole("button", { name: "Connect" })).toBeVisible();
    await expect(card.getByRole("button", { name: "Approve" })).toHaveCount(0);
    await expect(page.getByText("ledger.example")).toHaveCount(0);

    // Connected (the provider's sign-in happened): its tools wait for the owner's review.
    await sql.run(
      `UPDATE remote_apps SET state = 'review', tools = $2 WHERE business_id = $1 AND id = 'ledger'`,
      [
        owner.business,
        JSON.stringify([
          {
            name: "list_entries",
            title: "List entries",
            description: "List ledger entries.",
            input: { type: "object" },
            hints: { readOnlyHint: true },
          },
          {
            name: "post_entry",
            description: "Post a journal entry.",
            input: { type: "object" },
            hints: { destructiveHint: true },
          },
          {
            name: "ramp_get_agent_card_creds",
            description: "Get a one-time payment token for a fund.",
            input: { type: "object" },
            hints: {},
          },
        ]),
      ],
    );
    await expect(card.getByRole("button", { name: "Review" })).toBeVisible({ timeout: 15_000 });
    await card.getByRole("button", { name: "Review" }).click();
    const review = page.getByTestId("app-review");
    await expect(review.getByText("Can do on its own")).toBeVisible();
    await expect(review.getByText("List entries")).toBeVisible();
    await expect(review.getByText("Asks you first")).toBeVisible();
    await expect(review.getByText("Post entry")).toBeVisible();
    await expect(review.getByText("Never available to employees")).toBeVisible();
    await expect(review.getByText("Ramp get agent card creds")).toBeVisible();
    await expect(review.getByText("Who can use it")).toBeVisible();
    await review.getByRole("button", { name: "Turn on" }).click();
    await expect
      .poll(
        async () =>
          (
            await sql.row<{ state: string }>(
              "SELECT state FROM remote_apps WHERE business_id = $1 AND id = 'ledger'",
              [owner.business],
            )
          )?.state,
      )
      .toBe("on");
    // The owner's acceptance is the policy: a read on its own, a write asks, the card tool never.
    const mode = async (capability: string) =>
      (
        await sql.row<{ mode: string }>(
          `SELECT mode FROM grants WHERE business_id = $1 AND employee_id = $2 AND capability = $3
             AND revoked_at IS NULL`,
          [owner.business, owner.chiefOfStaff, capability],
        )
      )?.mode;
    expect(await mode("ledger_list_entries")).toBe("auto");
    expect(await mode("ledger_post_entry")).toBe("ask");
    expect(await mode("ledger_ramp_get_agent_card_creds")).toBeUndefined();
  } finally {
    // Stop the page's polling before its business is removed.
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
