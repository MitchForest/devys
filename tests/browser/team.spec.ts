import { test, expect, type Page } from "@playwright/test";
import { createHash, randomBytes } from "node:crypto";
import { localStores } from "../fixtures/local.ts";

const hex = () =>
  Array.from(randomBytes(32), (byte) => byte.toString(16).padStart(2, "0")).join("");
const hash = (token: string) => createHash("sha256").update(token).digest("hex");

/**
 * Model-dependent responses are stubbed so the flows are deterministic: runtimes are idle
 * and posts are recorded instead of reaching a model.
 */
async function stubRuntime(page: Page) {
  const sent: { path: string; body: Record<string, unknown> }[] = [];
  await page.route(/\/status$/, (route) =>
    route.fulfill({ json: { state: { run: null, inbox: [], outbox: [] } } }),
  );
  await page.route(/\/conversations\/[^/]+\/messages$/, async (route) => {
    const request = route.request();
    if (request.method() !== "POST") return route.fallback();
    const path = decodeURIComponent(new URL(request.url()).pathname);
    const body = request.postDataJSON() as Record<string, unknown>;
    sent.push({ path, body });
    await route.fulfill({
      status: 201,
      json: {
        message: {
          id: crypto.randomUUID(),
          conversation: path.split("/").at(-2),
          author: "person:owner",
          kind: "message",
          text: body.text,
          reply_to: null,
          mentions: [],
          via_voice: false,
          ref: null,
          created_at: new Date().toISOString(),
        },
        to: [],
      },
    });
  });
  return sent;
}

async function signIn(
  page: Page,
  sql: { run: (text: string, values: unknown[]) => Promise<number> },
  person: string,
  name: string,
) {
  const token = hex();
  await sql.run(
    "INSERT INTO enrollment_tokens (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [hash(token), person],
  );
  await page.goto("/");
  await page.getByLabel("Enrollment code").fill(token);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("heading", { name: new RegExp(`, ${name}\\.$`) })).toBeVisible();
}

