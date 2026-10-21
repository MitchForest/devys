import { Globe, Hand, Undo2 } from "lucide-react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useRef, useState } from "react";
import { api } from "../app/api.ts";
import type { WorkItem } from "../../work/contract.ts";
import { useBusinessId, useMembers, usePerson, useWork } from "../app/data.ts";
import { useTakeover } from "../app/mutations.ts";
import { takeoverTitle } from "../app/names.ts";
import { useNav } from "../app/navigation.ts";
import { keys, poll, problemOf } from "../app/query.ts";

/** Where the business's browser is and which work drives it. */
const useBrowserStatus = (businessId: string, interval: number) =>
  useQuery({
    queryKey: keys.browser(businessId),
    queryFn: () => api.browserStatus(businessId),
    refetchInterval: interval,
  });
import { DevysButton } from "../design/buttons.tsx";

/** The business's browser while this work item drives it: a line that opens the live view. */
export function BrowserSection({ item }: { item: WorkItem }) {
  const businessId = useBusinessId();
  const nav = useNav();
  const status = useBrowserStatus(businessId, poll).data;
  if (!status?.open || status.driver !== item.id) return null;
  return (
    <button
      type="button"
      onClick={() => nav.openLayer({ kind: "browser", workId: item.id })}
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
  const item = useWork().data?.find((w) => w.id === workId);
  return item ? <BrowserView item={item} /> : null;
}

function BrowserView({ item }: { item: WorkItem }) {
  const businessId = useBusinessId();
  const person = usePerson();
  const members = useMembers();
  const takeoverChange = useTakeover();
  // The live picture, read often while it shows; never while the tab is hidden.
  const status = useBrowserStatus(businessId, 1_200).data;
  const picture = useQuery({
    queryKey: keys.screenshot(businessId),
    queryFn: () => api.browserScreenshot(businessId),
    refetchInterval: 1_200,
  });
  const shot = picture.data ?? null;
  const input = useMutation({
    mutationFn: (action: Parameters<typeof api.browserInput>[1]) =>
      api.browserInput(businessId, action),
  });
  const problem = input.isError
    ? input.error instanceof Error
      ? input.error.message
      : "The page refused that"
    : picture.isError
      ? problemOf(picture.error, "The browser is unavailable")
      : undefined;
  const [text, setText] = useState("");
  const image = useRef<HTMLImageElement>(null);
  const mine = item.taken_over_by !== null && item.taken_over_by === person?.id;
  const takeover = takeoverTitle(item.taken_over_by, person?.id, members);
  const send = (action: Parameters<typeof api.browserInput>[1]) =>
    input.mutateAsync(action).catch(() => undefined);
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
        <DevysButton compact onClick={() => takeoverChange.mutate(item)}>
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
