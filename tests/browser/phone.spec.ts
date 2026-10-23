import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { bearer, insertMessage, signIn, stubPosting } from "./helpers.ts";

test.use({ viewport: { width: 390, height: 844 } });

test("on a phone: the list, then one conversation full screen; Back to the list; details from the pill", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Sasha", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const growth = { id: owner.team.growth };
  const project = await post<{ id: string }>(`${path}/projects`, {
    name: "Launch",
    goal: "Ship Acme v1",
    lead: growth.id,
  });
  const workItem = await post<{ id: string }>(`${path}/work`, {
    title: "Write a tagline",
    owner: growth.id,
    project_id: project.id,
  });
  await insertMessage(sql, owner.business, `project:${project.id}`, {
    author: "system",
    kind: "card",
    text: "Write a tagline",
    ref: `devys:work/item/${workItem.id}`,
  });
  const sent = await stubPosting(page);
  try {
    await signIn(page, sql, owner.person, { phone: true });
    await expect(page.getByRole("navigation", { name: "Sidebar" })).toHaveCount(0);

    // Back from a conversation is the list, as in Messages: tiles, Projects and Chats.
    await page.getByRole("button", { name: "Back", exact: true }).click();
    await expect(
      page.getByTestId("pinned").getByRole("link", { name: "Chief of Staff" }),
    ).toBeVisible();
    await expect(page.getByRole("heading", { name: "Projects" })).toBeVisible();
    await expect(page.getByRole("link", { name: /^Growth/ })).toBeVisible();
    await page.getByRole("link", { name: /^Launch/ }).click();
    await expect(page.getByLabel("Message Launch")).toBeVisible();

    // The header's pill opens the project's details over the conversation.
    await page.getByRole("button", { name: "About Launch" }).click();
    await expect(page.getByRole("region", { name: "Launch overview" })).toBeVisible();
    await expect(page.getByText("Ship Acme v1")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.getByRole("region", { name: "Launch overview" })).toHaveCount(0);

    // The work's card opens the thread full screen, its card pinned above the reply.
    await page.getByTestId("work-card").getByText("Write a tagline").click();
    await expect(page.getByRole("textbox", { name: "Reply" })).toBeVisible();
    await expect(page.getByTestId("work-card").getByText("Growth", { exact: true })).toBeVisible();
    await page.getByRole("textbox", { name: "Reply" }).fill("Under six words.");
    await page.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.key).toBe(`work:${workItem.id}`);

    // Back returns to the channel, then to the list.
    await page.getByRole("button", { name: "Back", exact: true }).click();
    await expect(page.getByLabel("Message Launch")).toBeVisible();
    await page.getByRole("button", { name: "Back", exact: true }).click();
    await page.getByRole("link", { name: /^Growth/ }).click();
    await expect(page.getByLabel("Message Growth")).toBeVisible();

    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
