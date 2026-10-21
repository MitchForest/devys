import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { randomUUID, randomBytes, createHash } from "node:crypto";

test("enrollment is single-use; downloads and sessions enforce business isolation and revocation", async ({
  page,
  browser,
  request,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const alex = await stores.owner("Alex", "Acme");
  const other = await stores.owner("Other owner", "Elsewhere");
  const artifact = randomUUID(),
    ownArtifact = randomUUID();
  const token = Array.from(randomBytes(32), (byte) => byte.toString(16).padStart(2, "0")).join("");
  const hash = createHash("sha256").update(token).digest("hex");
  await sql.run(
    "INSERT INTO enrollment_tokens (token_hash,person_id,expires_at) VALUES ($1,$2,now() + interval '1 hour')",
    [hash, alex.person],
  );
  await sql.run(
    "INSERT INTO artifacts (id,business_id,operation_id,object_key,filename,content_type,byte_length) VALUES ($1,$2,'fixture',$3,'private.txt','text/plain',4)",
    [artifact, other.business, `${other.business}/private`],
  );
  await stores.files.put(`${alex.business}/download.txt`, "saved in R2");
  await sql.run(
    "INSERT INTO artifacts (id,business_id,operation_id,object_key,filename,content_type,byte_length) VALUES ($1,$2,'own-fixture',$3,'download.txt','text/plain',11)",
    [ownArtifact, alex.business, `${alex.business}/download.txt`],
  );
  const mine = `/api/businesses/${alex.business}`;
  const theirs = `/api/businesses/${other.business}`;
  try {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Welcome to Devys" })).toBeVisible();
    expect((await request.get("/api/me")).status()).toBe(401);
    await page.getByLabel("Enrollment code").fill(token);
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(
      page.getByRole("navigation", { name: "Sidebar" }).getByRole("button", { name: /^Home/ }),
    ).toBeVisible();
    await expect(page.getByLabel("Message Head of Operations")).toBeVisible();
    await page.getByRole("button", { name: "Account" }).click();
    await page.getByRole("menuitem", { name: "Apps & connections…" }).click();
    const settings = page.getByRole("dialog", { name: "Settings" });
    await expect(settings.getByRole("region", { name: "Google Drive" })).toBeVisible();
    await expect(settings.getByText("Google Drive setup is pending.")).toBeVisible();
    await expect(page.getByText("private.txt")).toHaveCount(0);
    await page.keyboard.press("Escape");
    // Another business's records never show, in its Documents app either.
    await page
      .getByRole("navigation", { name: "Sidebar" })
      .getByRole("button", { name: "Documents" })
      .click();
    await expect(page.getByRole("region", { name: "Documents" })).toBeVisible();
    await expect(page.getByText("private.txt")).toHaveCount(0);
    const status = (path: string) =>
      page.evaluate(async (target) => (await fetch(target)).status, path);
    expect(await status(`${mine}/artifacts/${artifact}`)).toBe(404);
    expect(await status(`${theirs}/artifacts/${artifact}`)).toBe(404);
    expect(await status(theirs)).toBe(404);
    const download = await page.evaluate(async (path) => {
      const response = await fetch(path);
      return { status: response.status, text: await response.text() };
    }, `${mine}/artifacts/${ownArtifact}`);
    expect(download).toEqual({ status: 200, text: "saved in R2" });
    const exported = await page.evaluate(
      async (path) => (await fetch(path)).text(),
      `${mine}/export`,
    );
    expect(exported).toContain('"kind":"complete"');
    expect(exported).toContain('"name":"Acme"');
    expect(exported).not.toContain("private.txt");
    const cookies = await page.context().cookies();
    expect(
      (
        await request.post(`${mine}/connections/google/disconnect`, {
          headers: {
            origin: "https://attacker.invalid",
            cookie: cookies.map((item) => `${item.name}=${item.value}`).join("; "),
          },
        })
      ).status(),
    ).toBe(403);
    const other = await browser.newContext();
    const consumed = await other.request.post("http://127.0.0.1:5173/api/enroll", {
      headers: { origin: "http://127.0.0.1:5173" },
      data: { token },
    });
    expect(consumed.status()).toBe(401);
    await other.close();
    await page.screenshot({
      path: "test-results/private-workspace-desktop.png",
      fullPage: true,
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({
      path: "test-results/private-workspace-mobile.png",
      fullPage: true,
    });
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
    await sql.run("UPDATE people SET revoked_at=now() WHERE id=$1", [alex.person]);
    expect(await status("/api/me")).toBe(401);
  } finally {
    await stores.remove([alex, other]);
    await stores.files.delete(`${alex.business}/download.txt`);
    await stores.dispose();
  }
});