test("the owner hires from a template, edits and retires, and talks to any employee", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Morgan", "Acme");
  const sent = await stubRuntime(page);
  try {
    await signIn(page, sql, owner.person, "Morgan");

    // Hire Growth from its template: name and responsibilities come prefilled.
    await page.getByRole("button", { name: "Hire", exact: true }).click();
    const sheet = page.getByRole("dialog");
    await sheet.getByRole("button", { name: "Growth" }).click();
    await expect(sheet.getByLabel("Name")).toHaveValue("Growth");
    await expect(sheet.getByLabel("Responsibilities")).toHaveValue(/^Grow the business\./);
    await expect(sheet.getByRole("list", { name: "Starting access" })).toContainText(
      "Read public websites",
    );
    await sheet.getByRole("button", { name: "Hire", exact: true }).click();
    await expect(sheet).toBeHidden();
    await expect(page.getByRole("heading", { name: "Growth", level: 1 })).toBeVisible();
    const growth = (await sql.row<{ id: string; role: string }>(
      "SELECT id, role FROM employees WHERE business_id = $1 AND template = 'growth' AND revoked_at IS NULL",
      [owner.business],
    ))!;
    expect(growth.role).toMatch(/^Grow the business\./);

    // The template's responsibilities show on the employee page, and edits are saved.
    await page.getByRole("tab", { name: "Responsibilities" }).click();
    const responsibilities = page.getByLabel("Responsibilities");
    await expect(responsibilities).toHaveValue(growth.role);
    await responsibilities.fill("Own launch marketing for Acme. Report weekly with sources.");
    await page.getByRole("button", { name: "Save responsibilities" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Saved" })).toBeVisible();
    expect(
      (await sql.row<{ role: string }>("SELECT role FROM employees WHERE id = $1", [growth.id]))!
        .role,
    ).toBe("Own launch marketing for Acme. Report weekly with sources.");

    // "Message" opens the DM with Growth in the main pane; the send goes to that DM.
    await page.getByRole("button", { name: "Message", exact: true }).click();
    await expect(page.getByRole("heading", { name: "Growth", level: 1 })).toBeVisible();
    await page.getByLabel("Message Growth").fill("Draft three launch headlines.");
    await page.getByRole("button", { name: "Send" }).click();
    await expect(page.getByText("Draft three launch headlines.")).toBeVisible();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.path).toBe(
      `/api/businesses/${owner.business}/conversations/direct:${growth.id}/messages`,
    );
    expect(sent[0]!.body).toMatchObject({ text: "Draft three launch headlines." });

    // Operations can't be retired.
    await page.getByRole("button", { name: "Team", exact: true }).click();
    await page
      .getByRole("navigation", { name: "Sidebar" })
      .getByRole("button", { name: "Head of Operations" })
      .click();
    await expect(page.getByRole("heading", { name: "Head of Operations", level: 1 })).toBeVisible();
    await expect(page.getByRole("button", { name: "Retire…" })).toHaveCount(0);

    // A space with a purpose and a lead opens on its conversation.
    await page.getByRole("button", { name: "Home", exact: true }).click();
    await page.getByRole("button", { name: "New space" }).click();
    await page.getByLabel("Space name").fill("Launch");
    await page.getByLabel("Purpose").fill("Ship Acme v1");
    await page.getByRole("button", { name: "Create", exact: true }).click();
    await expect(page.getByRole("heading", { name: "Launch", level: 1 })).toBeVisible();
    await expect(page.getByLabel("Message Launch")).toBeVisible();
    await page.getByRole("tab", { name: "Overview" }).click();
    await expect(page.getByTestId("space-lead")).toHaveText("Head of Operations");
    const space = (await sql.row<{ id: string }>(
      "SELECT id FROM spaces WHERE business_id = $1 AND name = 'Launch'",
      [owner.business],
    ))!;

    // A task created there shows in its Work tab.
    await page.getByRole("tab", { name: "Work" }).click();
    await page.getByRole("main").getByRole("button", { name: "New task" }).last().click();
    const dialog = page.getByRole("dialog", { name: "New task" });
    await dialog.getByLabel("Title").fill("Write the launch post");
    await dialog.getByLabel("Owner").selectOption({ label: "Growth" });
    await dialog.getByLabel("Objective").fill("A post the owner approves before Friday");
    await expect(dialog.getByLabel("Space")).toHaveValue(space.id);
    await dialog.getByRole("button", { name: "Create task" }).click();
    await expect(dialog).toBeHidden();
    await expect(page.getByRole("main").getByText("Write the launch post")).toBeVisible();
    const task = (await sql.row<{ id: string; owner_employee_id: string }>(
      "SELECT id, owner_employee_id FROM commitments WHERE business_id = $1 AND title = 'Write the launch post'",
      [owner.business],
    ))!;
    expect(task.owner_employee_id).toBe(growth.id);
    expect(
      await sql.row("SELECT 1 FROM space_items WHERE space_id = $1 AND ref = $2", [
        space.id,
        task.id,
      ]),
    ).toBeTruthy();

    // A Work row opens the item in the right panel; its thread is the work item's.
    await page.getByRole("main").getByText("Write the launch post").click();
    const panel = page.getByRole("region", { name: "Work item" });
    await expect(panel.getByTestId("task-owner")).toHaveText("Growth");
    await expect(panel.getByTestId("panel-title")).toHaveText("Write the launch post");
    await panel.getByLabel("Message about Write the launch post").fill("Start with the outline.");
    await panel.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(2);
    expect(sent[1]!.path).toBe(
      `/api/businesses/${owner.business}/conversations/work:${task.id}/messages`,
    );

    // Retiring Growth hands its open work to the chosen successor.
    await page.getByRole("button", { name: "Team", exact: true }).click();
    await page
      .getByRole("navigation", { name: "Sidebar" })
      .getByRole("button", { name: "Growth" })
      .click();
    await page.getByRole("button", { name: "Retire…" }).click();
    const retire = page.getByRole("dialog", { name: "Retire Growth?" });
    await expect(retire).toContainText("1 open task moves");
    await retire.getByLabel("Hand open work to").selectOption({ label: "Head of Operations" });
    await retire.getByRole("button", { name: "Retire", exact: true }).click();
    await expect(page.getByRole("heading", { name: "Head of Operations", level: 1 })).toBeVisible();
    await expect(
      page.getByRole("navigation", { name: "Sidebar" }).getByRole("button", { name: "Growth" }),
    ).toHaveCount(0);
    expect(
      (await sql.row<{ owner_employee_id: string }>(
        "SELECT owner_employee_id FROM commitments WHERE id = $1",
        [task.id],
      ))!.owner_employee_id,
    ).toBe(owner.operations);
    expect(
      (await sql.row<{ retired: boolean }>(
        "SELECT revoked_at IS NOT NULL AS retired FROM employees WHERE id = $1",
        [growth.id],
      ))!.retired,
    ).toBe(true);
  } finally {
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("Settings → Devices issues a code with its link and lists and revokes devices", async ({
  page,
  context,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Quinn", "Acme");
  await stubRuntime(page);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  // Another device already signed in as Quinn.
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at, label) VALUES ($1, $2, now() + interval '1 day', $3)",
    [hash(hex()), owner.person, "Quinn's iPad"],
  );
  try {
    await signIn(page, sql, owner.person, "Quinn");
    await page.getByRole("button", { name: "Account" }).click();
    await page.getByRole("menuitem", { name: "Settings…" }).click();
    const settings = page.getByRole("dialog", { name: "Settings" });
    await settings.getByRole("button", { name: "Devices", exact: true }).click();

    const devices = settings.getByRole("list", { name: "Devices" });
    await expect(devices.getByRole("listitem")).toHaveCount(3);
    await expect(devices.getByText(/^This device · Added/)).toHaveCount(1);
    await expect(devices.getByText("Quinn's iPad")).toBeVisible();

    const before = (await sql.row<{ n: number }>(
      "SELECT count(*)::int AS n FROM enrollment_tokens WHERE person_id = $1",
      [owner.person],
    ))!.n;
    await settings.getByRole("button", { name: "Add a device" }).click();
    const code = settings.getByTestId("device-code");
    await expect(code).toHaveText(/^[0-9a-f]{64}$/);
    const issued = (await code.textContent())!;
    await expect(settings.getByTestId("device-link")).toHaveText(
      `devys://enroll?server=${encodeURIComponent("http://127.0.0.1:5173")}&code=${issued}`,
    );
    await expect(settings.getByRole("timer")).toHaveText(/^Expires in (10:00|9:5\d)$/);
    expect(
      (await sql.row<{ n: number }>(
        "SELECT count(*)::int AS n FROM enrollment_tokens WHERE person_id = $1",
        [owner.person],
      ))!.n,
    ).toBe(before + 1);
    await settings.getByRole("button", { name: "Copy code" }).click();
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(issued);

    // Revoking signs only that device out.
    await settings.getByRole("button", { name: "Revoke Quinn's iPad" }).click();
    await expect(devices.getByText("Quinn's iPad")).toHaveCount(0);
    expect(
      (await sql.row<{ n: number }>(
        "SELECT count(*)::int AS n FROM web_sessions WHERE person_id = $1 AND label = $2",
        [owner.person, "Quinn's iPad"],
      ))!.n,
    ).toBe(0);
  } finally {
    await stores.remove([owner]);
    await stores.dispose();
  }
});
