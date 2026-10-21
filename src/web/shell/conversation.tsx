import { useEmployees, useOperations, useProjects } from "../app/data.ts";
import { usePlace } from "../app/navigation.ts";
import { ui, useUi } from "../app/ui.ts";
import { useMain } from "../app/workspace.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { Composer, ConversationView } from "./chat.tsx";

/**
 * The middle of the screen, always a conversation: Home's chat with Operations, a direct
 * chat, a project's channel or a work item's thread.
 */
export function ConversationPane() {
  const place = usePlace();
  const main = useMain();
  const employees = useEmployees();
  const operations = useOperations();
  const projects = useProjects().data;
  const notice = useUi((state) => state.notice);
  const employee =
    place.kind === "direct"
      ? employees.find((e) => e.id === place.employeeId)
      : place.kind === "home"
        ? operations
        : undefined;
  const project = place.kind === "project" ? projects?.find((p) => p.id === place.id) : undefined;
  const label =
    place.kind === "thread"
      ? "Reply"
      : project
        ? `Message ${project.name}`
        : `Message ${employee?.name ?? "the team"}`;
  const empty =
    place.kind === "thread" ? (
      <span className="text-body text-ink-3">Nothing said about this yet.</span>
    ) : project ? (
      <span className="max-w-[360px] text-body text-ink-3">
        Tell the team what {project.name} needs. Each piece of work gets its own thread.
      </span>
    ) : (
      <>
        {employee && <EmployeePortrait employee={employee} size={48} />}
        <span className="max-w-[360px] text-body text-ink-3">
          {place.kind === "home"
            ? `Tell ${employee?.name ?? "Operations"} what you need. @mention anyone to bring them in.`
            : `Message ${employee?.name ?? "them"}. @mention a colleague to bring them in.`}
        </span>
      </>
    );
  return (
    <div className="relative flex h-full flex-col">
      <div className="min-h-0 flex-1">
        <ConversationView conversation={main} className="max-w-[760px]" empty={empty} />
      </div>
      <Composer conversation={main} label={label} className="max-w-[780px]" />
      {notice && (
        <div role="status" className="absolute inset-x-0 top-3 flex justify-center px-4">
          <div className="flex animate-in items-center gap-2.5 rounded-full bg-sheet px-3.5 py-[9px] shadow-raised fade-in slide-in-from-top-2">
            <span className="text-body text-ink">{notice}</span>
            <button
              type="button"
              aria-label="Dismiss"
              className="text-ink-3 hover:text-ink-2"
              onClick={ui.dismissNotice}
            >
              ×
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
