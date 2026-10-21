/**
 * The surface host page the Apple apps load from their bundle into a WKWebView. Native code
 * sends content with `window.devysSurface.show(…)` and hears back through the `devys` script
 * message handler: `ready` once, then the reader's selections and edits. Editors that write
 * whole files (spreadsheets, whiteboards) say `edited`; on Save native code calls `serialize()`
 * for the file. The page makes no network requests and never sees the session token; native
 * code does the networking.
 */
import { createRoot } from "react-dom/client";
import { lazy, Suspense, useEffect, useMemo, useRef, useState } from "react";
import { DiffSurface, type DiffComment, type DiffSelection } from "./diff.tsx";
import { CodeFile } from "./files/code.tsx";
import { MarkdownDocument, type TextSelection } from "./files/markdown.tsx";
import { deckToPptx, isDeck, SlidesEditor } from "./files/slides.tsx";

const SheetEditor = lazy(() =>
  import("./files/sheet.tsx").then((m) => ({ default: m.SheetEditor })),
);
const WhiteboardEditor = lazy(() =>
  import("./files/whiteboard.tsx").then((m) => ({ default: m.WhiteboardEditor })),
);

type SurfaceContent =
  | { kind: "diff"; patch: string; comments?: DiffComment[]; dark?: boolean }
  /**
   * `version` changes when the text is replaced from outside, as after a conflict. Layers are
   * read-only (`readOnly`) unless the owner has taken the work over.
   */
  /** A markdown file; a deck (`isDeck`) edits beside its slides instead. */
  | {
      kind: "markdown";
      name: string;
      markdown: string;
      version: string;
      readOnly?: boolean;
      dark?: boolean;
    }
  | { kind: "code"; name: string; contents: string; dark?: boolean }
  | {
      kind: "sheet";
      name: string;
      base64: string;
      version: string;
      readOnly?: boolean;
      dark?: boolean;
    }
  | { kind: "whiteboard"; json: string; version: string; readOnly?: boolean; dark?: boolean };

type SurfaceMessage =
  | { type: "ready" }
  | { type: "select"; selection: DiffSelection | null }
  | { type: "change"; markdown: string }
  | { type: "deck" }
  | { type: "edited" }
  | { type: "selectText"; selection: TextSelection | null }
  | { type: "rendered"; files: number; milliseconds: number };

declare global {
  interface Window {
    devysSurface?: {
      show(content: SurfaceContent): void;
      /** The edited file: text, or bytes as base64. Null when nothing is edited. */
      serialize(): { text: string } | { base64: string } | null;
      /** A PowerPoint copy of the deck being edited, as base64. */
      exportDeck(): Promise<string | null>;
    };
    webkit?: { messageHandlers?: { devys?: { postMessage(message: SurfaceMessage): void } } };
  }
}

const tell = (message: SurfaceMessage) =>
  window.webkit?.messageHandlers?.devys?.postMessage(message);

const toBase64 = (bytes: ArrayBuffer) => {
  const view = new Uint8Array(bytes);
  let binary = "";
  for (let at = 0; at < view.length; at += 0x8000)
    binary += String.fromCharCode(...view.subarray(at, at + 0x8000));
  return btoa(binary);
};
const fromBase64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0)).buffer;

function Host() {
  const [content, setContent] = useState<SurfaceContent | null>(null);
  const [shownAt, setShownAt] = useState(0);
  // The edited file, written out when native code asks; the deck source for exports.
  const serializer = useRef<(() => string | ArrayBuffer) | null>(null);
  const deckSource = useRef<string | null>(null);
  useEffect(() => {
    window.devysSurface = {
      show: (next) => {
        document.documentElement.classList.toggle("dark", Boolean(next.dark));
        serializer.current = null;
        deckSource.current =
          next.kind === "markdown" && isDeck(next.name, next.markdown) ? next.markdown : null;
        if (deckSource.current !== null) tell({ type: "deck" });
        setShownAt(performance.now());
        setContent(next);
      },
      serialize: () => {
        const written = serializer.current?.();
        if (written === undefined) return null;
        return typeof written === "string" ? { text: written } : { base64: toBase64(written) };
      },
      exportDeck: async () =>
        deckSource.current === null ? null : toBase64(await deckToPptx(deckSource.current)),
    };
    tell({ type: "ready" });
  }, []);
  useEffect(() => {
    if (!content) return;
    // Two frames after React commits, the first screen of the diff has painted. A hidden web
    // view gets no frames, so a timer reports instead.
    let told = false;
    const report = () => {
      if (told) return;
      told = true;
      tell({
        type: "rendered",
        files: document.querySelectorAll("diffs-container").length,
        milliseconds: Math.round(performance.now() - shownAt),
      });
    };
    requestAnimationFrame(() => requestAnimationFrame(report));
    const timer = setTimeout(report, 1_000);
    return () => clearTimeout(timer);
  }, [content, shownAt]);
  const sheetBytes = useMemo(
    () => (content?.kind === "sheet" ? fromBase64(content.base64) : null),
    [content],
  );
  if (!content) return null;
  const dark = content.dark ?? false;
  const readOnly = "readOnly" in content && content.readOnly === true;
  const selectText = (selection: TextSelection | null) => tell({ type: "selectText", selection });
  const edited = (serialize: () => string | ArrayBuffer) => {
    serializer.current = serialize;
    tell({ type: "edited" });
  };
  if (content.kind === "markdown" && isDeck(content.name, content.markdown))
    return (
      <div className="h-dvh">
        <SlidesEditor
          markdown={content.markdown}
          version={content.version}
          readOnly={readOnly}
          onChange={(markdown) => {
            deckSource.current = markdown;
            tell({ type: "change", markdown });
          }}
        />
      </div>
    );
  if (content.kind === "sheet")
    return (
      <div className="h-dvh">
        <Suspense>
          <SheetEditor
            bytes={sheetBytes!}
            name={content.name}
            version={content.version}
            dark={dark}
            readOnly={readOnly}
            onChange={edited}
          />
        </Suspense>
      </div>
    );
  if (content.kind === "whiteboard")
    return (
      <div className="h-dvh">
        <Suspense>
          <WhiteboardEditor
            json={content.json}
            version={content.version}
            dark={dark}
            readOnly={readOnly}
            onChange={edited}
          />
        </Suspense>
      </div>
    );
  if (content.kind === "markdown")
    return (
      <div className="h-dvh">
        <MarkdownDocument
          markdown={content.markdown}
          version={content.version}
          readOnly={readOnly}
          onChange={(markdown) => tell({ type: "change", markdown })}
          onSelect={selectText}
        />
      </div>
    );
  if (content.kind === "code")
    return (
      <div className="h-dvh">
        <CodeFile
          name={content.name}
          contents={content.contents}
          dark={dark}
          onSelect={selectText}
        />
      </div>
    );
  return (
    <div className="h-dvh p-2">
      <DiffSurface
        patch={content.patch}
        comments={content.comments ?? []}
        dark={content.dark ?? false}
        onSelect={(selection) => tell({ type: "select", selection })}
      />
    </div>
  );
}

createRoot(document.getElementById("surface")!).render(<Host />);
