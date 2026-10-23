import { expect, test } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { signIn } from "./helpers.ts";

test("another browser connects with one button and is let in from a signed-in one", async ({
  page,
  browser,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Sam", "Acme");
  const elsewhere = await browser.newContext();
  const stranger = await browser.newContext();
  try {
    await signIn(page, sql, owner.person);

    // Signed out: the Face, one button, nothing to type.
    const phone = await elsewhere.newPage();
    await phone.goto("/");
    const connect = phone.getByRole("button", { name: /^Connect to / });
    await expect(connect).toBeVisible();
    await expect(phone.getByRole("textbox")).toHaveCount(0);
    await connect.click();
    const match = phone.getByLabel("Match");
    await expect(match).toHaveText(/^\S+$/);
    await expect(phone.getByText(/^Allow on /)).toBeVisible();

    // The signed-in browser is asked, showing the same two emoji.
    const prompt = page.getByRole("dialog", { name: /wants to join$/ });
    await expect(prompt).toBeVisible();
    await expect(prompt.getByLabel("Match")).toHaveText((await match.textContent())!);
    await prompt.getByRole("button", { name: "Allow" }).click();
    await expect(prompt).toHaveCount(0);

    // Allowed: the other browser is in, as Sam, on Acme's Home.
    await expect(phone.getByTestId("place-title")).toHaveText("Home", { timeout: 15_000 });
    expect(
      (await sql.row<{ n: number }>(
        "SELECT count(*)::int AS n FROM web_sessions WHERE person_id = $1 AND label LIKE 'Chrome on %'",
        [owner.person],
      ))!.n,
    ).toBe(1);

    // Denied: back to the button, quietly, and still signed out.
    const other = await stranger.newPage();
    await other.goto("/");
    await other.getByRole("button", { name: /^Connect to / }).click();
    await expect(other.getByLabel("Match")).toBeVisible();
    await page
      .getByRole("dialog", { name: /wants to join$/ })
      .getByRole("button", { name: "Deny" })
      .click();
    await expect(other.getByRole("button", { name: /^Connect to / })).toBeVisible({
      timeout: 10_000,
    });
    await expect(other.getByRole("alert")).toHaveCount(0);
    expect((await other.request.get("/api/me")).status()).toBe(401);
  } finally {
    await elsewhere.close();
    await stranger.close();
    await sql.run("DELETE FROM join_requests WHERE name LIKE 'Chrome on %' AND allowed_by IS NULL");
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("signed in with no business: name it, and start", async ({ page }) => {
  const stores = await localStores();
  const { sql } = stores;
  const person = crypto.randomUUID();
  await sql.run("INSERT INTO people (id, display_name) VALUES ($1, 'Robin')", [person]);
  let business: string | undefined;
  try {
    await page.goto("/");
    const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");
    const hash = Array.from(
      new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))),
      (byte) => byte.toString(16).padStart(2, "0"),
    ).join("");
    await sql.run(
      "INSERT INTO sign_in_links (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
      [hash, person],
    );
    await page.goto(`/#signin=${token}`);
    const form = page.getByRole("form", { name: "Name your business" });
    await expect(form).toBeVisible();
    await expect(form.getByRole("textbox")).toHaveCount(2);
    await form.getByLabel("Name").fill("Globex");
    await form.getByLabel("What it does").fill("Repairs and installs garage doors.");
    await form.getByRole("button", { name: "Start" }).click();
    await expect(page.getByTestId("place-title")).toHaveText("Home", { timeout: 15_000 });
    business = (await sql.row<{ business_id: string }>(
      "SELECT business_id FROM memberships WHERE person_id = $1",
      [person],
    ))!.business_id;
    // The starting team is hired with the Chief of Staff: Admin, Finance, Growth and Engineering.
    expect(
      (await sql.row<{ n: number }>(
        "SELECT count(*)::int AS n FROM employees WHERE business_id = $1",
        [business],
      ))!.n,
    ).toBe(5);
  } finally {
    await stores.remove(business ? [{ person, business }] : []);
    if (!business) {
      await sql.run("DELETE FROM sign_in_links WHERE person_id = $1", [person]);
      await sql.run("DELETE FROM web_sessions WHERE person_id = $1", [person]);
      await sql.run("DELETE FROM people WHERE id = $1", [person]);
    }
    await stores.dispose();
  }
});
