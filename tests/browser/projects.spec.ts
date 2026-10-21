import { test, expect, type Page } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";
import { bearer, insertMessage, sidebar, signIn, stubPosting } from "./helpers.ts";

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

const toolbarPanel = (page: Page, shown: boolean) =>
  page.getByRole("button", {
    name: shown ? "Hide side panel (⌥⌘0)" : "Show side panel (⌥⌘0)",
  });

test("New project with goal, deadline, budget, lead and team opens its channel and overview", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Emerson", "Acme");
  const post = await bearer(sql, owner.person);
  const growth = await post<{ id: string }>(`/api/businesses/${owner.business}/employees`, {
    template: "growth",
  });
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    // No projects yet: the section is absent, not an empty destination.
    await expect(sidebar(page).getByRole("heading", { name: "Projects" })).toHaveCount(0);

    await sidebar(page).getByRole("button", { name: "New", exact: true }).click();
    await page.getByRole("menuitem", { name: "New project" }).click();
    const dialog = page.getByRole("dialog", { name: "New project" });
    await dialog.getByLabel("Name").fill("Launch");
    await dialog.getByLabel("Goal").fill("Ship Acme v1 to the first ten customers");
    await dialog.getByLabel("Deadline").fill("2026-12-15");
    await dialog.getByLabel("Budget").fill("1500");
    await dialog.getByLabel("Lead").selectOption({ label: "Growth" });
    await dialog.getByRole("button", { name: /Head of Operations/ }).click();
    await expect(dialog.getByRole("button", { name: /Head of Operations/ })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await dialog.getByRole("button", { name: "Create project" }).click();
    await expect(dialog).toBeHidden();

    // Its channel is the middle; its overview is the permanent view, open by default.
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    await expect(page.getByLabel("Message Launch")).toBeVisible();
    await expect(sidebar(page).getByRole("heading", { name: "Projects" })).toBeVisible();
    await expect(sidebar(page).getByRole("button", { name: "Launch" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    const overview = page.getByRole("region", { name: "Launch overview" });
    await expect(overview.getByTestId("panel-title")).toHaveText("Overview");
    await expect(overview.getByText("Ship Acme v1 to the first ten customers")).toBeVisible();
    await expect(overview.getByText(/^Dec 15 · \d+d$/)).toBeVisible();
    await expect(overview.getByText("$1,500")).toBeVisible();
    await expect(overview.getByRole("button", { name: "Growth" })).toBeVisible();
    await expect(overview.getByRole("button", { name: "Head of Operations" })).toBeVisible();
    await expect(overview.getByText("No threads yet.", { exact: false })).toBeVisible();

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
        owner.operations,
      ]),
    ).toBeTruthy();

    // The overview edits the project in place.
    await overview.getByRole("button", { name: "Edit project" }).click();
    await overview.getByLabel("Goal").fill("Ship Acme v1 to twenty customers");
    await overview.getByRole("button", { name: "Save" }).click();
    await expect(overview.getByText("Ship Acme v1 to twenty customers")).toBeVisible();
    await expect
      .poll(
        async () =>
          (await sql.row<{ goal: string }>("SELECT goal FROM projects WHERE id = $1", [project.id]))
            ?.goal,
      )
      .toBe("Ship Acme v1 to twenty customers");
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
  const growth = await post<{ id: string }>(`${path}/employees`, { template: "growth" });
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
    ref: `artifact:${first.id}`,
  });
  const keys = [first.key];
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    await sidebar(page)
      .getByRole("button", { name: /^Launch/ })
      .click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    const overview = page.getByRole("region", { name: "Launch overview" });
    await expect(overview).toBeVisible();

    // The card opens the page as a layer over the overview; it goes with the next message.
    await page.getByTestId("page-card").click();
    const layer = page.getByRole("region", { name: "Pricing" });
    await expect(layer.getByTestId("panel-title")).toHaveText("Pricing");
    await expect(overview).toHaveCount(0);
    await expect(
      layer.frameLocator('[data-testid="artifact-frame"]').getByRole("heading", {
        name: "Pricing v1",
      }),
    ).toBeVisible();
    await expect(page.getByTestId("reference-chip")).toHaveText("Viewing Pricing");

    // Keep puts it on the project's overview: a reference, so the page stays in Documents.
    await layer.getByRole("button", { name: "Keep" }).click();
    await page.getByRole("menuitem", { name: "Keep in Launch" }).click();
    await expect(layer.getByRole("button", { name: "Launch" })).toBeVisible();
    expect(
      await sql.row(
        "SELECT 1 FROM project_items WHERE project_id = $1 AND kind = 'artifact' AND ref = $2",
        [project.id, first.id],
      ),
    ).toBeTruthy();

    // A new version published in the channel replaces the open page and says who changed it.
    const second = await publish(stores, owner.business, "Pricing.html", "<h1>Pricing v2</h1>");
    keys.push(second.key);
    await insertMessage(sql, owner.business, channel, {
      author: `employee:${growth.id}`,
      kind: "event",
      text: "Published a page: Pricing",
      ref: `artifact:${second.id}`,
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
    await layer.getByRole("button", { name: "Earlier version" }).click();
    await expect(layer.getByText("v1 of 2")).toBeVisible();

    // × returns to the overview, which lists the kept page.
    await layer.getByRole("button", { name: "Close (back to the panel)" }).click();
    await expect(overview).toBeVisible();
    await expect(overview.getByRole("button", { name: "Pricing" })).toBeVisible();
    await overview.getByRole("button", { name: "Pricing" }).click();
    await expect(page.getByRole("region", { name: "Pricing" })).toBeVisible();
  } finally {
    await page.close();
    await stores.remove([owner]);
    for (const key of keys) await stores.files.delete(key);
    await stores.dispose();
  }
});

