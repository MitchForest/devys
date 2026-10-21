import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { bearer, insertMessage, sidebar, signIn, stubPosting } from "./helpers.ts";

test("a direct chat is the middle; who answers follows replies and @mentions; reactions show", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Avery", "Acme");
  const post = await bearer(sql, owner.person);
  const growth = await post<{ id: string }>(`/api/businesses/${owner.business}/employees`, {
    template: "growth",
  });
  const sent = await stubPosting(page, () => [owner.operations]);
  const direct = `direct:${owner.operations}`;
  try {
    await signIn(page, sql, owner.person);
    await expect(sidebar(page).getByRole("button", { name: "Growth" })).toBeVisible();
    await sidebar(page).getByRole("button", { name: "Head of Operations" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Head of Operations");
    const field = page.getByLabel("Message Head of Operations");
    await expect(field).toBeVisible();

    // An empty direct chat: its employee answers.
    const chip = page.getByTestId("to-names");
    await expect(chip).toHaveAttribute("data-names", "Head of Operations");

    // The owner's bubble shows at once and the post goes to this chat.
    await field.fill("What is due this week?");
    await page.getByRole("button", { name: "Send" }).click();
    await expect(page.getByText("What is due this week?")).toBeVisible();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.key).toBe(direct);
    expect(sent[0]!.body).toMatchObject({ text: "What is due this week?" });
    expect(sent[0]!.body.id).toMatch(/^[A-Za-z0-9-]{8,64}$/);

    // Operations answers and Growth chimes in: Growth spoke last, so Growth answers next.
    const answer = await insertMessage(sql, owner.business, direct, {
      author: `employee:${owner.operations}`,
      text: "The launch post and the pricing page.",
    });
    await insertMessage(sql, owner.business, direct, {
      author: `employee:${growth.id}`,
      text: "I can take the launch post.",
    });
    await expect(page.getByText("I can take the launch post.")).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.getByTestId("speaker").filter({ hasText: "Growth" })).toBeVisible();
    await expect(chip).toHaveAttribute("data-names", "Growth");

    // A reaction shows on the employee's message.
    await page.getByText("The launch post and the pricing page.").click({ button: "right" });
    await page.getByRole("menuitem", { name: "👍" }).click();
    await expect(page.getByLabel("Reacted 👍")).toBeVisible();
    // It is stored for the employee who wrote the message, so it outlives a refresh.
    await expect
      .poll(async () =>
        sql.row<{ emoji: string }>("SELECT emoji FROM app_reactions WHERE target_id = $1", [
          answer,
        ]),
      )
      .toEqual({ emoji: "👍" });

    // Replying to Operations' message makes Operations the one who answers.
    await page.getByText("The launch post and the pricing page.").click({ button: "right" });
    await page.getByRole("menuitem", { name: "Reply" }).click();
    await expect(page.getByText("Replying to Head of Operations")).toBeVisible();
    await expect(chip).toHaveAttribute("data-names", "Head of Operations");
    await field.fill("Start with the pricing page.");
    await page.keyboard.press("Enter");
    await expect.poll(() => sent.length).toBe(2);
    expect(sent[1]!.body).toMatchObject({
      text: "Start with the pricing page.",
      replyTo: answer,
    });

    // @-autocomplete inserts the name and mentions Growth, who then answers.
    await field.pressSequentially("@Gro");
    await page
      .getByRole("listbox", { name: "Mention" })
      .getByRole("option", { name: /Growth/ })
      .click();
    await expect(field).toHaveValue("@Growth ");
    await expect(chip).toHaveAttribute("data-names", "Growth");
    await field.pressSequentially("draft the post too");
    await page.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(3);
    expect(sent[2]!.body).toMatchObject({
      text: "@Growth draft the post too",
      mentions: [growth.id],
    });

    // The chip's picker sends someone else's name as the only mention.
    await page.getByRole("button", { name: "Change who answers" }).click();
    await page.getByRole("menuitem", { name: /^Growth/ }).click();
    await expect(chip).toHaveAttribute("data-names", "Growth");
    await field.fill("Thanks");
    await page.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(4);
    expect(sent[3]!.body).toMatchObject({
      text: "Thanks",
      mentions: [growth.id],
    });
  } finally {
    // Stop the page's polling and read receipts before its business is removed.
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("a project opens on its channel; a hand-off card opens the thread; Back and Start a thread", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Blake", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const growth = await post<{ id: string }>(`${path}/employees`, {
    template: "growth",
  });
  const project = await post<{ id: string }>(`${path}/projects`, {
    name: "Launch",
    goal: "Ship Acme v1",
    lead: owner.operations,
  });
  const task = await post<{ id: string }>(`${path}/work`, {
    title: "Write a tagline",
    owner: growth.id,
    projectId: project.id,
  });
  const channel = `project:${project.id}`;
  await insertMessage(sql, owner.business, channel, {
    author: `employee:${owner.operations}`,
    text: "Growth, can you write the tagline?",
  });
  await insertMessage(sql, owner.business, channel, {
    author: "system",
    kind: "event",
    text: 'Growth took on "Write a tagline".',
    ref: `devys:work/item/${task.id}`,
  });
  const sent = await stubPosting(page, () => [growth.id]);
  try {
    await signIn(page, sql, owner.person);

    // Unread messages show on the project in the sidebar.
    const row = sidebar(page).getByRole("button", { name: /^Launch/ });
    await expect(row).toHaveAccessibleName("Launch, 2 unread");
    await expect(row.getByTestId("unread")).toHaveText("2");

    // The project opens on its channel, with its overview beside it.
    await row.click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    await expect(page.getByRole("region", { name: "Launch overview" })).toBeVisible();
    await expect(page.getByText("Growth, can you write the tagline?")).toBeVisible();
    await expect(page.getByLabel("Message Launch")).toBeVisible();

    // Opening it reads it: the badge clears here and on the server.
    await expect(row.getByTestId("unread")).toHaveCount(0);
    await expect
      .poll(
        async () =>
          (
            await sql.row<{ n: number }>(
              `SELECT count(*)::int AS n FROM messages m WHERE m.business_id = $1 AND m.conversation = $2
                 AND m.seq > (SELECT seen_seq FROM conversation_reads r WHERE r.business_id = $1
                   AND r.conversation = $2 AND r.participant = $3)`,
              [owner.business, channel, `person:${owner.person}`],
            )
          )?.n,
      )
      .toBe(0);
    await page.reload();
    await expect(sidebar(page).getByRole("button", { name: /^Launch/ })).toHaveAccessibleName(
      "Launch",
    );

    // The hand-off card moves the middle into the work item's thread; its card is the panel.
    await sidebar(page)
      .getByRole("button", { name: /^Launch/ })
      .click();
    await page.getByTestId("handoff").click();
    await expect(page.getByTestId("place-title")).toHaveText("Write a tagline");
    await expect(
      page.getByRole("navigation", { name: "Breadcrumb" }).getByRole("button", { name: "Launch" }),
    ).toBeVisible();
    const card = page.getByRole("region", { name: "Work item" });
    await expect(card.getByTestId("panel-title")).toHaveText("Write a tagline");
    await expect(card.getByTestId("task-owner")).toHaveText("Growth");
    await expect(page.getByText("Growth, can you write the tagline?")).toHaveCount(0);
    await insertMessage(sql, owner.business, `work:${task.id}`, {
      author: `employee:${growth.id}`,
      text: "Drafting three options.",
    });
    await expect(page.getByText("Drafting three options.")).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.getByTestId("to-names")).toHaveAttribute("data-names", "Growth");
    await page.getByRole("textbox", { name: "Reply" }).fill("Keep it under six words.");
    await page.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.key).toBe(`work:${task.id}`);

    // Back returns to the channel and its overview.
    await page.getByRole("button", { name: "Back (⌘[)" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    await expect(page.getByText("Growth, can you write the tagline?")).toBeVisible();
    await expect(page.getByRole("region", { name: "Launch overview" })).toBeVisible();

    // Start a thread on a message: a work item owned by its author, in this project.
    await page.getByText("Growth, can you write the tagline?").click({ button: "right" });
    await page.getByRole("menuitem", { name: "Start a thread" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Growth, can you write the tagline?");
    await expect(
      page.getByRole("region", { name: "Work item" }).getByTestId("task-owner"),
    ).toHaveText("Head of Operations");
    expect(
      await sql.row<{ owner_employee_id: string; project_id: string }>(
        "SELECT owner_employee_id, project_id FROM commitments WHERE business_id = $1 AND title = $2",
        [owner.business, "Growth, can you write the tagline?"],
      ),
    ).toEqual({ owner_employee_id: owner.operations, project_id: project.id });
    await page.getByRole("button", { name: "Back (⌘[)" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
  } finally {
    // Stop the page's polling and read receipts before its business is removed.
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
