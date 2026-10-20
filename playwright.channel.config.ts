import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests/channel",
  workers: 1,
  timeout: 120_000,
  use: { baseURL: "http://127.0.0.1:5180" },
  webServer: {
    command: "DEVYS_CHANNEL_TEST=1 bun run dev:local --host 127.0.0.1 --port 5180",
    url: "http://127.0.0.1:5180/health",
    reuseExistingServer: false,
  },
});
