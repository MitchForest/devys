import { test, expect, type Page } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";
import { bearer, sidebar, signIn, stubPosting, type Sql } from "./helpers.ts";

/** A routine stored as the work component stores one. */
async function insertRoutine(
  sql: Sql,
  business: string,
  routine: {
    employee: string;
    project?: string;
    title: string;
    instruction: string;
    trigger: unknown;
    notify: "always" | "when_found";
    state: "proposed" | "active" | "paused";
    next?: string;
    last?: { at: string; result: string };
  },
) {
  const id = randomUUID();
  await sql.run(
    `INSERT INTO routines (id, business_id, employee_id, project_id, title, instruction, trigger,
       notify, state, next_run_at, last_run_at, last_result, created_by)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`,
    [
      id,
      business,
      routine.employee,
      routine.project ?? null,
      routine.title,
      routine.instruction,
      JSON.stringify(routine.trigger),
      routine.notify,
      routine.state,
      routine.next ?? null,
      routine.last?.at ?? null,
      routine.last?.result ?? null,
      `employee:${routine.employee}`,
    ],
  );
  return id;
}

const showPanel = async (page: Page) => {
  const show = page.getByRole("button", { name: /^Show side panel/ });
  if (await show.isVisible()) await show.click();
};

test("routines show on the desk and overview, open read-only, pause and resume, and are proposed in Needs you", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Riley", "Acme");
  const post = await bearer(sql, owner.person);
  const growth = await post<{ id: string }>(`/api/businesses/${owner.business}/employees`, {
    template: "growth",
  });
  const project = await post<{ id: string }>(`/api/businesses/${owner.business}/projects`, {
    name: "Launch",
    lead: growth.id,
  });
  const inTwoDays = new Date(Date.now() + 2 * 86_400_000).toISOString();
  const report = await insertRoutine(sql, owner.business, {
    employee: growth.id,
    project: project.id,
    title: "Weekly signups report",
    instruction:
      "Count last week's signups and post the number with the change from the week before.",
    trigger: { kind: "cron", expression: "0 9 * * 1", timezone: "Europe/London" },
    notify: "always",
    state: "active",
    next: inTwoDays,
    last: { at: new Date(Date.now() - 5 * 86_400_000).toISOString(), result: "42 signups, up 8." },
  });
  const instruction = `Look for supplier replies that need an answer. ${"Skip newsletters and receipts. ".repeat(12)}`;
  const sweep = await insertRoutine(sql, owner.business, {
    employee: growth.id,
    title: "Inbox sweep",
    instruction,
    trigger: { kind: "cron", expression: "0 * * * *", timezone: "America/New_York" },
    notify: "when_found",
    state: "proposed",
  });
  const grant = await sql.row<{ id: string }>(
    "SELECT id FROM grants WHERE employee_id = $1 AND capability = 'routineActivate' AND revoked_at IS NULL",
    [growth.id],
  );
  const decision = randomUUID();
  await sql.run(
    `INSERT INTO decisions (id, business_id, employee_id, grant_id, capability, input, input_hash, expires_at)
     VALUES ($1, $2, $3, $4, 'routineActivate', $5, 'fixture', now() + interval '1 hour')`,
    [decision, owner.business, growth.id, grant!.id, JSON.stringify({ ref: sweep, revision: 1 })],
  );
  // Waiting work with a follow-up says when it looks again.
  const work = await post<{ id: string; revision: number }>(
    `/api/businesses/${owner.business}/work`,
    { title: "Chase the press kit", owner: growth.id },
  );
  await sql.run("UPDATE work_items SET state = 'waiting', wake_at = $2 WHERE id = $1", [
    work.id,
    inTwoDays,
  ]);
  await stubPosting(page);
  try {
    await signIn(page, sql, owner.person);

    // Needs you: the proposal reads as a whole, its long instruction folded.
    const needsYou = page.getByRole("region", { name: "Needs you" });
    const proposal = needsYou.getByTestId("routine-proposal");
    await expect(proposal.getByText("Growth proposes a routine")).toBeVisible();
    await expect(proposal.getByText("Inbox sweep")).toBeVisible();
    await expect(proposal.getByText("Every hour (America/New_York)")).toBeVisible();
    await expect(proposal.getByText("Posts only when something needs attention")).toBeVisible();
    await proposal.getByRole("button", { name: "More" }).click();
    await expect(proposal.getByRole("button", { name: "Less" })).toBeVisible();

    // The desk lists Growth's routines: state, schedule, next run, last result; Pause on the active.
    await sidebar(page).getByRole("link", { name: "Growth" }).click();
    await showPanel(page);
    const desk = page.getByRole("region", { name: "Growth's desk" });
    await expect(desk.getByRole("heading", { name: "Routines · 2" })).toBeVisible();
    const row = desk.getByTestId("routine-row").filter({ hasText: "Weekly signups report" });
    await expect(row).toContainText("Active");
    await expect(row).toContainText(/Next run /);
    await expect(row).toContainText("Last: 42 signups, up 8.");
    const proposed = desk.getByTestId("routine-row").filter({ hasText: "Inbox sweep" });
    await expect(proposed).toContainText("Proposed");
    await expect(proposed.getByRole("button", { name: "Pause" })).toHaveCount(0);
    // The waiting work says when it looks again.
    await expect(desk.getByText(/waiting until /)).toBeVisible();

    // Pause, then Resume, from the desk.
    await row.getByRole("button", { name: "Pause" }).click();
    await expect(row).toContainText("Paused");
    await expect
      .poll(
        async () =>
          (await sql.row<{ state: string }>("SELECT state FROM routines WHERE id = $1", [report]))
            ?.state,
      )
      .toBe("paused");
    await row.getByRole("button", { name: "Resume" }).click();
    await expect(row).toContainText("Active");
    await expect
      .poll(
        async () =>
          (await sql.row<{ state: string }>("SELECT state FROM routines WHERE id = $1", [report]))
            ?.state,
      )
      .toBe("active");

    // The routine's layer is read-only: what, when, who, where; Pause and Ask.
    await row.getByRole("button", { name: /Weekly signups report/ }).click();
    const layer = page.getByRole("region", { name: "Routine" });
    await expect(layer.getByText("Count last week's signups", { exact: false })).toBeVisible();
    await expect(layer.getByText("Always posts")).toBeVisible();
    await expect(layer.getByText("Next run")).toBeVisible();
    await expect(layer.getByText("42 signups, up 8.")).toBeVisible();
    await expect(layer.getByRole("button", { name: "Launch" })).toBeVisible();
    await expect(layer.getByRole("textbox")).toHaveCount(0);
    await layer.getByRole("button", { name: "Pause" }).click();
    await expect(layer.getByRole("button", { name: "Resume" })).toBeVisible();
    await layer.getByRole("button", { name: "Resume" }).click();
    await expect(layer.getByRole("button", { name: "Pause" })).toBeVisible();

    // The project's overview lists only its own routine.
    await sidebar(page).getByRole("link", { name: "Launch" }).click();
    await showPanel(page);
    const overview = page.getByRole("region", { name: "Launch overview" });
    await expect(overview.getByRole("heading", { name: "Routines · 1" })).toBeVisible();
    await expect(overview.getByText("Weekly signups report")).toBeVisible();
    await expect(overview.getByText("Inbox sweep")).toHaveCount(0);

    // Approving the proposal answers that exact request.
    await sidebar(page).getByRole("link", { name: /^Home/ }).click();
    await page
      .getByRole("region", { name: "Needs you" })
      .getByTestId("routine-proposal")
      .getByRole("button", { name: "Approve" })
      .click();
    await expect(page.getByTestId("routine-proposal")).toHaveCount(0);
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
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
