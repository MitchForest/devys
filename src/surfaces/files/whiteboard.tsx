/**
 * Whiteboards (.docs/PRODUCT_EXPERIENCE.md#files-and-documents): Excalidraw (MIT) editing an
 * `.excalidraw` file, which is JSON, so it saves as text over the revision it was read at. Its
 * fonts come from the app (`excalidraw/fonts/`), never its CDN.
 */
import { Excalidraw, getSceneVersion, serializeAsJSON } from "@excalidraw/excalidraw";
import type { ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types";
import "@excalidraw/excalidraw/index.css";
import { useMemo, useRef } from "react";

declare global {
  interface Window {
    EXCALIDRAW_ASSET_PATH?: string | string[];
  }
}

type Scene = { elements?: unknown[]; appState?: Record<string, unknown>; files?: unknown };

/**
 * Edits a whiteboard. `onChange` fires when the drawing changes (not on scrolling or selecting)
 * and hands over a function that writes the current drawing as `.excalidraw` JSON.
 */
export function WhiteboardEditor({
  json,
  version,
  dark,
  onChange,
}: {
  json: string;
  version: string;
  dark: boolean;
  onChange: (serialize: () => string) => void;
}) {
  window.EXCALIDRAW_ASSET_PATH = new URL("excalidraw/", document.baseURI).href;
  const scene = useMemo(() => {
    try {
      return (json.trim() ? JSON.parse(json) : {}) as Scene;
    } catch {
      return null;
    }
  }, [json]);
  // The scene version last seen, per loaded version of the file (a new one remounts the editor).
  const drawn = useRef<{ version: string; at: number } | null>(null);
  const board = useRef<ExcalidrawImperativeAPI | null>(null);
  if (!scene) return <p className="p-4 text-body text-ink-2">This whiteboard couldn't be read.</p>;
  return (
    <div className="size-full" data-testid="whiteboard-editor">
      <Excalidraw
        key={version}
        theme={dark ? "dark" : "light"}
        initialData={{
          elements: (scene.elements ?? []) as never,
          appState: { ...scene.appState, collaborators: new Map() } as never,
          files: (scene.files ?? {}) as never,
        }}
        excalidrawAPI={(api) => (board.current = api)}
        onChange={(elements, appState, files) => {
          const at = getSceneVersion(elements);
          const before = drawn.current;
          drawn.current = { version, at };
          // The first call for a version reports the drawing as loaded: fit it to the view, since
          // files employees write start wherever they put them. Zooming is not an edit.
          if (before?.version !== version) {
            if (elements.length)
              board.current?.scrollToContent(elements, {
                fitToViewport: true,
                viewportZoomFactor: 0.8,
                maxZoom: 1,
              });
            return;
          }
          if (before.at === at) return;
          onChange(() => serializeAsJSON(elements, appState, files, "local"));
        }}
      />
    </div>
  );
}
