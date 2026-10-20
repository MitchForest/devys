import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

/** The native and web terminals parse the same bytes the same way only on one Ghostty revision. */
it("every libghostty-vt artifact carries the pinned revision", () => {
  const pin = readFileSync("vendor/ghostty/VERSION", "utf8").trim();
  expect(pin).toMatch(/^[0-9a-f]{40}$/);
  const artifacts = [
    "src/surfaces/terminal/vendor/ghostty-vt.wasm",
    ...["macos-arm64", "ios-arm64", "ios-arm64-simulator"].map(
      (slice) =>
        `apple/Packages/DevysTerminal/Vendor/GhosttyVT.xcframework/${slice}/libghostty-vt.a`,
    ),
  ];
  for (const path of artifacts)
    expect(readFileSync(path).includes(Buffer.from(`0.1.0-dev+${pin}`)), path).toBe(true);
});
