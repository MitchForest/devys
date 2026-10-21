import { existsSync } from "node:fs";
import { createServer } from "node:http";
import { chromium } from "playwright-core";
import { expect, it } from "vitest";
import { sandboxed } from "../src/apps/documents/contract.ts";
import { pageProblem } from "../src/apps/documents/page.ts";

const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

it("a page is refused when it has forms, frames, objects, <base> or a refresh, or is too large", () => {
  expect(pageProblem("<h1>Signups by week</h1><script>draw()</script>")).toBeUndefined();
  expect(pageProblem("")).toMatch(/empty/);
  expect(pageProblem('<form action="https://x"><input></form>')).toMatch(/forms/);
  expect(pageProblem('<iframe src="https://x"></iframe><base href="/">')).toMatch(/frames, <base>/);
  expect(pageProblem('<meta http-equiv="refresh" content="0;url=https://x">')).toMatch(/refresh/);
  expect(pageProblem("x".repeat(600_000))).toMatch(/larger/);
});

it.skipIf(!existsSync(chrome))(
  "a published page runs its scripts but reaches nothing: no network, no Devys, no cookies",
  async () => {
    const requests: string[] = [];
    const server = createServer((request, response) => {
      // The outer page's own favicon request is Chrome's, not the frame's.
      if (request.url !== "/favicon.ico") requests.push(request.url ?? "");
      response.setHeader("set-cookie", "session=secret; Path=/");
      response.end("ok");
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const origin = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
    const browser = await chromium.launch({ executablePath: chrome, headless: true });
    try {
      const page = await browser.newPage();
      await page.goto(origin);
      await page.waitForTimeout(300);
      const before = requests.length;
      // The page tries everything and reports back by postMessage, the one way out.
      const html = `<h1>Report</h1><img src="${origin}/pixel.png"><script>
        const report = {};
        try { report.parent = window.parent.document.cookie; } catch (e) { report.parent = "blocked"; }
        try { report.cookie = document.cookie; } catch (e) { report.cookie = "blocked"; }
        fetch("${origin}/data").then(() => (report.fetch = "reached"), () => (report.fetch = "blocked"))
          .finally(() => parent.postMessage(report, "*"));
      </script>`;
      const report = await page.evaluate(
        (srcdoc) =>
          new Promise((resolve) => {
            addEventListener("message", (event) => resolve(event.data));
            const frame = document.createElement("iframe");
            frame.setAttribute("sandbox", "allow-scripts");
            frame.srcdoc = srcdoc;
            document.body.appendChild(frame);
          }),
        sandboxed(html),
      );
      expect(report).toEqual({ parent: "blocked", cookie: "blocked", fetch: "blocked" });
      await page.waitForTimeout(300);
      expect(requests.slice(before)).toEqual([]);
    } finally {
      await browser.close();
      server.close();
    }
  },
  30_000,
);
