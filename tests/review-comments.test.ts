import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import {
  commentLine,
  hunkHash,
  hunkText,
  reviewBundle,
  type DiffComment,
} from "../src/surfaces/diff.tsx";

const patch = [
  "diff --git a/src/app.ts b/src/app.ts",
  "index 1111111..2222222 100644",
  "--- a/src/app.ts",
  "+++ b/src/app.ts",
  "@@ -1,3 +1,4 @@",
  " const a = 1;",
  "-const b = 2;",
  "+const b = 3;",
  "+const c = 4;",
  " export { a };",
  "@@ -20,2 +21,2 @@ function later() {",
  "-  return 1;",
  "+  return 2;",
  " }",
  "diff --git a/README.md b/README.md",
  "--- a/README.md",
  "+++ b/README.md",
  "@@ -1 +1 @@",
  "-Old title",
  "+New title",
  "\\ No newline at end of file",
  "",
].join("\n");

const comment = (change: Partial<DiffComment>): DiffComment => ({
  path: "src/app.ts",
  side: "additions",
  start: 2,
  end: 3,
  hunk: "0a1b2c3d",
  text: "Keep b at 2.",
  ...change,
});

describe("review comments, in the format the native client writes too", () => {
  it("reads as path, lines, side, base and hunk, then the text", () => {
    expect(commentLine(comment({ base: "9f8e7d6c5b4a39281706" }))).toBe(
      "src/app.ts lines 2–3 (new, base 9f8e7d6c, hunk 0a1b2c3d): Keep b at 2.",
    );
    expect(commentLine(comment({ side: "deletions", start: 2, end: 2 }))).toBe(
      "src/app.ts line 2 (old, hunk 0a1b2c3d): Keep b at 2.",
    );
  });

  it("bundles pending comments into one message under the work's title", () => {
    expect(
      reviewBundle("Add waitlist page", [
        comment({}),
        comment({ path: "README.md", start: 1, end: 1 }),
      ]),
    ).toBe(
      [
        "Review comments on Add waitlist page:",
        "src/app.ts lines 2–3 (new, hunk 0a1b2c3d): Keep b at 2.",
        "README.md line 1 (new, hunk 0a1b2c3d): Keep b at 2.",
      ].join("\n"),
    );
  });

  it("finds the hunk holding the selection's first line on its side", () => {
    expect(hunkText(patch, { path: "src/app.ts", side: "additions", start: 3, end: 3 })).toBe(
      [
        "@@ -1,3 +1,4 @@",
        " const a = 1;",
        "-const b = 2;",
        "+const b = 3;",
        "+const c = 4;",
        " export { a };",
      ].join("\n"),
    );
    expect(hunkText(patch, { path: "src/app.ts", side: "deletions", start: 20, end: 20 })).toBe(
      ["@@ -20,2 +21,2 @@ function later() {", "-  return 1;", "+  return 2;", " }"].join("\n"),
    );
    expect(hunkText(patch, { path: "README.md", side: "additions", start: 1, end: 1 })).toBe(
      ["@@ -1 +1 @@", "-Old title", "+New title", "\\ No newline at end of file"].join("\n"),
    );
    expect(hunkText(patch, { path: "src/other.ts", side: "additions", start: 1, end: 1 })).toBe("");
  });

  it("hashes a hunk as the first 8 hex digits of its SHA-256", async () => {
    const text = hunkText(patch, { path: "README.md", side: "additions", start: 1, end: 1 });
    expect(await hunkHash(text)).toBe(createHash("sha256").update(text).digest("hex").slice(0, 8));
  });
});
