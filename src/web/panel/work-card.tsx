import { Bell, BellRing } from "lucide-react";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { ToolbarIconButton } from "../design/buttons.tsx";
import { EmptyNote } from "../design/primitives.tsx";
import { WorkDetail } from "../pages/work.tsx";
import { PanelBody, PanelHeader } from "./panel.tsx";

/**
 * A thread's permanent view: the work item itself. Who owns it, where it stands, what's next,
 * the decision waiting on the owner, its coding sessions, the live browser and its evidence.
 */
export function WorkCard({ workId, close }: { workId: string; close: () => void }) {
  const { work, followed, actions } = useWorkspace();
  const item = valueOf(work)?.find((w) => w.id === workId);
  const following = followed.includes(workId);
  return (
    <section aria-label="Work item" className="flex h-full flex-col">
      <PanelHeader title={item?.title ?? "Work"} close={close}>
        {item && (
          <ToolbarIconButton
            label={following ? "Following: told at each step. Stop following" : "Follow each step"}
            onClick={() => void actions.setFollowing(item.id, !following)}
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
            {work.status === "loading" ? "Loading…" : "This work item no longer exists."}
          </EmptyNote>
        )}
      </PanelBody>
    </section>
  );
}
