import { test, expect } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";
import {
  bearer,
  fromPalette,
  insertMessage,
  openAbout,
  sidebar,
  signIn,
  stubPosting,
} from "./helpers.ts";

type Stores = Awaited<ReturnType<typeof localStores>>;

/** A page an employee published: its bytes in R2 and its record, as artifactPage saves one. */
async function publish(stores: Stores, business: string, filename: string, html: string) {
  const id = randomUUID();
  const key = `${business}/artifacts/${id}`;
  await stores.files.put(key, html);
  await stores.sql.run(
    `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length)
     VALUES ($1, $2, $3, $4, $5, 'text/html', $6)`,
    [id, business, `fixture-${id}`, key, filename, html.length],
  );
  return { id, key };
}

test("New project with goal, deadline, budget, lead and team opens its channel; its pill shows the details", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Emerson", "Acme");
  const growth = { id: owner.team.growth };
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    // No projects yet: the section is absent, not an empty destination.
    await expect(sidebar(page).getByRole("heading", { name: "Projects" })).toHaveCount(0);

    await fromPalette(page, "New project");
    const dialog = page.getByRole("dialog", { name: "New project" });
    await dialog.getByLabel("Name").fill("Launch");
    await dialog.getByLabel("Goal").fill("Ship Acme v1 to the first ten customers");
    await dialog.getByLabel("Deadline").fill("2026-12-15");
    await dialog.getByLabel("Budget").fill("1500");
    await dialog.getByLabel("Lead").selectOption({ label: "Growth" });
    await dialog.getByRole("button", { name: /Chief of Staff/ }).click();
    await expect(dialog.getByRole("button", { name: /Chief of Staff/ })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await dialog.getByRole("button", { name: "Create project" }).click();
    await expect(dialog).toBeHidden();

    // Its channel is the middle; its details open from the header's pill.
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    await expect(page.getByLabel("Message Launch")).toBeVisible();
    await expect(sidebar(page).getByRole("heading", { name: "Projects" })).toBeVisible();
    await expect(sidebar(page).getByRole("link", { name: "Launch" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    await openAbout(page);
    const overview = page.getByRole("region", { name: "Launch overview" });
    await expect(overview.getByTestId("panel-title")).toHaveText("Overview");
    await expect(overview.getByText("Ship Acme v1 to the first ten customers")).toBeVisible();
    await expect(overview.getByText(/^Dec 15 · \d+d$/)).toBeVisible();
    await expect(overview.getByText("$1,500")).toBeVisible();
    await expect(overview.getByRole("button", { name: "Growth" })).toBeVisible();
    await expect(overview.getByRole("button", { name: "Chief of Staff" })).toBeVisible();
    // No work yet: the Work section holds no standing description.
    await expect(overview.getByText("No threads yet.", { exact: false })).toHaveCount(0);

    const project = (await sql.row<{
      id: string;
      goal: string;
      deadline: string;
      budget_cents: string;
      budget_currency: string;
      lead_employee_id: string;
    }>(
      `SELECT id, goal, deadline::text AS deadline, budget_cents::text AS budget_cents,
              budget_currency, lead_employee_id FROM projects WHERE business_id = $1`,
      [owner.business],
    ))!;
    expect(project).toMatchObject({
      goal: "Ship Acme v1 to the first ten customers",
      deadline: "2026-12-15",
      budget_cents: "150000",
      budget_currency: "USD",
      lead_employee_id: growth.id,
    });
    expect(
      await sql.row("SELECT 1 FROM project_members WHERE project_id = $1 AND employee_id = $2", [
        project.id,
        owner.chiefOfStaff,
      ]),
    ).toBeTruthy();

    // The overview is read-only: the project changes by asking in its channel.
    await expect(overview.getByRole("button", { name: "Edit project" })).toHaveCount(0);
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("a page card opens a layer, is kept in the project, and a new version replaces it", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Finley", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const growth = { id: owner.team.growth };
  const project = await post<{ id: string }>(`${path}/projects`, {
    name: "Launch",
    lead: growth.id,
  });
  const channel = `project:${project.id}`;
  const first = await publish(stores, owner.business, "Pricing.html", "<h1>Pricing v1</h1>");
  await insertMessage(sql, owner.business, channel, {
    author: `employee:${growth.id}`,
    kind: "event",
    text: "Published a page: Pricing",
    ref: `devys:documents/artifact/${first.id}`,
  });
  const keys = [first.key];
  const sent = await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    await sidebar(page)
      .getByRole("link", { name: /^Launch/ })
      .click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    const overview = page.getByRole("region", { name: "Launch overview" });
    // Nothing is open beside the channel until the owner opens something to look at.
    await expect(page.getByTestId("panel-title")).toHaveCount(0);

    // The card opens the page as a layer beside the channel; it goes with the next message.
    await page.getByTestId("page-card").click();
    const layer = page.getByRole("region", { name: "Pricing" });
    await expect(layer.getByTestId("panel-title")).toHaveText("Pricing");
    await expect(
      layer.frameLocator('[data-testid="artifact-frame"]').getByRole("heading", {
        name: "Pricing v1",
      }),
    ).toBeVisible();
    await expect(page.getByTestId("reference-chip")).toHaveText("Viewing Pricing");
    // The layer is in the address: reloading (or opening the link) shows the same page.
    await expect(page).toHaveURL(
      `/${owner.business}/project/${project.id}?layer=devys:documents/artifact/${first.id}`,
    );
    await page.reload();
    await expect(layer.getByTestId("panel-title")).toHaveText("Pricing");
    await expect(page.getByTestId("reference-chip")).toHaveText("Viewing Pricing");
    // The next message carries the page as its ref; its words stay as written.
    await page.getByLabel("Message Launch").fill("Make it shorter");
    await page.getByRole("button", { name: "Send", exact: true }).click();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.body.text).toBe("Make it shorter");
    expect(sent[0]!.body.ref).toBe(`devys:documents/artifact/${first.id}`);

    // Keep pins it in the project: a reference, so the page stays where it was made.
    await layer.getByRole("button", { name: "Keep" }).click();
    await page.getByRole("menuitem", { name: "Keep in Launch" }).click();
    await expect(layer.getByRole("button", { name: "Launch" })).toBeVisible();
    expect(
      await sql.row("SELECT 1 FROM project_items WHERE project_id = $1 AND ref = $2", [
        project.id,
        `devys:documents/artifact/${first.id}`,
      ]),
    ).toBeTruthy();

    // A new version published in the channel replaces the open page and says who changed it.
    const second = await publish(stores, owner.business, "Pricing.html", "<h1>Pricing v2</h1>");
    keys.push(second.key);
    await insertMessage(sql, owner.business, channel, {
      author: `employee:${growth.id}`,
      kind: "event",
      text: "Published a page: Pricing",
      ref: `devys:documents/artifact/${second.id}`,
    });
    await expect(layer.getByTestId("updated-by")).toHaveText("Updated by Growth", {
      timeout: 15_000,
    });
    await expect(
      layer.frameLocator('[data-testid="artifact-frame"]').getByRole("heading", {
        name: "Pricing v2",
      }),
    ).toBeVisible();
    await expect(layer.getByText("v2 of 2")).toBeVisible();
    // The page is kept, whichever version is open.
    await expect(layer.getByRole("button", { name: "Launch" })).toBeVisible();
    await layer.getByRole("button", { name: "Earlier version" }).click();
    await expect(layer.getByText("v1 of 2")).toBeVisible();
    await expect(layer.getByRole("button", { name: "Launch" })).toBeVisible();

    // × closes the panel; the kept page is pinned under the channel's header, once, and opens
    // as it is now. The details list it too.
    await layer.getByRole("button", { name: "Close" }).click();
    await expect(layer).toHaveCount(0);
    const pins = page.getByLabel("Pinned");
    await expect(pins.getByRole("button", { name: "Pricing" })).toHaveCount(1);
    // Animations settle (popovers zoom in, faces draw) before the picture.
    await page.waitForTimeout(600);
    await page.screenshot({ path: "/tmp/g-project-pins.png" });
    await openAbout(page);
    await expect(overview.getByRole("button", { name: "Pricing" })).toHaveCount(1);
    await page.keyboard.press("Escape");
    await pins.getByRole("button", { name: "Pricing" }).click();
    await expect(page.getByRole("region", { name: "Pricing" })).toBeVisible();
    await expect(layer.getByText("v2 of 2")).toBeVisible();
    await expect(
      layer.frameLocator('[data-testid="artifact-frame"]').getByRole("heading", {
        name: "Pricing v2",
      }),
    ).toBeVisible();
  } finally {
    await page.close();
    await stores.remove([owner]);
    for (const key of keys) await stores.files.delete(key);
    await stores.dispose();
  }
});

test("the right panel opens only for a layer; a further layer stacks; Esc goes back one at a time", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Rowan", "Acme");
  const roadmap = await publish(stores, owner.business, "Roadmap.html", "<h1>Roadmap</h1>");
  const pricing = await publish(stores, owner.business, "Pricing.html", "<h1>Pricing</h1>");
  await stubPosting(page);
  const jump = async (title: string) => {
    // Keys go to the workspace, not to a page open in its frame.
    await page.getByLabel("Message Chief of Staff").click();
    await page.keyboard.press("Meta+k");
    await page.keyboard.type(title);
    await page.keyboard.press("Enter");
    await expect(page.getByRole("dialog", { name: "Search" })).toBeHidden();
  };
  try {
    await signIn(page, sql, owner.person);
    // The conversation has the full width: nothing beside it.
    await expect(page.getByRole("region", { name: "Needs you" })).toHaveCount(0);
    await expect(page.getByTestId("panel-title")).toHaveCount(0);

    // A page opens beside the conversation without leaving it; another stacks over it.
    await jump("Roadmap");
    const first = page.getByRole("region", { name: "Roadmap" });
    await expect(first.getByTestId("panel-title")).toHaveText("Roadmap");
    await expect(page.getByTestId("place-title")).toHaveText("Chief of Staff");
    await expect(page.getByLabel("Message Chief of Staff")).toBeVisible();
    await jump("Pricing");
    const second = page.getByRole("region", { name: "Pricing" });
    await expect(second.getByRole("button", { name: "Back", exact: true })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(first).toBeVisible();
    await expect(second).toHaveCount(0);
    await page.keyboard.press("Escape");
    await expect(page.getByTestId("panel-title")).toHaveCount(0);
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.files.delete(roadmap.key);
    await stores.files.delete(pricing.key);
    await stores.dispose();
  }
});
