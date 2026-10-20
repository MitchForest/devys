import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import type { Employee } from "../app/api.ts";
import { moodOf, templateTitle } from "../app/names.ts";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { EmptyNote, PageBody } from "../design/primitives.tsx";
import { Composer, ConversationView } from "../shell/chat.tsx";

/** A DM with one employee, in the main pane: their face, the conversation and the composer. */
export function DirectPage({ employeeId }: { employeeId: string }) {
  const state = useWorkspace();
  const { employees, main } = state;
  const employee = employees.find((e) => e.id === employeeId);
  if (!employee)
    return (
      <PageBody>
        <EmptyNote>This employee no longer works here.</EmptyNote>
      </PageBody>
    );
  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center border-b border-hairline px-5 py-3">
        <Popover>
          <PopoverTrigger
            aria-label={`About ${employee.name}`}
            className="-mx-1.5 flex min-w-0 items-center gap-3 rounded-[10px] px-1.5 py-1 text-left hover:bg-sheet-tint"
          >
            <EmployeePortrait employee={employee} size={32} mood={moodOf(state, employee)} />
            <div className="flex min-w-0 flex-col">
              <h1 className="truncate text-heading font-semibold text-ink">{employee.name}</h1>
              {/* Only what's changing: the role and description are a click away. */}
              {(employee.paused || state.workingOf(employee.id)) && (
                <span className="truncate text-detail text-ink-3">
                  {employee.paused ? "Paused" : "Working"}
                </span>
              )}
            </div>
          </PopoverTrigger>
          <PopoverContent align="start" className="w-80 gap-3 rounded-card bg-sheet p-4">
            <EmployeeAbout employee={employee} />
          </PopoverContent>
        </Popover>
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

/** Who an employee is, on demand: role, responsibilities, open work and the full profile. */
function EmployeeAbout({ employee }: { employee: Employee }) {
  const state = useWorkspace();
  const { actions } = state;
  const open = (valueOf(state.work) ?? []).filter(
    (item) =>
      item.owner_employee_id === employee.id &&
      item.state !== "completed" &&
      item.state !== "cancelled",
  );
  return (
    <>
      <div className="flex flex-col gap-0.5">
        <span className="text-control font-semibold text-ink">{employee.name}</span>
        {templateTitle(employee.template) !== employee.name && (
          <span className="text-detail text-ink-3">{templateTitle(employee.template)}</span>
        )}
      </div>
      <p className="line-clamp-6 text-detail text-ink-2">{employee.role}</p>
      {open.length > 0 && (
        <div className="flex flex-col gap-0.5">
          <span className="text-label font-medium text-ink-3">Open work · {open.length}</span>
          {open.slice(0, 6).map((item) => (
            <button
              key={item.id}
              type="button"
              onClick={() => actions.openWork(item.id)}
              className="-mx-2 truncate rounded-[8px] px-2 py-1 text-left text-detail text-ink hover:bg-sheet-tint"
            >
              {item.title}
            </button>
          ))}
        </div>
      )}
      <button
        type="button"
        onClick={() => actions.selectPage({ kind: "employee", id: employee.id })}
        className="self-start text-detail font-medium text-ink-2 hover:text-ink"
      >
        Open profile
      </button>
    </>
  );
}
