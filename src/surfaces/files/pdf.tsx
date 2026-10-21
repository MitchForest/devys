/**
 * A PDF, drawn page by page with pdf.js (Mozilla, Apache-2.0). Dragging on a page marks a region
 * to comment on; regions are reported in PDF points from the page's top left, so they mean the
 * same on every client. Nothing is written into the file.
 */
import { getDocument, GlobalWorkerOptions, type PDFDocumentProxy } from "pdfjs-dist";
import { useEffect, useRef, useState } from "react";

GlobalWorkerOptions.workerSrc = new URL(
  "pdfjs-dist/build/pdf.worker.min.mjs",
  import.meta.url,
).href;

export interface PdfRegion {
  page: number;
  rects: readonly { x: number; y: number; width: number; height: number }[];
}

export function PdfDocument({
  bytes,
  regions = [],
  onRegion,
}: {
  bytes: ArrayBuffer;
  regions?: readonly PdfRegion[];
  onRegion?: (region: PdfRegion) => void;
}) {
  const [pdf, setPdf] = useState<PDFDocumentProxy | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    const task = getDocument({ data: bytes.slice(0) });
    task.promise.then(
      (loaded) => live && setPdf(loaded),
      () => live && setError("This PDF couldn't be read."),
    );
    return () => {
      live = false;
      void task.destroy();
    };
  }, [bytes]);
  if (error) return <p className="p-4 text-body text-ink-2">{error}</p>;
  if (!pdf) return <p className="p-4 text-body text-ink-3">Loading…</p>;
  return (
    <div
      className="flex size-full flex-col items-center gap-3 overflow-y-auto bg-well p-3"
      data-testid="pdf-document"
    >
      {Array.from({ length: pdf.numPages }, (_, index) => (
        <PdfPage
          key={index}
          pdf={pdf}
          number={index + 1}
          regions={regions.filter((region) => region.page === index + 1)}
          onRegion={onRegion}
        />
      ))}
    </div>
  );
}

function PdfPage({
  pdf,
  number,
  regions,
  onRegion,
}: {
  pdf: PDFDocumentProxy;
  number: number;
  regions: readonly PdfRegion[];
  onRegion?: (region: PdfRegion) => void;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const holder = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 612, height: 792, scale: 1 });
  const [drag, setDrag] = useState<{ x: number; y: number; w: number; h: number } | null>(null);
  const [visible, setVisible] = useState(number <= 2);

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => entry?.isIntersecting && setVisible(true),
      {
        rootMargin: "800px",
      },
    );
    if (holder.current) observer.observe(holder.current);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!visible) return;
    let cancelled = false;
    void pdf.getPage(number).then((page) => {
      const width = Math.min(holder.current?.parentElement?.clientWidth ?? 800, 900) - 24;
      const base = page.getViewport({ scale: 1 });
      const scale = width / base.width;
      const viewport = page.getViewport({ scale: scale * devicePixelRatio });
      const target = canvas.current;
      if (!target || cancelled) return;
      target.width = viewport.width;
      target.height = viewport.height;
      setSize({ width: base.width * scale, height: base.height * scale, scale });
      void page.render({ canvas: target, viewport }).promise;
    });
    return () => {
      cancelled = true;
    };
  }, [pdf, number, visible]);

  const point = (event: React.PointerEvent) => {
    const box = holder.current!.getBoundingClientRect();
    return { x: event.clientX - box.left, y: event.clientY - box.top };
  };
  return (
    <div
      ref={holder}
      className="relative shrink-0 bg-white shadow-sm"
      style={{ width: size.width, height: size.height }}
      onPointerDown={(event) => {
        if (!onRegion) return;
        const start = point(event);
        setDrag({ x: start.x, y: start.y, w: 0, h: 0 });
        (event.target as Element).setPointerCapture(event.pointerId);
      }}
      onPointerMove={(event) => {
        if (!drag) return;
        const at = point(event);
        setDrag({ ...drag, w: at.x - drag.x, h: at.y - drag.y });
      }}
      onPointerUp={() => {
        if (drag && Math.abs(drag.w) > 6 && Math.abs(drag.h) > 6)
          onRegion?.({
            page: number,
            rects: [
              {
                x: Math.min(drag.x, drag.x + drag.w) / size.scale,
                y: Math.min(drag.y, drag.y + drag.h) / size.scale,
                width: Math.abs(drag.w) / size.scale,
                height: Math.abs(drag.h) / size.scale,
              },
            ],
          });
        setDrag(null);
      }}
    >
      <canvas ref={canvas} className="size-full" aria-label={`Page ${number}`} />
      {regions
        .flatMap((region) => region.rects)
        .map((rect, index) => (
          <div
            key={index}
            className="pointer-events-none absolute rounded-[3px] border-2 border-indigo bg-indigo/10"
            style={{
              left: rect.x * size.scale,
              top: rect.y * size.scale,
              width: rect.width * size.scale,
              height: rect.height * size.scale,
            }}
          />
        ))}
      {drag && (
        <div
          className="pointer-events-none absolute border-2 border-dashed border-indigo"
          style={{
            left: Math.min(drag.x, drag.x + drag.w),
            top: Math.min(drag.y, drag.y + drag.h),
            width: Math.abs(drag.w),
            height: Math.abs(drag.h),
          }}
        />
      )}
    </div>
  );
}
