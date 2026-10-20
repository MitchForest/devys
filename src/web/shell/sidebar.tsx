import {
  CircleAlert,
  CircleCheck,
  CircleDashed,
  Clock,
  BarChart3,
  Link,
  LayoutGrid,
  Plus,
  FolderOpen,
  ScanFace,
  Sun,
  Inbox,
  UserPlus,
  type LucideIcon,
} from "lucide-react";
import { EmployeePortrait } from "../design/portrait.tsx";
import { useState, type ReactNode } from "react";
import type { Employee } from "../app/api.ts";
import { moodOf, templateTitle, workFilters } from "../app/names.ts";
import {
  filterOf,
  useWorkspace,
  valueOf,
  type Destination,
  type Page,
  type WorkFilter,
} from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { fieldClass } from "../design/fields.tsx";
import { BusinessTile } from "../design/face.tsx";
import { StatusChip } from "../design/primitives.tsx";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

export const destinations: { value: Destination; title: string }[] = [
  { value: "home", title: "Home" },
  { value: "inbox", title: "Inbox" },
  { value: "work", title: "Work" },
  { value: "team", title: "Team" },
  { value: "money", title: "Money" },
  { value: "apps", title: "Apps" },
];
const tints = ["blue", "orange", "green", "purple", "pink"];
/** A space's tile color, from its place in the list, the same everywhere it shows. */
export const spaceTint = (index: number) => tints[(index + 1) % tints.length]!;
const filterIcons: Record<WorkFilter, LucideIcon> = {
  all: Inbox,
  needsYou: CircleAlert,
  inProgress: CircleDashed,
  waiting: Clock,
  done: CircleCheck,
};
// Files is one page whichever file it opened at.
const samePage = (a: Page, b: Page) =>
  a.kind === "files" ? b.kind === "files" : JSON.stringify(a) === JSON.stringify(b);

type Trailing = "none" | "working" | "needsYou" | "paused";

/** Contextual navigation for the selected rail destination. The selection is one white pill. */
export function Sidebar() {
  const state = useWorkspace();
  const { destination, business, decisions, employees, work, actions } = state;
  const trailing = useTrailing();
  const mood = (employee: Employee) => moodOf(state, employee);
  return (
    <nav aria-label="Sidebar" className="h-full overflow-y-auto px-2.5 pb-4 [scrollbar-width:none]">
      <h2 className="px-2.5 pt-3.5 pb-3 text-heading font-semibold text-ink">
        {destination === "home"
          ? business?.name
          : destinations.find((d) => d.value === destination)!.title}
      </h2>
      <div className="flex flex-col gap-0.5">
        {destination === "home" && (
          <>
            <Row page={{ kind: "today" }} title="Today" icon={Sun} />
            <Row
              page={{ kind: "approvals" }}
              title="Approvals"
              icon={ScanFace}
              count={valueOf(decisions)?.length ?? 0}
            />
            <Row page={{ kind: "files" }} title="Files" icon={FolderOpen} />
            <ConversationList />
          </>
        )}
        {destination === "inbox" && <Quiet>Mail arrives with E1.</Quiet>}
        {destination === "work" &&
          workFilters.map((filter) => (
            <Row
              key={filter.value}
              page={{ kind: "work", filter: filter.value }}
              title={filter.title}
              icon={filterIcons[filter.value]}
              count={
                (valueOf(work) ?? []).filter(
                  (item) => filter.value === "all" || filterOf(item.state) === filter.value,
                ).length
              }
            />
          ))}
        {destination === "team" && (
          <>
            {employees.map((employee) => (
              <Row
                key={employee.id}
                page={{ kind: "employee", id: employee.id }}
                title={employee.name}
                detail={templateTitle(employee.template)}
                trailing={trailing(employee)}
              >
                <EmployeePortrait employee={employee} size={26} mood={mood(employee)} />
              </Row>
            ))}
            <button
              type="button"
              onClick={() => actions.setHireOpen(true)}
              className="flex w-full items-center gap-2.5 rounded-[9px] px-2.5 py-[7px] text-left text-control text-ink-2 hover:text-ink"
            >
              <UserPlus className="size-[15px] w-[26px] shrink-0" strokeWidth={1.9} />
              Hire
            </button>
          </>
        )}
        {destination === "money" && (
          <Row page={{ kind: "money" }} title="Overview" icon={BarChart3} />
        )}
        {destination === "apps" && (
          <>
            <Row
              page={{ kind: "apps", section: "installed" }}
              title="Installed"
              icon={LayoutGrid}
            />
            <Row page={{ kind: "apps", section: "connections" }} title="Connections" icon={Link} />
          </>
        )}
      </div>
    </nav>
  );
}

function useTrailing() {
  const state = useWorkspace();
  return (employee: Employee): Trailing =>
    employee.paused
      ? "paused"
      : state.workingOf(employee.id)
        ? "working"
        : (valueOf(state.decisions) ?? []).some((d) => d.employee_id === employee.id)
          ? "needsYou"
          : "none";
}

/**
 * Every conversation the owner can open: a DM with each employee and each space, with
 * unread counts. The sidebar's Home and the phone's home list both show it.
 */
