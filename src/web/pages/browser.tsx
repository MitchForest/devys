import { Globe, Hand, Undo2 } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { api, type BrowserStatus, type Commitment } from "../app/api.ts";
import { takeoverTitle } from "../app/names.ts";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";

/** The business's browser while this work item drives it: a line that opens the live view. */
export function BrowserSection({ item }: { item: Commitment }) {
  const { businessId, actions } = useWorkspace();
  const [status, setStatus] = useState<BrowserStatus | null>(null);
  useEffect(() => {
    let live = true;
    const load = () =>
      api
        .browserStatus(businessId)
        .then((next) => live && setStatus(next))
        .catch(() => live && setStatus(null));
    void load();
    const timer = setInterval(() => void load(), 5_000);
    return () => {
      live = false;
      clearInterval(timer);
    };
  }, [businessId]);
  if (!status?.open || status.driver !== item.id) return null;
  return (
    <button
      type="button"
      onClick={() => actions.openLayer({ kind: "browser", workId: item.id })}
      className="flex items-center gap-2 rounded-[10px] px-2 py-1.5 text-left text-detail text-ink-2 hover:bg-sheet-tint hover:text-ink"
    >
      <Globe className="size-3.5 shrink-0 text-ink-3" />
      <span className="truncate">{status.title || status.url}</span>
      <span className="ml-auto shrink-0 text-caption text-ink-3">Watch</span>
    </button>
  );
}

/**
 * The live picture of the business's browser. Take over stops employees acting on this work
 * item; while it's yours, clicks on the picture and typing go to the page (not recorded).
 */
export function BrowserLayer({ workId }: { workId: string }) {
  const { work } = useWorkspace();
  const item = valueOf(work)?.find((w) => w.id === workId);
  return item ? <BrowserView item={item} /> : null;
}

function BrowserView({ item }: { item: Commitment }) {
  const { businessId, person, members, actions } = useWorkspace();
  const [shot, setShot] = useState<{ jpeg: string; width: number; height: number } | null>(null);
  const [status, setStatus] = useState<BrowserStatus | null>(null);
  const [text, setText] = useState("");
  const [problem, setProblem] = useState<string>();
  const image = useRef<HTMLImageElement>(null);
  const mine = item.taken_over_by !== null && item.taken_over_by === person?.id;
  const takeover = takeoverTitle(item.taken_over_by, person?.id, members);
  useEffect(() => {
    let live = true;
    const load = async () => {
      try {
        const [next, picture] = await Promise.all([
          api.browserStatus(businessId),
          api.browserScreenshot(businessId),
        ]);
        if (!live) return;
        setStatus(next);
        setShot(picture);
      } catch (error) {
        if (live) setProblem(error instanceof Error ? error.message : "The browser is unavailable");
      }
    };
    void load();
    const timer = setInterval(() => void load(), 1_200);
    return () => {
      live = false;
      clearInterval(timer);
    };
  }, [businessId]);
  const send = (action: Parameters<typeof api.browserInput>[1]) =>
    api
      .browserInput(businessId, action)
      .catch((error: unknown) =>
        setProblem(error instanceof Error ? error.message : "The page refused that"),
      );
  return (
    <div className="flex h-full flex-col" data-testid="browser-view">
      <div className="flex items-center gap-2 border-b border-hairline px-4 py-2.5">
        <Globe className="size-4 text-ink-3" />
        <span className="truncate text-control font-semibold text-ink">
          {status?.title || "Browser"}
        </span>
        <span className="truncate text-caption text-ink-3">{status?.url}</span>
        <span className="ml-auto" />
        {takeover && <span className="shrink-0 text-caption text-ink-3">{takeover}</span>}
        <DevysButton compact onClick={() => actions.toggleTakeover(item)}>
          {item.taken_over_by === null ? (
            <>
              <Hand /> Take over
            </>
          ) : (
            <>
              <Undo2 /> Hand back
            </>
          )}
        </DevysButton>
      </div>
      <div className="min-h-0 flex-1 overflow-auto bg-sheet-tint p-3">
        {shot ? (
          <img
            ref={image}
            alt={status?.title ?? "The business's browser"}
            src={`data:image/jpeg;base64,${shot.jpeg}`}
            className={mine ? "mx-auto max-w-full cursor-pointer" : "mx-auto max-w-full"}
            onClick={(event) => {
              if (!mine || !image.current) return;
              const box = image.current.getBoundingClientRect();
              void send({
                kind: "click",
                x: Math.round(((event.clientX - box.left) / box.width) * shot.width),
                y: Math.round(((event.clientY - box.top) / box.height) * shot.height),
              });
            }}
          />
        ) : (
          <p className="text-body text-ink-3">{problem ?? "Loading…"}</p>
        )}
      </div>
      {mine ? (
        <form
          className="flex items-center gap-2 border-t border-hairline px-4 py-2.5"
          onSubmit={(event) => {
            event.preventDefault();
            if (!text) return;
            void send({ kind: "type", text }).then(() => setText(""));
          }}
        >
          <input
            value={text}
            onChange={(event) => setText(event.target.value)}
            aria-label="Type into the page"
            placeholder="Click a field above, then type here"
            className="min-w-0 flex-1 rounded-[8px] bg-sheet-tint px-2.5 py-1.5 text-detail text-ink outline-none"
          />
          <DevysButton compact type="submit">
            Type
          </DevysButton>
          <DevysButton compact onClick={() => void send({ kind: "key", key: "Enter" })}>
            Enter
          </DevysButton>
        </form>
      ) : (
        <p className="border-t border-hairline px-4 py-2.5 text-detail text-ink-3">
          Take over to click and type in this browser yourself; until then its employee drives it.
        </p>
      )}
    </div>
  );
}
