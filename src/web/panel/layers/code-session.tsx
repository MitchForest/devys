import { useQuery } from "@tanstack/react-query";
import { lazy, Suspense } from "react";
import { api } from "../../app/api.ts";
import { useBusinessId, useWork } from "../../app/data.ts";
import { usePlace } from "../../app/navigation.ts";
import { keys, problemOf } from "../../app/query.ts";
import { useSessions } from "../coding.tsx";

// The session view carries the diff renderer and its highlighter; it loads when opened, in the
// browser only, so the server bundle never carries it.
const SessionView = lazy(() =>
  import.meta.env.SSR
    ? (Promise.resolve({ default: () => null }) as never)
    : import("./code-session-view.tsx"),
);

/**
 * A coding session as a layer, from its ref alone: the business's sessions say which work item
 * it belongs to, so it opens from a project, the Documents of a chat or a card anywhere.
 */
export function CodeSessionLayer({ id }: { id: string }) {
  const businessId = useBusinessId();
  const place = usePlace();
  const coded = useQuery({
    queryKey: keys.codingWork(businessId),
    queryFn: () => api.codingWork(businessId),
  });
  const workId =
    coded.data?.sessions.find((session) => session.id === id)?.work_item_id ??
    (place.kind === "thread" ? place.workId : undefined);
  if (!workId)
    return (
      <p role={coded.isError ? "alert" : undefined} className="p-4 text-body text-ink-3">
        {coded.isPending
          ? "Loading…"
          : problemOf(coded.error, "This coding session is unavailable.")}
      </p>
    );
  return <SessionLayer workId={workId} sessionId={id} />;
}

/** One coding session, read live from its work item's sessions. */
function SessionLayer({ workId, sessionId }: { workId: string; sessionId: string }) {
  const businessId = useBusinessId();
  const sessions = useSessions(businessId, workId);
  const item = useWork().data?.find((w) => w.id === workId);
  const session = sessions.data?.find((each) => each.id === sessionId);
  if (sessions.isError)
    return (
      <p role="alert" className="p-4 text-body text-ink-3">
        {problemOf(sessions.error, "This coding session is unavailable.")}
      </p>
    );
  if (!item || !session) return <p className="p-4 text-body text-ink-3">Loading…</p>;
  return (
    <Suspense fallback={null}>
      <SessionView item={item} session={session} onChanged={() => void sessions.refetch()} />
    </Suspense>
  );
}
