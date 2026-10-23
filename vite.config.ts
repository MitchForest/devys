import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import react from "@vitejs/plugin-react";
import { excalidrawFonts } from "./scripts/excalidraw-fonts.ts";
import { cloudflare } from "@cloudflare/vite-plugin";

/**
 * A development server pointed at its own Mac host and Workers state (`bun run scenario`):
 * `DEVYS_DEV_VARS` is a JSON object of Worker vars (the host's address, token and home) and
 * `DEVYS_DEV_STATE` the state folder, both passed in the environment, never written to a file.
 */
const devVars = process.env.DEVYS_DEV_VARS
  ? (JSON.parse(process.env.DEVYS_DEV_VARS) as Record<string, string>)
  : undefined;
const channelTest = process.env.DEVYS_CHANNEL_TEST === "1";

export default defineConfig({
  resolve: { alias: { "@": fileURLToPath(new URL("./src/web", import.meta.url)) } },
  plugins: [
    tailwindcss(),
    process.env.ALCHEMY_CLOUDFLARE_VITE_INJECTED === "1"
      ? null
      : cloudflare({
          configPath: channelTest ? "./wrangler.channel.jsonc" : "./wrangler.local.jsonc",
          persistState: channelTest
            ? { path: ".wrangler/channel-state" }
            : process.env.DEVYS_DEV_STATE
              ? { path: process.env.DEVYS_DEV_STATE }
              : true,
          ...(devVars ? { config: (config) => ({ vars: { ...config.vars, ...devVars } }) } : {}),
          viteEnvironment: { name: "ssr" },
        }),
    tanstackStart({ srcDirectory: "src/web", server: { entry: "../worker.ts" } }),
    react(),
    excalidrawFonts(),
  ],
});
