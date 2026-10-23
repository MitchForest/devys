import { test, expect } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { localStores } from "../fixtures/local.ts";
import { bearer, signIn } from "./helpers.ts";

test("a work item's card asks one thing at a time: a spend says it is approved on a Mac or iPhone", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Riley", "Acme");
  const post = await bearer(sql, owner.person);
  const work = await post<{ id: string }>(`/api/businesses/${owner.business}/work`, {
    title: "Register the domain",
    owner: owner.chiefOfStaff,
  });
  const grant = await sql.row<{ id: string }>(
    "SELECT id FROM grants WHERE employee_id = $1 AND capability = 'askOwner' AND revoked_at IS NULL",
    [owner.chiefOfStaff],
  );
  // What the employee asked with askOwner, in the work item's thread.
  const ask = async (kind: string, input: unknown, at: string) => {
    const id = randomUUID();
    await sql.run(
      `INSERT INTO decisions (id, kind, business_id, employee_id, grant_id, capability, input,
         input_hash, work_item_id, conversation, requested_at, expires_at)
       VALUES ($1, $2, $3, $4, $5, 'askOwner', $6, $1, $7, $8, $9, now() + interval '1 hour')`,
      [
        id,
        kind,
        owner.business,
        owner.chiefOfStaff,
        grant!.id,
        JSON.stringify(input),
        work.id,
        `work:${work.id}`,
        at,
      ],
    );
    return id;
  };
  await ask(
    "approve",
    {
      kind: "approve",
      action: "Register acme-plumbing.example for one year",
      counterparty: "Namecheap",
      amount: { cents: 1299, currency: "USD" },
      renewal: "Renews yearly at $14.99",
    },
    new Date(Date.now() - 60_000).toISOString(),
  );
  // A second request on the same work (the server refuses one; old data may hold it) waits.
  await ask(
    "take_over",
    { kind: "take_over", reason: "Sign in to the registrar (2FA)" },
    new Date().toISOString(),
  );
  try {
    await signIn(page, sql, owner.person);
    await page.goto(`/${owner.business}/thread/${work.id}`);
    const card = page.getByTestId("work-card");
    await expect(card.getByTestId("work-state")).toHaveText(
      "Your turn: Spend $12.99: Register acme-plumbing.example for one year",
    );
    // The spend shows exactly, and says where it is approved: the web cannot sign it.
    await expect(card.getByTestId("sign-elsewhere")).toHaveText("Approve on your Mac or iPhone");
    await expect(card.getByText("Namecheap", { exact: true })).toBeVisible();
    await expect(card.getByText("$12.99", { exact: true })).toBeVisible();
    await expect(card.getByRole("button", { name: "Approve" })).toHaveCount(0);
    // Only the first ask shows; nothing else asks beside it.
    await expect(page.getByText("Sign in to the registrar (2FA)")).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Open Chrome" })).toHaveCount(0);
    await expect(page.getByTestId("request-card")).toHaveCount(0);
    await page.screenshot({ path: "/tmp/f1-your-turn-spend.png" });
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("a secret request opens the secure entry sheet; the value goes in one post and nowhere else", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Riley", "Acme");
  const post = await bearer(sql, owner.person);
  const work = await post<{ id: string }>(`/api/businesses/${owner.business}/work`, {
    title: "Register the domain",
    owner: owner.chiefOfStaff,
  });
  const grant = await sql.row<{ id: string }>(
    "SELECT id FROM grants WHERE employee_id = $1 AND capability = 'askOwner' AND revoked_at IS NULL",
    [owner.chiefOfStaff],
  );
  const id = randomUUID();
  await sql.run(
    `INSERT INTO decisions (id, kind, business_id, employee_id, grant_id, capability, input,
       input_hash, work_item_id, conversation, expires_at)
     VALUES ($1, 'secret', $2, $3, $4, 'askOwner', $5, $1, $6, $7, now() + interval '1 hour')`,
    [
      id,
      owner.business,
      owner.chiefOfStaff,
      grant!.id,
      JSON.stringify({ kind: "secret", name: "RAMP_CARD", why: "The company card", spend: true }),
      work.id,
      `work:${work.id}`,
    ],
  );
  // The Mac host isn't running beside the dev server: its answer is stood in for here, and what
  // the sheet sent is kept to check.
  const posted: string[] = [];
  await page.route(`**/api/businesses/${owner.business}/secrets`, async (route) => {
    posted.push(route.request().postData() ?? "");
    await route.fulfill({
      status: 201,
      contentType: "application/json",
      body: JSON.stringify({
        secrets: [
          {
            name: "RAMP_CARD",
            kind: "spend",
            added_by: owner.person,
            added_at: new Date().toISOString(),
            last_used_at: null,
          },
        ],
      }),
    });
  });
  try {
    await signIn(page, sql, owner.person);
    await page.goto(`/${owner.business}/thread/${work.id}`);
    const needsYou = page.getByTestId("work-card");
    // The owner reads what it is; the name is the employee's and never shows.
    await expect(needsYou.getByTestId("work-state")).toHaveText("Your turn: Your card");
    await expect(needsYou.getByText("RAMP_CARD")).toHaveCount(0);
    await expect(needsYou.getByRole("button", { name: "Approve" })).toHaveCount(0);
    await needsYou.getByRole("button", { name: "Add card" }).click();
    const sheet = page.getByTestId("secret-entry");
    await expect(sheet.getByText("Add your card")).toBeVisible();
    await expect(sheet.getByText("The company card")).toBeVisible();
    await expect(sheet.getByText("RAMP_CARD")).toHaveCount(0);
    await expect(sheet.getByLabel("Card number")).toHaveAttribute("autocomplete", "cc-number");
    await sheet.getByLabel("Card number").fill("4242 4242 4242 4242");
    await sheet.getByLabel("Expiry").fill("04/31");
    await sheet.getByLabel("Security code", { exact: true }).fill("737");
    await sheet.getByLabel("Name on card").fill("Riley Owner");
    await sheet.getByLabel("Postal code").fill("94107");
    await sheet.getByRole("button", { name: "Save" }).click();
    await expect(sheet).toHaveCount(0);
    expect(posted.map((body) => JSON.parse(body))).toEqual([
      {
        name: "RAMP_CARD",
        kind: "spend",
        card: {
          number: "4242424242424242",
          expiry: "04/31",
          cvc: "737",
          name: "Riley Owner",
          postal: "94107",
        },
      },
    ]);
    // Nothing of it stays in the page or the URL.
    expect(await page.content()).not.toContain("4242424242424242");
    expect(page.url()).not.toContain("4242");
  } finally {
    await stores.remove([owner]);
    await stores.dispose();
  }
});

test("an approval lists its steps and shows its draft; a file request sends the chosen file", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Riley", "Acme");
  const post = await bearer(sql, owner.person);
  const work = await post<{ id: string }>(`/api/businesses/${owner.business}/work`, {
    title: "Ship the waitlist page",
    owner: owner.chiefOfStaff,
  });
  const brand = await post<{ id: string }>(`/api/businesses/${owner.business}/work`, {
    title: "Put the logo on the site",
    owner: owner.chiefOfStaff,
  });
  const grant = await sql.row<{ id: string }>(
    "SELECT id FROM grants WHERE employee_id = $1 AND capability = 'askOwner' AND revoked_at IS NULL",
    [owner.chiefOfStaff],
  );
  const page_ = randomUUID();
  await sql.run(
    `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length)
     VALUES ($1, $2, $1, $3, 'Launch email.html', 'text/html', 20)`,
    [page_, owner.business, `${owner.business}/artifacts/${page_}`],
  );
  const ask = async (kind: string, input: unknown, on = work.id) => {
    const id = randomUUID();
    await sql.run(
      `INSERT INTO decisions (id, kind, business_id, employee_id, grant_id, capability, input,
         input_hash, work_item_id, conversation, expires_at)
       VALUES ($1, $2, $3, $4, $5, 'askOwner', $6, $1, $7, $8, now() + interval '1 hour')`,
      [
        id,
        kind,
        owner.business,
        owner.chiefOfStaff,
        grant!.id,
        JSON.stringify(input),
        on,
        `work:${on}`,
      ],
    );
    return id;
  };
  await ask("approve", {
    kind: "approve",
    action: "Ship the waitlist page",
    counterparty: "github.com/acme/site",
    steps: ["Merge PR #12 at a1b2c3", "Deploy a1b2c3 of site to production"],
    preview: `devys:documents/artifact/${page_}`,
    previewHash: "d".repeat(64),
  });
  const logo = await ask(
    "file",
    { kind: "file", purpose: "Your logo, for the site", accept: ["image/*"] },
    brand.id,
  );
  // The Mac host isn't running beside the dev server: the upload's answer is stood in for.
  const sent: { url: string; type: string | null; size: number }[] = [];
  await page.route(`**/api/businesses/${owner.business}/decisions/${logo}/file*`, async (route) => {
    sent.push({
      url: route.request().url(),
      type: route.request().headers()["content-type"] ?? null,
      size: route.request().postDataBuffer()?.length ?? 0,
    });
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: '{"status":"approved"}',
    });
  });
  try {
    await signIn(page, sql, owner.person);
    await page.goto(`/${owner.business}/thread/${work.id}`);
    const card = page.getByTestId("work-card");
    await expect(card.getByTestId("request-steps").getByRole("listitem")).toHaveText([
      "Merge PR #12 at a1b2c3",
      "Deploy a1b2c3 of site to production",
    ]);
    const draft = card.getByTestId("draft-preview");
    await expect(draft.getByText("Launch email")).toBeVisible();
    await expect(card.getByRole("button", { name: "Approve" })).toBeVisible();
    // The draft opens as its layer.
    await draft.getByRole("button", { name: /Launch email/ }).click();
    await expect(page).toHaveURL(/layer=/);

    await page.goto(`/${owner.business}/thread/${brand.id}`);
    const needsYou = page.getByTestId("work-card");
    await expect(needsYou.getByTestId("work-state")).toHaveText(
      "Your turn: Your logo, for the site",
    );
    await expect(needsYou.getByTestId("choose-file")).toHaveAttribute("accept", "image/*");
    await needsYou.getByTestId("choose-file").setInputFiles({
      name: "logo.png",
      mimeType: "image/png",
      buffer: Buffer.from([137, 80, 78, 71]),
    });
    await expect.poll(() => sent.length).toBe(1);
    expect(sent[0]).toMatchObject({ type: "image/png", size: 4 });
    expect(new URL(sent[0]!.url).searchParams.get("name")).toBe("logo.png");
    await expect(needsYou.getByText("Your logo, for the site")).toHaveCount(0);
  } finally {
    await stores.remove([owner]);
    await stores.dispose();
  }
});
