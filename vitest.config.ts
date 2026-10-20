import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      "cloudflare:workers": new URL("./tests/fixtures/platform.ts", import.meta.url).pathname,
    },
  },
  test: {
    include: ["tests/**/*.test.ts"],
    exclude: ["tests/**/*.workers.test.ts", "tests/bun/**"],
    testTimeout: 15_000,
  },
});
