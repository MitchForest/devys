import { readFileSync } from "node:fs";
import { expect, it } from "vitest";
import { siteCopies } from "./site-copies.ts";

it("the site's shared files are current copies of the web app's originals", () => {
  for (const { source, copy, header } of siteCopies) {
    expect(readFileSync(copy, "utf8"), `${copy} is stale: run bun run site:sync`).toBe(
      header + readFileSync(source, "utf8"),
    );
  }
});
