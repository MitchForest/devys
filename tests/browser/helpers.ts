import { expect, type Page } from "@playwright/test";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { localStores } from "../fixtures/local.ts";

export const base = "http://127.0.0.1:5173";
export const hex = () =>
  Array.from(randomBytes(32), (byte) => byte.toString(16).padStart(2, "0")).join("");
export const hash = (token: string) => createHash("sha256").update(token).digest("hex");
export type Sql = Awaited<ReturnType<typeof localStores>>["sql"];

/** The API as another client of the same person: a bearer session. */
export async function bearer(sql: Sql, person: string) {
  const token = hex();
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [hash(token), person],
  );
  return async <T>(path: string, body: unknown) => {
    const response = await fetch(`${base}${path}`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error(`${path} failed: ${response.status}`);
    return (await response.json()) as T;
  };
}

/** The sidebar: pinned tiles, Projects and Chats, each a conversation. */
export const sidebar = (page: Page) => page.getByRole("navigation", { name: "Sidebar" });

/** Hires an employee from a role template, as the owner's other client would. */
export async function hire(
  sql: Sql,
  owner: { person: string; business: string },
  template: string,
) {
  const post = await bearer(sql, owner.person);
  return await post<{ id: string; name: string }>(`/api/businesses/${owner.business}/employees`, {
    template,
  });
}

/** Settings, from the owner's face at the bottom of the sidebar. */
export async function openSettings(page: Page) {
  await sidebar(page).getByRole("button", { name: "Settings" }).click();
  const settings = page.getByRole("dialog", { name: "Settings" });
  await expect(settings).toBeVisible();
  return settings;
}

/** The header's pill opens who or what the conversation is with: a desk, a project's details. */
export async function openAbout(page: Page) {
  await page.getByRole("button", { name: /^About / }).click();
}

/** Signs in with a one-time link, as the Mac app opens one; the workspace opens on Home. */
export async function signIn(page: Page, sql: Sql, person: string, { phone = false } = {}) {
  const token = hex();
  await sql.run(
    "INSERT INTO sign_in_links (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [hash(token), person],
  );
  await page.goto(`/#signin=${token}`);
  if (phone) {
    // A phone has no sidebar: Home is the conversation with the Chief of Staff, full screen.
    await expect(page.getByLabel("Message Chief of Staff")).toBeVisible();
    return;
  }
  await expect(sidebar(page).getByRole("link", { name: /^Chief of Staff/ })).toBeVisible();
  await expect(page.getByTestId("place-title")).toHaveText("Chief of Staff");
}

/** A message stored as the server stores one, for what employees and events say. */
export async function insertMessage(
  sql: Sql,
  business: string,
  key: string,
  message: {
    author: string;
    text: string;
    kind?: "message" | "event" | "card";
    ref?: string;
    replies?: string[];
    question?: string;
    pickMany?: boolean;
  },
) {
  const id = randomUUID();
  await sql.run(
    "INSERT INTO conversations (business_id, key) VALUES ($1, $2) ON CONFLICT DO NOTHING",
    [business, key],
  );
  await sql.run(
    `INSERT INTO messages (id, business_id, conversation, author, kind, text, ref, client_id, replies,
       question, pick_many)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
    [
      id,
      business,
      key,
      message.author,
      message.kind ?? "message",
      message.text,
      message.ref ?? null,
      randomUUID(),
      message.replies ?? [],
      message.question ?? null,
      message.pickMany ?? false,
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
export async function stubPosting(page: Page, to: () => string[] = () => []) {
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
          reply_to: body.reply_to ?? null,
          mentions: body.mentions ?? [],
          via_voice: false,
          ref: null,
          replies: [],
          question: null,
          pick_many: false,
          created_at: new Date().toISOString(),
        },
        to: to(),
      },
    });
  });
  return sent;
}
