import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import react from "@vitejs/plugin-react";
import { excalidrawFonts } from "./scripts/excalidraw-fonts.ts";
import { cloudflare } from "@cloudflare/vite-plugin";

export default defineConfig({
  resolve: { alias: { "@": fileURLToPath(new URL("./src/web", import.meta.url)) } },
  plugins: [
    tailwindcss(),
    process.env.ALCHEMY_CLOUDFLARE_VITE_INJECTED === "1"
      ? null
      : cloudflare({
          configPath:
            process.env.DEVYS_CHANNEL_TEST === "1"
              ? "./wrangler.channel.jsonc"
              : "./wrangler.local.jsonc",
          persistState:
            process.env.DEVYS_CHANNEL_TEST === "1" ? { path: ".wrangler/channel-state" } : true,
          viteEnvironment: { name: "ssr" },
        }),
    tanstackStart({ srcDirectory: "src/web", server: { entry: "../worker.ts" } }),
    react(),
    excalidrawFonts(),
  ],
});
