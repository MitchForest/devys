import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { bearer, insertMessage, sidebar, signIn, stubPosting } from "./helpers.ts";

test("a direct chat is the middle; who answers follows replies and @mentions; reactions show", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Avery", "Acme");
  const growth = { id: owner.team.growth };
  const sent = await stubPosting(page, () => [owner.chiefOfStaff]);
  const direct = `direct:${owner.chiefOfStaff}`;
  try {
    await signIn(page, sql, owner.person);
    await expect(sidebar(page).getByRole("link", { name: "Growth" })).toBeVisible();
    await sidebar(page).getByRole("link", { name: "Chief of Staff" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Chief of Staff");
    const field = page.getByLabel("Message Chief of Staff");
    await expect(field).toBeVisible();

    // An empty direct chat: its employee answers.
    const chip = page.getByTestId("to-names");
    await expect(chip).toHaveAttribute("data-names", "Chief of Staff");

    // The owner's bubble shows at once and the post goes to this chat.
    await field.fill("What is due this week?");
    await page.getByRole("button", { name: "Send" }).click();
    await expect(page.getByText("What is due this week?")).toBeVisible();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.key).toBe(direct);
    expect(sent[0]!.body).toMatchObject({ text: "What is due this week?" });
    expect(sent[0]!.body.id).toMatch(/^[A-Za-z0-9-]{8,64}$/);

    // The Chief of Staff answers and Growth chimes in: Growth spoke last, so Growth answers next.
    const answer = await insertMessage(sql, owner.business, direct, {
      author: `employee:${owner.chiefOfStaff}`,
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

    // Replying to the Chief of Staff's message makes the Chief of Staff the one who answers.
    await page.getByText("The launch post and the pricing page.").click({ button: "right" });
    await page.getByRole("menuitem", { name: "Reply" }).click();
    await expect(page.getByText("Replying to Chief of Staff")).toBeVisible();
    await expect(chip).toHaveAttribute("data-names", "Chief of Staff");
    await field.fill("Start with the pricing page.");
    await page.keyboard.press("Enter");
    await expect.poll(() => sent.length).toBe(2);
    expect(sent[1]!.body).toMatchObject({
      text: "Start with the pricing page.",
      reply_to: answer,
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

test("an employee's answers show as a card under its latest message; a tap answers it and it goes", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Casey", "Acme");
  const sent = await stubPosting(page, () => [owner.chiefOfStaff]);
  const direct = `direct:${owner.chiefOfStaff}`;
  await insertMessage(sql, owner.business, direct, {
    author: `employee:${owner.chiefOfStaff}`,
    text: "An older question.",
    replies: ["Old"],
  });
  const question = await insertMessage(sql, owner.business, direct, {
    author: `employee:${owner.chiefOfStaff}`,
    text: "Should the launch post go out today?",
    replies: ["Today", "Tomorrow"],
  });
  try {
    await signIn(page, sql, owner.person);
    await sidebar(page).getByRole("link", { name: "Chief of Staff" }).click();
    const field = page.getByLabel("Message Chief of Staff");
    await field.fill("Half-written thought");
    // Only the latest employee message offers its answers.
    const replies = page.getByTestId("question-card");
    await expect(replies).toHaveCount(1);
    await expect(replies.getByRole("button")).toHaveText(["AToday", "BTomorrow", "Something else"]);
    await replies.getByRole("button", { name: /Tomorrow/ }).click();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.body).toMatchObject({ text: "Tomorrow", reply_to: question });
    // Sent: the replies go, and what the owner was writing stays.
    await expect(replies).toHaveCount(0);
    await expect(field).toHaveValue("Half-written thought");
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("a turn that stopped is Devys's notice, not the employee's words, with Ask again", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Drew", "Acme");
  const sent = await stubPosting(page, () => [owner.chiefOfStaff]);
  const direct = `direct:${owner.chiefOfStaff}`;
  await insertMessage(sql, owner.business, direct, {
    author: `person:${owner.person}`,
    text: "Find a venue",
  });
  await insertMessage(sql, owner.business, direct, {
    author: "system",
    kind: "event",
    text: "Chief of Staff stopped: it took too long.",
    replies: ["Ask again"],
  });
  try {
    await signIn(page, sql, owner.person);
    await sidebar(page).getByRole("link", { name: "Chief of Staff" }).click();
    await expect(page.getByText("Chief of Staff stopped: it took too long.")).toBeVisible();
    // An event, not a message: no speaker line or bubble of the employee's.
    await expect(page.getByTestId("speaker")).toHaveCount(0);
    const replies = page.getByTestId("question-card");
    await replies.getByRole("button", { name: /Ask again/ }).click();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.body).toMatchObject({ text: "Ask again" });
    await expect(replies).toHaveCount(0);
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("a project opens on its channel; the work's card opens the thread; Back and Start a thread", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Blake", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const growth = { id: owner.team.growth };
  const project = await post<{ id: string }>(`${path}/projects`, {
    name: "Launch",
    goal: "Ship Acme v1",
    lead: owner.chiefOfStaff,
  });
  const workItem = await post<{ id: string }>(`${path}/work`, {
    title: "Write a tagline",
    owner: growth.id,
    project_id: project.id,
  });
  const channel = `project:${project.id}`;
  await insertMessage(sql, owner.business, channel, {
    author: `employee:${owner.chiefOfStaff}`,
    text: "Growth, can you write the tagline?",
  });
  await insertMessage(sql, owner.business, channel, {
    author: "system",
    kind: "card",
    text: "Write a tagline",
    ref: `devys:work/item/${workItem.id}`,
  });
  const sent = await stubPosting(page, () => [growth.id]);
  try {
    await signIn(page, sql, owner.person);

    // Unread messages show on the project in the sidebar, under Projects.
    await expect(sidebar(page).getByRole("heading", { name: "Projects" })).toBeVisible();
    const row = sidebar(page).getByRole("link", { name: /^Launch/ });
    await expect(row).toHaveAccessibleName("Launch, 2 unread");
    await expect(row.getByTestId("unread")).toBeVisible();

    // The project opens on its channel; its details are the header's pill.
    await row.click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    await expect(page.getByRole("region", { name: "Launch overview" })).toHaveCount(0);
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
    await expect(sidebar(page).getByRole("link", { name: /^Launch/ })).toHaveAccessibleName(
      "Launch",
    );

    // The work's card moves the middle into its thread, where the card is pinned.
    await sidebar(page)
      .getByRole("link", { name: /^Launch/ })
      .click();
    await page.getByTestId("work-card").getByText("Write a tagline").click();
    await expect(page.getByTestId("place-title")).toHaveText("Write a tagline");
    const card = page.getByTestId("work-card");
    await expect(card).toHaveCount(1);
    await expect(card.getByText("Growth", { exact: true })).toBeVisible();
    // The thread is an address: a reload keeps it and its Back; the browser's Back leaves it.
    await expect(page).toHaveURL(`/${owner.business}/thread/${workItem.id}`);
    await page.reload();
    await expect(page.getByTestId("place-title")).toHaveText("Write a tagline");
    await page.goBack();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    await page.goForward();
    await expect(page.getByTestId("place-title")).toHaveText("Write a tagline");
    await expect(page.getByRole("button", { name: "Back" })).toBeVisible();
    await expect(page.getByText("Growth, can you write the tagline?")).toHaveCount(0);
    await insertMessage(sql, owner.business, `work:${workItem.id}`, {
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
    expect(sent[0]!.key).toBe(`work:${workItem.id}`);

    // Back returns to the channel.
    await page.getByRole("button", { name: "Back" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
    await expect(page.getByText("Growth, can you write the tagline?")).toBeVisible();

    // Start a thread on a message: a work item owned by its author, in this project.
    await page.getByText("Growth, can you write the tagline?").click({ button: "right" });
    await page.getByRole("menuitem", { name: "Start a thread" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Growth, can you write the tagline?");
    await expect(
      page.getByTestId("work-card").getByText("Chief of Staff", { exact: true }),
    ).toBeVisible();
    expect(
      await sql.row<{ owner_employee_id: string; project_id: string }>(
        "SELECT owner_employee_id, project_id FROM work_items WHERE business_id = $1 AND title = $2",
        [owner.business, "Growth, can you write the tagline?"],
      ),
    ).toEqual({ owner_employee_id: owner.chiefOfStaff, project_id: project.id });
    await page.getByRole("button", { name: "Back" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Launch");
  } finally {
    // Stop the page's polling and read receipts before its business is removed.
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