export function ConversationList() {
  const state = useWorkspace();
  const { spaces, employees, actions, unreadOf } = state;
  const trailing = useTrailing();
  return (
    <div className="flex flex-col gap-0.5">
      <div className="flex items-center">
        <Label>Direct messages</Label>
        <span className="ml-auto" />
        <button
          type="button"
          aria-label="Hire"
          title="Hire"
          onClick={() => actions.setHireOpen(true)}
          className="mr-2.5 grid place-items-center pt-3 text-ink-3 hover:text-ink-2"
        >
          <Plus className="size-3.5" />
        </button>
      </div>
      <div role="group" aria-label="Direct messages" className="flex flex-col gap-0.5">
        {employees.map((employee) => (
          <Row
            key={employee.id}
            page={{ kind: "direct", employeeId: employee.id }}
            title={employee.name}
            trailing={trailing(employee)}
            unread={unreadOf(`direct:${employee.id}`)}
          >
            <EmployeePortrait employee={employee} size={20} mood={moodOf(state, employee)} />
          </Row>
        ))}
      </div>
      <div className="flex items-center">
        <Label>Spaces</Label>
        <span className="ml-auto" />
        <NewSpaceButton />
      </div>
      <div role="group" aria-label="Spaces" className="flex flex-col gap-0.5">
        {(valueOf(spaces) ?? []).map((space, index) => (
          <Row
            key={space.id}
            page={{ kind: "space", id: space.id }}
            title={space.name}
            unread={unreadOf(`space:${space.id}`)}
          >
            <BusinessTile name={space.name} tint={spaceTint(index)} size={20} />
          </Row>
        ))}
      </div>
    </div>
  );
}

function Label({ children }: { children: ReactNode }) {
  return <h3 className="px-2.5 pt-3.5 pb-1 text-label font-medium text-ink-3">{children}</h3>;
}

function Quiet({ children }: { children: ReactNode }) {
  return <p className="px-2.5 text-detail text-ink-3">{children}</p>;
}

function Row({
  page,
  title,
  detail,
  icon: Icon,
  count,
  unread = 0,
  trailing = "none",
  children,
}: {
  page: Page;
  title: string;
  detail?: string;
  icon?: LucideIcon;
  count?: number;
  /** Messages the owner hasn't read: a filled badge. */
  unread?: number;
  trailing?: Trailing;
  children?: ReactNode;
}) {
  const { page: current, actions } = useWorkspace();
  const selected = samePage(current, page);
  return (
    <button
      type="button"
      aria-label={unread ? `${title}, ${unread} unread` : detail ? undefined : title}
      aria-current={selected ? "page" : undefined}
      onClick={() => actions.selectPage(page)}
      className={cn(
        "flex w-full items-center gap-2.5 rounded-[9px] px-2.5 text-left text-control transition-[color,background-color,box-shadow] duration-200",
        detail ? "py-1.5" : "py-[7px]",
        selected ? "bg-sheet text-ink shadow-resting" : "text-ink-2 hover:text-ink",
        unread > 0 && !selected && "font-semibold text-ink",
      )}
    >
      {Icon ? <Icon className="size-[15px] w-5 shrink-0" strokeWidth={1.9} /> : children}
      <span className="flex min-w-0 flex-col gap-px">
        <span className="truncate">{title}</span>
        {detail && <span className="truncate text-detail text-ink-3">{detail}</span>}
      </span>
      <span className="ml-auto" />
      {trailing === "working" && (
        <span className="size-1.5 shrink-0 rounded-full bg-indigo" aria-label="working" />
      )}
      {trailing === "needsYou" && (
        <StatusChip tone="needsYou" small>
          Needs you
        </StatusChip>
      )}
      {trailing === "paused" && <span className="text-caption text-ink-3">Paused</span>}
      {unread > 0 && (
        <span
          data-testid="unread"
          className="grid h-[17px] min-w-[17px] shrink-0 place-items-center rounded-full bg-indigo px-1 text-[10.5px] font-bold text-white tabular-nums"
        >
          {unread}
        </span>
      )}
      {count !== undefined && count > 0 && (
        <span className="text-detail tabular-nums text-ink-3">{count}</span>
      )}
    </button>
  );
}

/** Creates a space with a name, a purpose and the employee who leads its thread. */
function NewSpaceButton() {
  const { actions, employees, operations } = useWorkspace();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [purpose, setPurpose] = useState("");
  const [lead, setLead] = useState("");
  const create = () => {
    void actions.createSpace({ name, purpose, lead: lead || operations?.id || "" });
    setName("");
    setPurpose("");
    setLead("");
    setOpen(false);
  };
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger
        aria-label="New space"
        title="New space"
        className="mr-2.5 grid place-items-center pt-3 text-ink-3 hover:text-ink-2"
      >
        <Plus className="size-3.5" />
      </PopoverTrigger>
      <PopoverContent side="bottom" align="start" className="w-[280px] rounded-[12px] p-3">
        <form
          className="flex flex-col gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            create();
          }}
        >
          <input
            autoFocus
            aria-label="Space name"
            placeholder="Space name"
            value={name}
            maxLength={80}
            onChange={(event) => setName(event.target.value)}
            className={fieldClass}
          />
          <input
            aria-label="Purpose"
            placeholder="Purpose (optional)"
            value={purpose}
            maxLength={500}
            onChange={(event) => setPurpose(event.target.value)}
            className={fieldClass}
          />
          <select
            aria-label="Lead"
            value={lead || operations?.id || ""}
            onChange={(event) => setLead(event.target.value)}
            className={fieldClass}
          >
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>
                Led by {employee.name}
              </option>
            ))}
          </select>
          <DevysButton compact type="submit" disabled={!name.trim()} className="self-end">
            Create
          </DevysButton>
        </form>
      </PopoverContent>
    </Popover>
  );
}
