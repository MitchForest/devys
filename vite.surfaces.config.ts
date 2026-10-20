import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { excalidrawFonts } from "./scripts/excalidraw-fonts.ts";

/**
 * The document surfaces as a static bundle for the Apple apps (.docs/COMPONENTS.md#surfaces):
 * relative paths so it loads from the app bundle, no server.
 */
export default defineConfig({
  base: "./",
  resolve: { alias: { "@": fileURLToPath(new URL("./src/web", import.meta.url)) } },
  plugins: [tailwindcss(), react(), excalidrawFonts()],
  build: {
    outDir:
      process.env.DEVYS_SURFACES_OUT ??
      "apple/Packages/DevysKit/Sources/DevysSurfaces/Resources/surfaces",
    emptyOutDir: true,
    rollupOptions: { input: fileURLToPath(new URL("./surfaces.html", import.meta.url)) },
  },
});
