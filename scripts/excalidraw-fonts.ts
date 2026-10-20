import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import type { Plugin } from "vite";

const fonts = join(process.cwd(), "node_modules/@excalidraw/excalidraw/dist/prod/fonts");
// Xiaolai covers CJK handwriting at 12 MB; without it Excalidraw draws CJK in a system font.
const skipped = new Set(["Xiaolai"]);

function files(folder: string): string[] {
  return readdirSync(folder, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory()
      ? skipped.has(entry.name)
        ? []
        : files(join(folder, entry.name))
      : [join(folder, entry.name)],
  );
}

/**
 * Serves Excalidraw's fonts from the app at `excalidraw/fonts/…` so the whiteboard never fetches
 * them from its CDN fallback (the Apple bundle allows no network at all).
 */
export function excalidrawFonts(): Plugin {
  return {
    name: "devys-excalidraw-fonts",
    configureServer(server) {
      server.middlewares.use("/excalidraw/fonts/", (request, response, next) => {
        const name = decodeURIComponent((request.url ?? "").split("?")[0]!).replace(/^\/+/, "");
        const file = files(fonts).find((each) => relative(fonts, each) === name);
        if (!file) return next();
        response.setHeader("content-type", "font/woff2");
        response.end(readFileSync(file));
      });
    },
    generateBundle() {
      if (this.environment.name !== "client") return;
      for (const file of files(fonts))
        this.emitFile({
          type: "asset",
          fileName: `excalidraw/fonts/${relative(fonts, file)}`,
          source: readFileSync(file),
        });
    },
  };
}
