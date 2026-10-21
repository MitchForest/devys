import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { bearer, insertMessage, signIn, stubPosting } from "./helpers.ts";

test.use({ viewport: { width: 390, height: 844 } });

test("on a phone: tabs of Home, Projects, Team and Apps; the conversation full screen; details in a sheet", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Sasha", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const growth = await post<{ id: string }>(`${path}/employees`, { template: "growth" });
  const project = await post<{ id: string }>(`${path}/projects`, {
    name: "Launch",
    goal: "Ship Acme v1",
    lead: growth.id,
  });
  const workItem = await post<{ id: string }>(`${path}/work`, {
    title: "Write a tagline",
    owner: growth.id,
    projectId: project.id,
  });
  await insertMessage(sql, owner.business, `project:${project.id}`, {
    author: "system",
    kind: "event",
    text: 'Growth took on "Write a tagline".',
    ref: `devys:work/item/${workItem.id}`,
  });
  const sent = await stubPosting(page);
  try {
    await signIn(page, sql, owner.person, { phone: true });
    const tabs = page.getByRole("navigation", { name: "Tabs" });
    for (const name of ["Home", "Projects", "Team", "Apps"])
      await expect(tabs.getByRole("button", { name })).toBeVisible();
    await expect(tabs.getByRole("button", { name: "Home" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    await expect(page.getByRole("navigation", { name: "Sidebar" })).toHaveCount(0);

    // The business menu holds what the desktop's header and New menu hold.
    await page.getByRole("button", { name: /^Switch business/ }).click();
    for (const name of ["New project", "Hire", "Settings"])
      await expect(page.getByRole("menuitem", { name, exact: true })).toBeVisible();
    await page.keyboard.press("Escape");

    // Projects lists each project; opening one fills the screen with its channel.
    await tabs.getByRole("button", { name: "Projects" }).click();
    await expect(tabs.getByRole("button", { name: "Projects" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    await page.getByRole("button", { name: /^Launch/ }).click();
    await expect(page.getByLabel("Message Launch")).toBeVisible();
    await expect(tabs).toHaveCount(0);

    // Its overview opens as a sheet over the conversation.
    await page.getByRole("button", { name: "Details" }).click();
    const details = page.getByRole("dialog", { name: "Details" });
    await expect(details.getByRole("region", { name: "Launch overview" })).toBeVisible();
    await expect(details.getByText("Ship Acme v1")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(details).toBeHidden();

    // A hand-off card opens the thread full screen; its work card is its details.
    await page.getByTestId("handoff").click();
    await expect(page.getByRole("textbox", { name: "Reply" })).toBeVisible();
    await page.getByRole("button", { name: "Details" }).click();
    await expect(details.getByRole("region", { name: "Work item" })).toBeVisible();
    await expect(details.getByTestId("work-item-owner")).toHaveText("Growth");
    await page.keyboard.press("Escape");
    await expect(details).toBeHidden();
    await page.getByRole("textbox", { name: "Reply" }).fill("Under six words.");
    await page.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.key).toBe(`work:${workItem.id}`);

    // Back returns to the channel, then to the list it was opened from.
    await page.getByRole("button", { name: "Back", exact: true }).click();
    await expect(page.getByLabel("Message Launch")).toBeVisible();
    await page.getByRole("button", { name: "Back", exact: true }).click();
    await expect(tabs.getByRole("button", { name: "Projects" })).toHaveAttribute(
      "aria-current",
      "page",
    );

    // Team opens a direct chat.
    await tabs.getByRole("button", { name: "Team" }).click();
    await page.getByRole("button", { name: "Growth", exact: true }).click();
    await expect(page.getByLabel("Message Growth")).toBeVisible();
    await page.getByRole("button", { name: "Back", exact: true }).click();

    // Apps open as a sheet over the conversation.
    await tabs.getByRole("button", { name: "Apps" }).click();
    await page.getByRole("button", { name: /^Documents/ }).click();
    await expect(details.getByRole("region", { name: "Documents" })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(details).toBeHidden();

    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
