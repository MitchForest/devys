import { FileText, Code2, PanelLeft } from "lucide-react";
import { useEffect, useState } from "react";
import type { Ref } from "../../protocol/ref.ts";
import { useChiefOfStaff, useEmployees, usePlaceTitle, useProjects } from "../app/data.ts";
import { useLayers, useNav, usePlace, type Place } from "../app/navigation.ts";
import { ui, useUi } from "../app/ui.ts";
import { useMood } from "../app/workspace.tsx";
import { BusinessTile } from "../design/face.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { Desk } from "../panel/desk.tsx";
import { kindOf, useCurrentRef, useRecordTitle } from "../panel/layers/titles.ts";
import { Overview } from "../panel/overview.tsx";
import { projectTint, SearchButton } from "./sidebar.tsx";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

const pill =
  "flex max-w-[min(420px,70%)] items-center gap-2 rounded-full bg-sheet py-1 pr-3.5 pl-1 shadow-resting ring-1 ring-hairline transition";

/**
 * The conversation's header: a centred pill with the face (or project tile) and name, which
 * opens the employee's desk or the project's details as a popover; the sidebar shows again from
 * here when hidden.
 */
export function ConversationHeader() {
  const place = usePlace();
  const sidebarVisible = useUi((state) => state.sidebarVisible);
  return (
    <header className="relative flex h-[52px] shrink-0 items-center justify-center px-3">
      <div className="absolute inset-y-0 left-3 flex items-center gap-1">
        {!sidebarVisible && (
          <>
            <HeaderButton label="Show sidebar (⌃⌘S)" onClick={ui.toggleSidebar}>
              <PanelLeft className="size-[15px]" />
            </HeaderButton>
            <SearchButton />
          </>
        )}
      </div>
      <PlacePill key={JSON.stringify(place)} place={place} />
    </header>
  );
}

function HeaderButton({
  label,
  children,
  ...props
}: React.ComponentProps<"button"> & { label: string }) {
  return (
    <button
      type="button"
      aria-label={label.replace(/ \(.*\)$/, "")}
      title={label}
      className="grid size-8 place-items-center rounded-full text-ink-2 hover:bg-track hover:text-ink"
      {...props}
    >
      {children}
    </button>
  );
}

/** The place's pill; tapping it shows who or what the conversation is with. */
export function PlacePill({ place }: { place: Place }) {
  const [open, setOpen] = useState(false);
  const title = usePlaceTitle(place);
  // Opening something from the popover (a routine, a kept page) shows it beside the chat.
  const { top } = useLayers();
  const shown = JSON.stringify(top);
  useEffect(() => setOpen(false), [shown]);
  const employees = useEmployees();
  const chiefOfStaff = useChiefOfStaff();
  const projects = useProjects().data ?? [];
  const employee =
    place.kind === "home"
      ? chiefOfStaff
      : place.kind === "direct"
        ? employees.find((e) => e.id === place.employeeId)
        : undefined;
  const projectIndex = place.kind === "project" ? projects.findIndex((p) => p.id === place.id) : -1;
  const face =
    place.kind === "project" ? (
      <BusinessTile name={title} tint={projectTint(Math.max(0, projectIndex))} size={26} />
    ) : employee ? (
      <PillFace employeeId={employee.id} />
    ) : null;
  const name = (
    <span className="truncate text-control font-semibold text-ink" data-testid="place-title">
      {title}
    </span>
  );
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger
        aria-label={`About ${title}`}
        className={cn(pill, "hover:shadow-raised", open && "shadow-raised")}
      >
        {face}
        {name}
      </PopoverTrigger>
      <PopoverContent
        side="bottom"
        align="center"
        sideOffset={8}
        className="max-h-[min(600px,calc(100dvh-120px))] w-[400px] max-w-[calc(100vw-2rem)] gap-0 overflow-hidden rounded-card bg-sheet p-0 shadow-raised [&>section]:h-auto [&>section]:min-h-0"
      >
        {place.kind === "project" ? (
          <Overview projectId={place.id} close={() => setOpen(false)} />
        ) : (
          employee && <Desk employeeId={employee.id} close={() => setOpen(false)} />
        )}
      </PopoverContent>
    </Popover>
  );
}

function PillFace({ employeeId }: { employeeId: string }) {
  const employee = useEmployees().find((e) => e.id === employeeId)!;
  const mood = useMood(employee);
  return <EmployeePortrait employee={employee} size={26} mood={mood} />;
}

/** A project's pinned items (kept with Keep in project), as a slim row under its header. */
export function ProjectPins({ projectId }: { projectId: string }) {
  const project = useProjects().data?.find((p) => p.id === projectId);
  const nav = useNav();
  const current = useCurrentRef();
  const recordTitle = useRecordTitle();
  const pins = (project?.items ?? [])
    .filter((item) => kindOf(item.ref))
    .map((item) => ({ id: item.id, ref: current(item.ref) }))
    .filter((item, index, all) => all.findIndex((other) => other.ref === item.ref) === index);
  if (!pins.length) return null;
  return (
    <div
      aria-label="Pinned"
      className="flex shrink-0 justify-center gap-1.5 overflow-x-auto px-4 pb-1.5 [scrollbar-width:none]"
    >
      {pins.map((pin) => (
        <PinChip
          key={pin.id}
          record={pin.ref}
          title={recordTitle(pin.ref)}
          open={() => nav.openLayer({ kind: "record", ref: pin.ref })}
        />
      ))}
    </div>
  );
}

function PinChip({ record, title, open }: { record: Ref; title: string; open: () => void }) {
  const Icon = kindOf(record)?.kind === "code/session" ? Code2 : FileText;
  return (
    <button
      type="button"
      onClick={open}
      className="flex max-w-56 shrink-0 items-center gap-1.5 rounded-full bg-sheet-tint px-2.5 py-1 text-caption text-ink-2 transition-colors hover:bg-track hover:text-ink"
    >
      <Icon className="size-3.5 shrink-0 text-ink-3" />
      <span className="truncate">{title}</span>
    </button>
  );
}
