import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { sidebar, signIn } from "./helpers.ts";

test("the owner sees and changes an employee's model on its desk", async ({ page }) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Casey", "Acme");
  const model = async () =>
    (await sql.row<{ model: string }>("SELECT model FROM employees WHERE id = $1", [
      owner.operations,
    ]))!.model;
  // Spend comes from the runtime; a fixed status keeps it deterministic without model calls.
  const usage = {
    input: 1_000,
    output: 400,
    cacheRead: 3_000,
    cacheWrite: 0,
    totalTokens: 4_400,
  };
  await page.route("**/status", (route) =>
    route.fulfill({
      json: {
        state: {
          run: null,
          inbox: [],
          outbox: [],
          usage: {
            models: {
              "gateway/claude-opus-5-5": {
                ...usage,
                cost: {
                  input: 0.1,
                  output: 0.3,
                  cacheRead: 0.02,
                  cacheWrite: 0,
                  total: 0.42,
                },
              },
            },
            tools: {},
          },
        },
      },
    }),
  );
  try {
    await signIn(page, sql, owner.person);
    await sidebar(page).getByRole("button", { name: "Head of Operations" }).click();
    await page.getByRole("button", { name: /^Show side panel/ }).click();
    const desk = page.getByRole("region", {
      name: "Head of Operations's desk",
    });
    await desk.getByText("Model", { exact: true }).first().click();

    // New employees start on the deployment's default model.
    const current = desk.getByTestId("employee-model");
    await expect(current).toHaveText("Claude Opus 5.5");
    await expect(desk.getByText("Spent $0.42 · 75% of input from cache")).toBeVisible();

    // The picker groups models by vendor and changes the model on the server.
    await desk.getByRole("button", { name: /^Change model for / }).click();
    await expect(page.getByRole("group", { name: "OpenAI" })).toBeVisible();
    await expect(page.getByRole("menuitemradio", { name: "Claude Opus 5.5" })).toBeChecked();
    const saved = page.waitForResponse(
      (response) => response.url().endsWith("/model") && response.request().method() === "PUT",
    );
    await page.getByRole("menuitemradio", { name: "GPT-6.1 Sol" }).click();
    expect((await saved).status()).toBe(200);
    await expect(current).toHaveText("GPT-6.1 Sol");
    expect(await model()).toBe("gpt-6.1-sol");
    await expect(page.getByRole("menu")).toBeHidden();

    // A refused change puts the previous model back and says so.
    await page.route("**/model", (route) =>
      route.fulfill({ status: 400, body: "Choose a configured model" }),
    );
    await desk.getByRole("button", { name: /^Change model for / }).click();
    await page.getByRole("menuitemradio", { name: "GPT-6 Luna" }).click();
    await expect(desk.getByRole("alert")).toContainText("couldn't be saved");
    await expect(current).toHaveText("GPT-6.1 Sol");
    expect(await model()).toBe("gpt-6.1-sol");
  } finally {
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
