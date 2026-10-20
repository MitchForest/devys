import { execFileSync } from "node:child_process";
/** A reused dev server still needs newly added migrations before browser fixtures run. */
export default function setup() {
  execFileSync("bun", ["scripts/db.ts", "ensure"], { stdio: "pipe" });
}