test("the Documents app opens as a layer; Esc goes back one layer; the panel is remembered per kind", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Rowan", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const growth = await post<{ id: string }>(`${path}/employees`, { template: "growth" });
  await post(`${path}/projects`, { name: "Launch", lead: growth.id });
  const page1 = await publish(stores, owner.business, "Roadmap.html", "<h1>Roadmap</h1>");
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);
    // Home has nothing waiting: no panel and no toggle; the conversation has the full width.
    await expect(page.getByRole("region", { name: "Needs you" })).toHaveCount(0);
    await expect(toolbarPanel(page, false)).toHaveCount(0);

    // An app opens beside the conversation without leaving it.
    await sidebar(page).getByRole("button", { name: "Documents" }).click();
    const documents = page.getByRole("region", { name: "Documents" });
    await expect(documents.getByTestId("panel-title")).toHaveText("Documents");
    await expect(page.getByTestId("place-title")).toHaveText("Home");
    await expect(page.getByLabel("Message Head of Operations")).toBeVisible();

    // A record opens as a further layer; Esc goes back one layer at a time.
    await documents.getByRole("button", { name: /^Roadmap/ }).click();
    const roadmap = page.getByRole("region", { name: "Roadmap" });
    await expect(roadmap.getByTestId("panel-title")).toHaveText("Roadmap");
    await expect(roadmap.getByRole("button", { name: "Back", exact: true })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(documents).toBeVisible();
    await expect(roadmap).toHaveCount(0);
    await documents.getByRole("button", { name: /^Roadmap/ }).click();
    await roadmap.getByRole("button", { name: "Back", exact: true }).click();
    await expect(documents).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(documents).toHaveCount(0);
    await expect(page.getByTestId("panel-title")).toHaveCount(0);

    // A project's overview is open by default; hiding it is remembered for projects only.
    await sidebar(page).getByRole("button", { name: "Launch" }).click();
    const overview = page.getByRole("region", { name: "Launch overview" });
    await expect(overview).toBeVisible();
    await toolbarPanel(page, true).click();
    await expect(overview).toHaveCount(0);

    // A direct chat's desk is closed by default; opening it is remembered for direct chats.
    await sidebar(page).getByRole("button", { name: "Growth" }).click();
    const desk = page.getByRole("region", { name: "Growth's desk" });
    await expect(desk).toHaveCount(0);
    await toolbarPanel(page, false).click();
    await expect(desk).toBeVisible();

    await sidebar(page).getByRole("button", { name: "Launch" }).click();
    await expect(overview).toHaveCount(0);
    await sidebar(page).getByRole("button", { name: "Head of Operations" }).click();
    await expect(page.getByRole("region", { name: "Head of Operations's desk" })).toBeVisible();

    // Remembered across visits, on this device.
    await page.reload();
    await sidebar(page).getByRole("button", { name: "Growth" }).click();
    await expect(desk).toBeVisible();
    await desk.getByRole("button", { name: "Hide side panel", exact: true }).click();
    await expect(desk).toHaveCount(0);
    await sidebar(page).getByRole("button", { name: "Launch" }).click();
    await expect(overview).toHaveCount(0);
    await toolbarPanel(page, false).click();
    await expect(overview).toBeVisible();
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.files.delete(page1.key);
    await stores.dispose();
  }
});
