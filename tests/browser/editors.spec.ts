import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join, normalize } from "node:path";
import { expect, test, type Page } from "@playwright/test";
import { read, utils, write } from "xlsx";

// The surfaces bundle the Apple apps load, served as files: what native shows, the web shows.
const bundle = join(process.cwd(), "test-results/surfaces-bundle");
const origin = "http://surfaces.test";
const types: Record<string, string> = {
  html: "text/html",
  js: "text/javascript",
  css: "text/css",
  wasm: "application/wasm",
  woff2: "font/woff2",
  json: "application/json",
};

test.beforeAll(() => {
  execFileSync("bun", ["run", "surfaces:build"], {
    env: { ...process.env, DEVYS_SURFACES_OUT: bundle },
    stdio: "ignore",
  });
});

async function openSurface(page: Page) {
  const elsewhere: string[] = [];
  await page.route("**/*", async (route) => {
    const url = new URL(route.request().url());
    if (url.origin !== origin) {
      elsewhere.push(url.href);
      return route.abort();
    }
    const file = normalize(join(bundle, decodeURIComponent(url.pathname)));
    if (!file.startsWith(bundle) || !existsSync(file)) return route.fulfill({ status: 404 });
    await route.fulfill({
      body: readFileSync(file),
      contentType: types[file.split(".").at(-1)!] ?? "application/octet-stream",
    });
  });
  await page.addInitScript(() => {
    const seen: unknown[] = [];
    Object.assign(window, {
      seen,
      webkit: { messageHandlers: { devys: { postMessage: (m: unknown) => seen.push(m) } } },
    });
  });
  await page.goto(`${origin}/surfaces.html`);
  await expect.poll(() => messages(page)).toContainEqual({ type: "ready" });
  return elsewhere;
}

const messages = (page: Page) =>
  page.evaluate(() => (window as unknown as { seen: unknown[] }).seen);

test("a spreadsheet edits in the surface and saves as xlsx with its formulas", async ({ page }) => {
  const elsewhere = await openSurface(page);
  const book = utils.book_new();
  const sheet = utils.aoa_to_sheet([["Cost"], [12], [30]]);
  sheet.A4 = { t: "n", v: 42, f: "SUM(A2:A3)" };
  sheet["!ref"] = "A1:A4";
  utils.book_append_sheet(book, sheet, "Budget");
  const base64 = Buffer.from(write(book, { type: "array", bookType: "xlsx" })).toString("base64");
  await page.evaluate((content) => window.devysSurface!.show(content), {
    kind: "sheet" as const,
    name: "budget.xlsx",
    base64,
    version: "1",
  });
  const editor = page.getByTestId("sheet-editor");
  await expect(editor.locator("[title*='not cell styling']")).toHaveCount(1);
  // Drawn (the sheet tab shows and the loading skeleton is gone), and opening it is not an edit.
  await expect(editor.getByText("Budget", { exact: true })).toBeVisible({ timeout: 30_000 });
  await expect(editor.locator('[aria-busy="true"]')).toHaveCount(0);
  expect(await messages(page)).not.toContainEqual({ type: "edited" });
  // Click B2 (the grid starts below the toolbar and formula bar), type over it, commit.
  const grid = await editor.evaluate((root) => {
    const canvases = [...root.querySelectorAll("canvas")].map((c) => c.getBoundingClientRect());
    const largest = canvases.sort((a, b) => b.width * b.height - a.width * a.height)[0]!;
    return { x: largest.x, y: largest.y };
  });
  await page.mouse.click(grid.x + 46 + 88 + 40, grid.y + 20 + 24 + 12);
  await page.keyboard.type("Total cost");
  await page.keyboard.press("Enter");
  await expect.poll(() => messages(page)).toContainEqual({ type: "edited" });
  const saved = await page.evaluate(() => window.devysSurface!.serialize());
  expect(saved && "base64" in saved).toBe(true);
  const out = read(Buffer.from((saved as { base64: string }).base64, "base64"), {
    cellFormula: true,
  }).Sheets.Budget!;
  expect(out.B2?.v).toBe("Total cost");
  expect(out.A1?.v).toBe("Cost");
  expect(out.A4!.f).toBe("SUM(A2:A3)");
  expect(elsewhere).toEqual([]);
});

test("a markdown deck shows its slides and exports PowerPoint", async ({ page }) => {
  const elsewhere = await openSurface(page);
  await page.evaluate(() =>
    window.devysSurface!.show({
      kind: "markdown",
      name: "launch.md",
      markdown: "---\nmarp: true\n---\n\n# Launch\n\n---\n\n## Plan\n\n- Ship it\n",
      version: "1",
    }),
  );
  await expect.poll(() => messages(page)).toContainEqual({ type: "deck" });
  const slides = page.frameLocator('[data-testid="slides-preview"]');
  await expect(slides.locator("section")).toHaveCount(2);
  await page
    .getByLabel("Deck source")
    .fill("---\nmarp: true\n---\n\n# Launch\n\n---\n\n# Two\n\n---\n\n# Three\n");
  await expect(slides.locator("section")).toHaveCount(3);
  await expect
    .poll(() => messages(page))
    .toContainEqual(expect.objectContaining({ type: "change" }));
  const pptx = await page.evaluate(() => window.devysSurface!.exportDeck());
  expect(Buffer.from(pptx!, "base64").subarray(0, 2).toString()).toBe("PK");
  expect(elsewhere).toEqual([]);
});

test("a whiteboard draws in the surface and saves as Excalidraw JSON", async ({ page }) => {
  const elsewhere = await openSurface(page);
  await page.evaluate(() =>
    window.devysSurface!.show({ kind: "whiteboard", json: "", version: "1" }),
  );
  const editor = page.getByTestId("whiteboard-editor");
  await expect(editor.locator("canvas").first()).toBeVisible({ timeout: 30_000 });
  await page.getByTitle(/Rectangle/).click();
  const box = (await editor.boundingBox())!;
  await page.mouse.move(box.x + box.width / 2 - 80, box.y + box.height / 2 - 60);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 + 80, box.y + box.height / 2 + 60, { steps: 8 });
  await page.mouse.up();
  await expect.poll(() => messages(page)).toContainEqual({ type: "edited" });
  const saved = (await page.evaluate(() => window.devysSurface!.serialize())) as { text: string };
  const scene = JSON.parse(saved.text) as { type: string; elements: { type: string }[] };
  expect(scene.type).toBe("excalidraw");
  expect(scene.elements.map((e) => e.type)).toContain("rectangle");
  expect(elsewhere).toEqual([]);
});
