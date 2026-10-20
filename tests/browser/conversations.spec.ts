import { test, expect, type Page } from "@playwright/test";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";

const base = "http://127.0.0.1:5173";
const hex = () =>
  Array.from(randomBytes(32), (byte) => byte.toString(16).padStart(2, "0")).join("");
const hash = (token: string) => createHash("sha256").update(token).digest("hex");
type Sql = Awaited<ReturnType<typeof localStores>>["sql"];

/** The API as another client of the same person: a bearer session. */
async function bearer(sql: Sql, person: string) {
  const token = hex();
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [hash(token), person],
  );
  return async <T>(path: string, body: unknown) => {
    const response = await fetch(`${base}${path}`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error(`${path} failed: ${response.status}`);
    return (await response.json()) as T;
  };
}

async function signIn(page: Page, sql: Sql, person: string, name: string) {
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

/** A message stored as the server stores one, for what employees and events say. */
async function insertMessage(
  sql: Sql,
  business: string,
  key: string,
  message: { author: string; text: string; kind?: "message" | "event"; ref?: string },
) {
  const id = randomUUID();
  await sql.run(
    "INSERT INTO conversations (business_id, key) VALUES ($1, $2) ON CONFLICT DO NOTHING",
    [business, key],
  );
  await sql.run(
    `INSERT INTO messages (id, business_id, conversation, author, kind, text, ref, client_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
    [
      id,
      business,
      key,
      message.author,
      message.kind ?? "message",
      message.text,
      message.ref ?? null,
      randomUUID(),
    ],
  );
  // Times are stored to the millisecond; the next message must come strictly after.
  await new Promise((resolve) => setTimeout(resolve, 5));
  return id;
}

/**
 * No model answers: runtimes are idle and posts are recorded and answered as the server
 * would accept them. Reading conversations goes to the real server.
 */
async function stubPosting(page: Page, to: () => string[]) {
  const sent: { key: string; body: Record<string, unknown> }[] = [];
  await page.route(/\/status$/, (route) =>
    route.fulfill({ json: { state: { run: null, inbox: [], outbox: [] } } }),
  );
  await page.route(/\/conversations\/[^/]+\/messages$/, async (route) => {
    const request = route.request();
    if (request.method() !== "POST") return route.fallback();
    const key = decodeURIComponent(new URL(request.url()).pathname.split("/").at(-2)!);
    const body = request.postDataJSON() as Record<string, unknown>;
    sent.push({ key, body });
    await route.fulfill({
      status: 201,
      json: {
        message: {
          id: randomUUID(),
          conversation: key,
          author: "person:owner",
          kind: "message",
          text: body.text,
          reply_to: body.replyTo ?? null,
          mentions: body.mentions ?? [],
          via_voice: false,
          ref: null,
          created_at: new Date().toISOString(),
        },
        to: to(),
      },
    });
  });
  return sent;
}

test("a DM opens in the main pane; the To chip follows replies and @mentions", async ({ page }) => {
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
    await signIn(page, sql, owner.person, "Avery");
    const dms = page.getByRole("group", { name: "Direct messages" });
    await expect(dms.getByRole("button", { name: "Growth" })).toBeVisible();
    await dms.getByRole("button", { name: "Head of Operations" }).click();
    await expect(page.getByRole("heading", { name: "Head of Operations", level: 1 })).toBeVisible();
    const field = page.getByLabel("Message Head of Operations");
    await expect(field).toBeVisible();

    // An empty DM: its employee answers.
    const chip = page.getByTestId("to-names");
    await expect(chip).toHaveText("Head of Operations");

    // The owner's bubble shows at once and the post goes to this DM.
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
    await expect(page.getByText("I can take the launch post.")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId("speaker").filter({ hasText: "Growth" })).toBeVisible();
    await expect(chip).toHaveText("Growth");

    // Replying to Operations' message makes Operations the one who answers.
    await page.getByText("The launch post and the pricing page.").click({ button: "right" });
    await page.getByRole("menuitem", { name: "Reply" }).click();
    await expect(page.getByText("Replying to Head of Operations")).toBeVisible();
    await expect(chip).toHaveText("Head of Operations");
    await field.fill("Start with the pricing page.");
    await page.keyboard.press("Enter");
    await expect.poll(() => sent.length).toBe(2);
    expect(sent[1]!.body).toMatchObject({ text: "Start with the pricing page.", replyTo: answer });

    // @-autocomplete inserts the name and mentions Growth, who then answers.
    await field.pressSequentially("@Gro");
    await page
      .getByRole("listbox", { name: "Mention" })
      .getByRole("option", { name: /Growth/ })
      .click();
    await expect(field).toHaveValue("@Growth ");
    await expect(chip).toHaveText("Growth");
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
    await expect(chip).toHaveText("Growth");
    await field.fill("Thanks");
    await page.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(4);
    expect(sent[3]!.body).toMatchObject({ text: "Thanks", mentions: [growth.id] });
  } finally {
    // Stop the page's polling and read receipts before its business is removed.
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("a space opens on its conversation; a hand-off card opens the work item's thread", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Blake", "Acme");
  const post = await bearer(sql, owner.person);
  const path = `/api/businesses/${owner.business}`;
  const growth = await post<{ id: string }>(`${path}/employees`, { template: "growth" });
  const space = await post<{ id: string }>(`${path}/spaces`, {
    name: "Launch",
    purpose: "Ship Acme v1",
    lead: owner.operations,
  });
  const task = await post<{ id: string }>(`${path}/work`, {
    title: "Write a tagline",
    owner: growth.id,
  });
  await insertMessage(sql, owner.business, `space:${space.id}`, {
    author: `employee:${owner.operations}`,
    text: "Growth, can you write the tagline?",
  });
  await insertMessage(sql, owner.business, `space:${space.id}`, {
    author: "system",
    kind: "event",
    text: 'Growth took on "Write a tagline".',
    ref: task.id,
  });
  const sent = await stubPosting(page, () => [growth.id]);
  try {
    await signIn(page, sql, owner.person, "Blake");

    // Unread messages show on the space in the sidebar.
    const spaces = page.getByRole("group", { name: "Spaces" });
    const row = spaces.getByRole("button", { name: /^Launch/ });
    await expect(row).toHaveAccessibleName("Launch, 2 unread");
    await expect(row.getByTestId("unread")).toHaveText("2");

    // The space opens on its conversation, with its tabs.
    await row.click();
    await expect(page.getByRole("heading", { name: "Launch", level: 1 })).toBeVisible();
    const tabs = page.getByRole("tablist", { name: "Space" });
    for (const tab of ["Conversation", "Overview", "Work", "Files"])
      await expect(tabs.getByRole("tab", { name: tab })).toBeVisible();
    await expect(tabs.getByRole("tab", { name: "Conversation" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
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
              [owner.business, `space:${space.id}`, `person:${owner.person}`],
            )
          )?.n,
      )
      .toBe(0);
    await page.reload();
    await expect(
      page.getByRole("group", { name: "Spaces" }).getByRole("button", { name: /^Launch/ }),
    ).toHaveAccessibleName("Launch");

    // The hand-off card opens the work item, with its own thread, in the right panel.
    await page
      .getByRole("group", { name: "Spaces" })
      .getByRole("button", { name: /^Launch/ })
      .click();
    await page.getByTestId("handoff").click();
    const panel = page.getByRole("region", { name: "Work item" });
    await expect(panel.getByTestId("panel-title")).toHaveText("Write a tagline");
    await expect(panel.getByTestId("task-owner")).toHaveText("Growth");
    await insertMessage(sql, owner.business, `work:${task.id}`, {
      author: `employee:${growth.id}`,
      text: "Drafting three options.",
    });
    await expect(panel.getByText("Drafting three options.")).toBeVisible({ timeout: 10_000 });
    await expect(panel.getByTestId("to-names")).toHaveText("Growth");
    await panel.getByLabel("Message about Write a tagline").fill("Keep it under six words.");
    await panel.getByRole("button", { name: "Send" }).click();
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]!.key).toBe(`work:${task.id}`);
    // The space's conversation stays in the main pane beside it.
    await expect(page.getByText("Growth, can you write the tagline?")).toBeVisible();
  } finally {
    // Stop the page's polling and read receipts before its business is removed.
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
