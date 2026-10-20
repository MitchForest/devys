/**
 * Word documents, read-only, through docx-preview (Apache-2.0). Spreadsheets edit in
 * `sheet.tsx`.
 */
import { renderAsync } from "docx-preview";
import { useEffect, useRef, useState } from "react";

export function WordDocument({ bytes }: { bytes: ArrayBuffer }) {
  const root = useRef<HTMLDivElement>(null);
  const [error, setError] = useState(false);
  useEffect(() => {
    if (!root.current) return;
    root.current.replaceChildren();
    renderAsync(bytes, root.current, undefined, {
      inWrapper: true,
      ignoreLastRenderedPageBreak: true,
    }).catch(() => setError(true));
  }, [bytes]);
  if (error) return <p className="p-4 text-body text-ink-2">This document couldn't be read.</p>;
  return <div ref={root} className="size-full overflow-auto bg-well" data-testid="word-document" />;
}
