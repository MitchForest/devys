import { fileURLToPath } from "node:url";
import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import { loadEnv } from "vite";
const modelKey =
  process.env.DEVYS_LIVE_MODEL === "1"
    ? (process.env.DEVYS_MODEL_GATEWAY_KEY ??
      loadEnv("test", process.cwd(), "").DEVYS_MODEL_GATEWAY_KEY ??
      "")
    : "";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./tests/wrangler.jsonc" },
      miniflare: {
        bindings: { DEVYS_MODEL_GATEWAY_KEY: modelKey },
      },
    }),
  ],
  // pg's CommonJS requires resolve without the workerd condition in the test bundler:
  // point them at the builds workerd uses (production bundling resolves these itself).
  resolve: {
    alias: {
      "pg-protocol": "pg-protocol/dist/index.js",
      "pg-cloudflare": fileURLToPath(import.meta.resolve("pg-cloudflare/package.json")).replace(
        "package.json",
        "dist/index.js",
      ),
    },
  },
  test: {
    include: ["tests/**/*.workers.test.ts"],
    globalSetup: ["tests/setup/database.ts"],

    testTimeout: 30_000,
    // ctx.abort deliberately breaks the output gate in the crash-recovery test.
    // All other unhandled errors remain failures.
    onUnhandledError(error) {
      if (
        error.message === "Injected interruption after side effect" &&
        "durableObjectReset" in error &&
        error.durableObjectReset === true
      )
        return false;
    },
  },
});
