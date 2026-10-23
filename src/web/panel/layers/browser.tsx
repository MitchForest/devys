import { Globe, Hand, Undo2 } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { api } from "../../app/api.ts";
import type { WorkItem } from "../../../work/contract.ts";
import { useBusinessId, useMembers, usePerson, useWork } from "../../app/data.ts";
import { useOpenChrome, useTakeover } from "../../app/mutations.ts";
import { takeoverTitle } from "../../app/names.ts";
import { keys, problemOf } from "../../app/query.ts";
import { Button } from "@/components/ui/button";

/**
 * The live picture of the business's browser, to watch. The owner clicks and types in the
 * business's own Chrome on the Mac: Open Chrome takes the work over (which stops employees
 * acting on it) and brings that window to the front; Hand back returns it.
 */
export function BrowserLayer({ workId }: { workId: string }) {
  const item = useWork().data?.find((w) => w.id === workId);
  return item ? <BrowserView item={item} /> : null;
}

function BrowserView({ item }: { item: WorkItem }) {
  const businessId = useBusinessId();
  const person = usePerson();
  const members = useMembers();
  const handBack = useTakeover();
  const openChrome = useOpenChrome();
  // The live picture, read often while it shows; never while the tab is hidden.
  const status = useQuery({
    queryKey: keys.browser(businessId),
    queryFn: () => api.browserStatus(businessId),
    refetchInterval: 1_200,
  }).data;
  const picture = useQuery({
    queryKey: keys.screenshot(businessId),
    queryFn: () => api.browserScreenshot(businessId),
    refetchInterval: 1_200,
  });
  const shot = picture.data ?? null;
  const problem = picture.isError
    ? problemOf(picture.error, "The browser is unavailable")
    : undefined;
  const mine = item.taken_over_by !== null && item.taken_over_by === person?.id;
  const takeover = takeoverTitle(item.taken_over_by, person?.id, members);
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
        {mine ? (
          <Button size="compact" onClick={() => handBack.mutate(item)}>
            <Undo2 /> Hand back
          </Button>
        ) : (
          item.taken_over_by === null && (
            <Button
              size="compact"
              disabled={openChrome.isPending}
              onClick={() => openChrome.mutate(item.id)}
            >
              <Hand /> Open Chrome
            </Button>
          )
        )}
      </div>
      <div className="min-h-0 flex-1 overflow-auto bg-sheet-tint p-3">
        {shot ? (
          <img
            alt={status?.title ?? "The business's browser"}
            src={`data:image/jpeg;base64,${shot.jpeg}`}
            className="mx-auto max-w-full"
          />
        ) : (
          <p className="text-body text-ink-3">{problem ?? "Loading…"}</p>
        )}
      </div>
    </div>
  );
}
