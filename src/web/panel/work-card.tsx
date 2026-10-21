import { Bell, BellRing } from "lucide-react";
import { useFollowed, useWork } from "../app/data.ts";
import { useFollow } from "../app/mutations.ts";
import { problemOf } from "../app/query.ts";
import { ToolbarIconButton } from "../design/buttons.tsx";
import { EmptyNote } from "../design/primitives.tsx";
import { WorkDetail } from "../pages/work.tsx";
import { PanelBody, PanelHeader } from "./panel.tsx";

/**
 * A thread's permanent view: the work item itself. Who owns it, where it stands, what's next,
 * the decision waiting on the owner, its coding sessions, the live browser and its evidence.
 */
export function WorkCard({ workId, close }: { workId: string; close: () => void }) {
  const work = useWork();
  const followed = useFollowed();
  const follow = useFollow();
  const item = work.data?.find((w) => w.id === workId);
  const following = followed.includes(workId);
  return (
    <section aria-label="Work item" className="flex h-full flex-col">
      <PanelHeader title={item?.title ?? "Work"} close={close}>
        {item && (
          <ToolbarIconButton
            label={following ? "Following: told at each step. Stop following" : "Follow each step"}
            onClick={() => follow.mutate({ workId: item.id, on: !following })}
          >
            {following ? <BellRing /> : <Bell />}
          </ToolbarIconButton>
        )}
      </PanelHeader>
      <PanelBody>
        {item ? (
          <WorkDetail item={item} />
        ) : (
          <EmptyNote>
            {work.isPending
              ? "Loading…"
              : work.isError
                ? problemOf(work.error, "This work item couldn't be loaded.")
                : "This work item no longer exists."}
          </EmptyNote>
        )}
      </PanelBody>
    </section>
  );
}
