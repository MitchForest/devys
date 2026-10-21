/**
 * A markdown document, edited as rich text and stored as markdown (Milkdown's Crepe, MIT). The
 * caller owns saving; this reports each change the reader makes (never the editor's own rewrite of
 * what it loaded) and the text the reader selects for a comment.
 */
import { Crepe } from "@milkdown/crepe";
import "@milkdown/crepe/theme/common/style.css";
import "@milkdown/crepe/theme/frame.css";
import { useEffect, useRef } from "react";

/** Selected text and where it sits in the markdown source (first match; -1 if formatting hides it). */
export interface TextSelection {
  start: number;
  end: number;
  quote: string;
}

/** Whether a node sits inside `root`, looking through shadow roots (code views draw in one). */
function within(root: HTMLElement, node: Node | null) {
  for (let at = node; at;) {
    if (root.contains(at)) return true;
    const top = at.getRootNode();
    at = top instanceof ShadowRoot ? top.host : null;
  }
  return false;
}

/**
 * The selected text. A selection inside a shadow root reads empty from the document in some
 * engines: Chromium answers through the shadow root, WebKit through its composed ranges.
 */
function selectedText(selection: Selection, root: HTMLElement) {
  const text = selection.toString();
  if (text) return text;
  const shadows = [...root.querySelectorAll("*")].flatMap((element) =>
    element.shadowRoot ? [element.shadowRoot] : [],
  );
  for (const shadow of shadows) {
    const inner = (shadow as ShadowRoot & { getSelection?: () => Selection | null })
      .getSelection?.()
      ?.toString();
    if (inner) return inner;
  }
  const composed = (
    selection as Selection & {
      getComposedRanges?: (options: { shadowRoots: ShadowRoot[] }) => StaticRange[];
    }
  ).getComposedRanges?.({ shadowRoots: shadows })[0];
  if (!composed || composed.collapsed) return "";
  const range = document.createRange();
  range.setStart(composed.startContainer, composed.startOffset);
  range.setEnd(composed.endContainer, composed.endOffset);
  return range.toString();
}

/**
 * Calls `selected` with the text the reader selects inside `root` (empty when they clear it).
 * Selecting elsewhere, such as typing a comment, keeps the last selection. Returns the stop.
 */
export function watchSelection(root: HTMLElement, selected: (quote: string) => void) {
  const select = () => {
    const selection = window.getSelection();
    if (!selection?.anchorNode || !within(root, selection.anchorNode)) return;
    selected(selectedText(selection, root).trim());
  };
  document.addEventListener("selectionchange", select);
  return () => document.removeEventListener("selectionchange", select);
}

export function MarkdownDocument({
  markdown,
  version,
  readOnly = false,
  onChange,
  onSelect,
}: {
  markdown: string;
  /** Changes when the text is replaced from outside (a reload after a conflict). */
  version: string;
  readOnly?: boolean;
  onChange: (markdown: string) => void;
  onSelect?: (selection: TextSelection | null) => void;
}) {
  const root = useRef<HTMLDivElement>(null);
  const latest = useRef({ onChange, onSelect, markdown, readOnly });
  latest.current = { onChange, onSelect, markdown, readOnly };
  const editor = useRef<{ crepe: Crepe; ready: Promise<unknown> } | null>(null);

  useEffect(() => {
    const element = root.current!;
    const crepe = new Crepe({
      root: element,
      defaultValue: latest.current.markdown,
      features: { [Crepe.Feature.AI]: false, [Crepe.Feature.TopBar]: false },
    });
    // Loading a document rewrites it the editor's way (tables, task lists, images): that is not
    // an edit. Until the owner first acts here, the editor's text is only its normalised copy of
    // what was loaded; afterwards each change is reported, and that copy reports as the loaded
    // text, so undoing back to it is not an edit either.
    const loaded = latest.current.markdown;
    let normalised = loaded;
    let acted = false;
    const act = () => (acted = true);
    const acts = ["beforeinput", "keydown", "paste", "cut", "drop", "pointerdown"] as const;
    for (const type of acts) element.addEventListener(type, act, true);
    crepe.on((listen) =>
      listen.markdownUpdated((_ctx, next) => {
        if (!acted) normalised = next;
        else latest.current.onChange(next === normalised ? loaded : next);
      }),
    );
    const ready = crepe.create().then(() => {
      if (!acted) normalised = crepe.getMarkdown();
      crepe.setReadonly(latest.current.readOnly);
    });
    editor.current = { crepe, ready };
    const stop = watchSelection(element, (quote) => {
      if (!quote) return latest.current.onSelect?.(null);
      const start = latest.current.markdown.indexOf(quote);
      latest.current.onSelect?.({ start, end: start < 0 ? -1 : start + quote.length, quote });
    });
    return () => {
      stop();
      for (const type of acts) element.removeEventListener(type, act, true);
      editor.current = null;
      void crepe.destroy();
    };
    // A new version replaces the editor; ordinary typing never does.
  }, [version]);
  // Taking the work over (or handing it back) unlocks or locks the open editor in place.
  useEffect(() => {
    const current = editor.current;
    void current?.ready.then(() => current.crepe.setReadonly(readOnly));
  }, [readOnly]);

  return (
    <div
      ref={root}
      className="devys-markdown size-full overflow-y-auto"
      data-testid="markdown-document"
    />
  );
}
