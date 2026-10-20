/**
 * A markdown document, edited as rich text and stored as markdown (Milkdown's Crepe, MIT). The
 * caller owns saving; this reports each change and the text the reader selects for a comment.
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
  const latest = useRef({ onChange, onSelect, markdown });
  latest.current = { onChange, onSelect, markdown };

  useEffect(() => {
    const crepe = new Crepe({
      root: root.current!,
      defaultValue: markdown,
      features: { [Crepe.Feature.AI]: false, [Crepe.Feature.TopBar]: false },
    });
    crepe.on((listen) => listen.markdownUpdated((_ctx, next) => latest.current.onChange(next)));
    void crepe.create().then(() => crepe.setReadonly(readOnly));
    const select = () => {
      const selection = window.getSelection();
      // Selecting elsewhere (such as typing the comment itself) keeps the last selection.
      if (!selection?.anchorNode || !root.current?.contains(selection.anchorNode)) return;
      const quote = selection.toString().trim();
      if (!quote) return latest.current.onSelect?.(null);
      const start = latest.current.markdown.indexOf(quote);
      latest.current.onSelect?.({ start, end: start < 0 ? -1 : start + quote.length, quote });
    };
    document.addEventListener("selectionchange", select);
    return () => {
      document.removeEventListener("selectionchange", select);
      void crepe.destroy();
    };
    // A new version replaces the editor; ordinary typing never does.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version]);

  return (
    <div
      ref={root}
      className="devys-markdown size-full overflow-y-auto"
      data-testid="markdown-document"
    />
  );
}
