// Copies files the marketing site shares with the web app into site/. The web app
// owns the originals; tests/site.test.ts fails while a copy differs.
import { readFileSync, writeFileSync } from "node:fs";
import { siteCopies } from "../tests/site-copies.ts";

for (const { source, copy, header } of siteCopies) {
  writeFileSync(copy, header + readFileSync(source, "utf8"));
  console.log(`${source} → ${copy}`);
}
