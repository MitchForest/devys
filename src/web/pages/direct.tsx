import { UserRound } from "lucide-react";
import { moodOf, templateTitle } from "../app/names.ts";
import { useWorkspace } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { EmptyNote, PageBody } from "../design/primitives.tsx";
import { Composer, ConversationView } from "../shell/chat.tsx";

/** A DM with one employee, in the main pane: their face, the conversation and the composer. */
export function DirectPage({ employeeId }: { employeeId: string }) {
  const state = useWorkspace();
  const { employees, main, actions } = state;
  const employee = employees.find((e) => e.id === employeeId);
  if (!employee)
    return (
      <PageBody>
        <EmptyNote>This employee no longer works here.</EmptyNote>
      </PageBody>
    );
  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-3 border-b border-hairline px-5 py-3">
        <EmployeePortrait
          employee={employee}
          size={32}
          mood={moodOf(state, employee)}
          label={employee.name}
        />
        <div className="flex min-w-0 flex-col">
          <h1 className="truncate text-heading font-semibold text-ink">{employee.name}</h1>
          <span className="truncate text-detail text-ink-3">
            {employee.paused
              ? "Paused"
              : state.workingOf(employee.id)
                ? "Working"
                : templateTitle(employee.template)}
          </span>
        </div>
        <span className="ml-auto" />
        <DevysButton
          kind="quiet"
          compact
          onClick={() => actions.selectPage({ kind: "employee", id: employee.id })}
        >
          <UserRound /> Profile
        </DevysButton>
      </div>
      <div className="min-h-0 flex-1">
        <ConversationView
          conversation={main}
          className="max-w-[760px]"
          empty={
            <>
              <EmployeePortrait employee={employee} size={48} />
              <span className="text-body text-ink-3">
                Message {employee.name}. @mention a colleague to bring them in.
              </span>
            </>
          }
        />
      </div>
      <Composer
        conversation={main}
        which="main"
        label={`Message ${employee.name}`}
        className="max-w-[780px]"
      />
    </div>
  );
}
