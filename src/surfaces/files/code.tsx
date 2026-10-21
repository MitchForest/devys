/**
 * A text or source file, highlighted by Pierre's file view, read-only. The text the reader
 * selects is reported as markdown reports it, so Ask quotes it on every client.
 */
import { File } from "@pierre/diffs/react";
import { useEffect, useRef } from "react";
import { watchSelection, type TextSelection } from "./markdown.tsx";

export function CodeFile({
  name,
  contents,
  dark = false,
  onSelect,
}: {
  name: string;
  contents: string;
  dark?: boolean;
  onSelect?: (selection: TextSelection | null) => void;
}) {
  const root = useRef<HTMLDivElement>(null);
  const latest = useRef({ contents, onSelect });
  latest.current = { contents, onSelect };
  useEffect(
    () =>
      watchSelection(root.current!, (quote) => {
        if (!quote) return latest.current.onSelect?.(null);
        const start = latest.current.contents.indexOf(quote);
        latest.current.onSelect?.({ start, end: start < 0 ? -1 : start + quote.length, quote });
      }),
    [],
  );
  return (
    <div ref={root} className="size-full overflow-auto" data-testid="code-file">
      <File file={{ name, contents }} options={{ themeType: dark ? "dark" : "light" }} />
    </div>
  );
}
