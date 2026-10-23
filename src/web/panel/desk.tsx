import {
  ChevronDown,
  CirclePause,
  Cpu,
  KeyRound,
  Pencil,
  Plus,
  ScanFace,
  TriangleAlert,
  UserMinus,
} from "lucide-react";
import { EmployeePortrait } from "../design/portrait.tsx";
import { useQuery } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { api } from "../app/api.ts";
import type { AccessList } from "../../app/wire.ts";
import type { Employee } from "../../identity/contract.ts";
import {
  useBusinessId,
  useEmployees,
  useMemory,
  useModels,
  useChiefOfStaff,
  useRoutines,
  useStatus,
  useWork,
} from "../app/data.ts";
import {
  useGrant,
  useRetire,
  useRevoke,
  useSetEmployeeModel,
  useSetProfile,
  useTogglePause,
} from "../app/mutations.ts";
import { accessTitle, isOpen, templateTitle } from "../app/names.ts";
import { keys, problemOf } from "../app/query.ts";
import { ui } from "../app/ui.ts";
import { useMood, useWorking } from "../app/workspace.tsx";
import { RoutinesSection } from "./routines.tsx";
import { WorkRow } from "./work.tsx";
import { PanelBody, PanelHeader, PanelSection } from "./panel.tsx";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { dollars, ModelPicker, perTurn, spend } from "../design/model-picker.tsx";
import { Card, EmptyNote } from "../design/primitives.tsx";
import { Spinner } from "../design/spinner.tsx";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { NativeSelect } from "@/components/ui/native-select";
import { Textarea } from "@/components/ui/textarea";

export function PausedBanner({ employee }: { employee: Employee }) {
  const togglePause = useTogglePause();
  return (
    <div className="flex items-center gap-2.5 rounded-card bg-sheet-tint p-3">
      <CirclePause className="size-4 shrink-0 fill-gray text-sheet-tint" />
      <span className="text-body text-ink-2">{employee.name} is paused and takes no actions.</span>
      <span className="ml-auto" />
      <Button size="compact" onClick={() => togglePause.mutate(employee)}>
        Resume
      </Button>
    </div>
  );
}

/**
 * A direct chat's permanent view: the employee's desk. What it is on now and what it just
 * finished stay open; who it is, its model, access and memory unfold on demand.
 */
export function Desk({ employeeId, close }: { employeeId: string; close: () => void }) {
  const employee = useEmployees().find((e) => e.id === employeeId);
  if (!employee)
    return (
      <section className="flex h-full flex-col">
        <PanelHeader title="Desk" close={close} />
        <PanelBody>
          <EmptyNote>This employee no longer works here.</EmptyNote>
        </PanelBody>
      </section>
    );
  return <EmployeeDesk employee={employee} close={close} />;
}

function EmployeeDesk({ employee, close }: { employee: Employee; close: () => void }) {
  const chiefOfStaff = useChiefOfStaff();
  const work = useWork().data;
  const routines = (useRoutines().data ?? []).filter((r) => r.employee_id === employee.id);
  const mood = useMood(employee);
  const working = useWorking(employee.id);
  const togglePause = useTogglePause();
  const isChiefOfStaff = employee.id === chiefOfStaff?.id;
  const owned = (work ?? []).filter((item) => item.owner_employee_id === employee.id);
  const open = owned.filter((item) => isOpen(item.state));
  const done = owned
    .filter((item) => item.state === "completed")
    .sort((a, b) => b.updated_at.localeCompare(a.updated_at))
    .slice(0, 5);
  return (
    <section aria-label={`${employee.name}'s desk`} className="flex h-full flex-col">
      <PanelHeader title={<EditableName key={employee.id} employee={employee} />} close={close} />
      <PanelBody>
        <div className="flex items-center gap-3">
          <EmployeePortrait employee={employee} size={44} mood={mood} label={employee.name} />
          <div className="flex min-w-0 flex-col gap-0.5">
            {templateTitle(employee.template) !== employee.name && (
              <span className="text-control text-ink">{templateTitle(employee.template)}</span>
            )}
            <span className="text-detail text-ink-3">
              {employee.paused
                ? "Paused"
                : working
                  ? "Working"
                  : open.length
                    ? `${open.length} open`
                    : "Free"}
            </span>
          </div>
          <span className="ml-auto" />
          <Button size="compact" variant="quiet" onClick={() => togglePause.mutate(employee)}>
            {employee.paused ? "Resume" : "Pause"}
          </Button>
        </div>
        {employee.paused && <PausedBanner employee={employee} />}
        {open.length > 0 && (
          <PanelSection
            title="Now"
            count={open.length}
            action={
              <button
                type="button"
                onClick={() => ui.newWorkItem({ owner: employee.id })}
                className="text-caption text-ink-3 hover:text-ink-2"
              >
                <Plus className="inline size-3" /> Work item
              </button>
            }
          >
            {open.map((item) => (
              <WorkRow key={item.id} item={item} compact />
            ))}
          </PanelSection>
        )}
        <RoutinesSection routines={routines} />
        {done.length > 0 && (
          <PanelSection title="Recently done">
            {done.map((item) => (
              <WorkRow key={item.id} item={item} compact />
            ))}
          </PanelSection>
        )}
        <div className="flex flex-col border-t border-hairline">
          <Disclosure title="Responsibilities">
            <ResponsibilitiesPane key={employee.id} employee={employee} />
          </Disclosure>
          <Disclosure title="Model">
            <ModelRow employee={employee} />
          </Disclosure>
          <Disclosure title="Access">
            <AccessPane employee={employee} />
          </Disclosure>
          {isChiefOfStaff && (
            <Disclosure title="Memory">
              <MemoryPane />
            </Disclosure>
          )}
        </div>
        {employee.template !== "chief-of-staff" && (
          <div>
            <RetireButton employee={employee} />
          </div>
        )}
      </PanelBody>
    </section>
  );
}

/** A section that unfolds on demand, so the desk shows only what is moving. */
function Disclosure({ title, children }: { title: string; children: ReactNode }) {
  return (
    <details className="group border-b border-hairline py-2.5">
      <summary className="flex cursor-pointer list-none items-center gap-1.5 text-control text-ink-2 hover:text-ink [&::-webkit-details-marker]:hidden">
        <ChevronDown className="size-3.5 -rotate-90 text-ink-3 transition-transform group-open:rotate-0" />
        {title}
      </summary>
      <div className="pt-3">{children}</div>
    </details>
  );
}

/** The employee's name; click the pencil to rename them. */
function EditableName({ employee }: { employee: Employee }) {
  const setProfile = useSetProfile();
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(employee.name);
  const save = () => {
    const next = name.trim();
    setEditing(false);
    if (!next || next === employee.name) return setName(employee.name);
    setProfile.mutate(
      { employee, change: { name: next } },
      { onError: () => setName(employee.name) },
    );
  };
  if (editing)
    return (
      <form
        onSubmit={(event) => {
          event.preventDefault();
          save();
        }}
      >
        <Input
          autoFocus
          aria-label="Name"
          value={name}
          maxLength={80}
          onChange={(event) => setName(event.target.value)}
          onBlur={save}
          onKeyDown={(event) => {
            if (event.key === "Escape") {
              setName(employee.name);
              setEditing(false);
            }
          }}
          className="py-0.5 text-control font-semibold"
        />
      </form>
    );
  return (
    <div className="group/name flex items-center gap-1.5">
      <span className="truncate text-control font-semibold text-ink">{employee.name}</span>
      <button
        type="button"
        aria-label={`Rename ${employee.name}`}
        title="Rename"
        onClick={() => setEditing(true)}
        className="grid size-6 place-items-center rounded-full text-ink-3 opacity-60 group-hover/name:opacity-100 hover:text-ink-2"
      >
        <Pencil className="size-3.5" />
      </button>
    </div>
  );
}

/** What the employee is accountable for; every turn starts from it. */
function ResponsibilitiesPane({ employee }: { employee: Employee }) {
  const setProfile = useSetProfile();
  const [text, setText] = useState(employee.responsibilities);
  const saving = setProfile.isPending;
  const [message, setMessage] = useState<{ ok: boolean; text: string }>();
  const changed = text.trim() !== employee.responsibilities.trim();
  return (
    <form
      className="flex flex-col gap-3"
      onSubmit={(event) => {
        event.preventDefault();
        if (!text.trim()) return;
        setMessage(undefined);
        setProfile.mutate(
          { employee, change: { responsibilities: text.trim() } },
          {
            onSuccess: () =>
              setMessage({ ok: true, text: "Saved. The next turn starts from these." }),
            onError: () =>
              setMessage({ ok: false, text: "Those responsibilities couldn't be saved." }),
          },
        );
      }}
    >
      <Field label="Accountable for" hint={`${text.length} of 2000 characters`}>
        <Textarea
          aria-label="Responsibilities"
          className="min-h-48 resize-y leading-[1.45]"
          value={text}
          maxLength={2000}
          onChange={(event) => {
            setText(event.target.value);
            setMessage(undefined);
          }}
        />
      </Field>
      <div className="flex items-center gap-2.5">
        <Button type="submit" disabled={saving || !changed || !text.trim()}>
          {saving ? "Saving…" : "Save responsibilities"}
        </Button>
        {changed && (
          <Button variant="quiet" onClick={() => setText(employee.responsibilities)}>
            Discard
          </Button>
        )}
        {message && (
          <span
            role={message.ok ? "status" : "alert"}
            className={cn("text-detail", message.ok ? "text-green" : "text-red")}
          >
            {message.text}
          </span>
        )}
      </div>
    </form>
  );
}

/** Retiring hands the employee's open work to a colleague; their history stays readable. */
function RetireButton({ employee }: { employee: Employee }) {
  const employees = useEmployees();
  const chiefOfStaff = useChiefOfStaff();
  const work = useWork().data;
  const retire = useRetire();
  const [open, setOpen] = useState(false);
  const others = employees.filter((e) => e.id !== employee.id);
  const [successor, setSuccessor] = useState("");
  const busy = retire.isPending;
  const chosen = successor || chiefOfStaff?.id || others[0]?.id || "";
  const openWork = (work ?? []).filter(
    (item) => item.owner_employee_id === employee.id && isOpen(item.state),
  ).length;
  return (
    <>
      <Button variant="quiet" size="compact" onClick={() => setOpen(true)}>
        <UserMinus /> Retire…
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="w-[420px] max-w-[calc(100%-2rem)] gap-0 rounded-card! bg-sheet p-0 shadow-raised sm:max-w-[420px]">
          <form
            className="flex flex-col gap-4 p-6"
            onSubmit={(event) => {
              event.preventDefault();
              if (!chosen) return;
              retire.mutate({ employee, successor: chosen }, { onSuccess: () => setOpen(false) });
            }}
          >
            <DialogTitle className="text-heading font-semibold text-ink">
              Retire {employee.name}?
            </DialogTitle>
            <p className="text-body text-ink-2">
              {openWork === 0
                ? `${employee.name} has no open work.`
                : `${employee.name}'s ${openWork} open ${openWork === 1 ? "work item moves" : "work items move"} to the colleague you choose.`}
            </p>
            <Field label="Hand open work to">
              <NativeSelect value={chosen} onChange={(event) => setSuccessor(event.target.value)}>
                {others.map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.name}
                  </option>
                ))}
              </NativeSelect>
            </Field>
            <div className="flex justify-end gap-2">
              <Button variant="quiet" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={busy || !chosen} className="text-red">
                {busy ? "Retiring…" : "Retire"}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}

/** Which model the employee thinks with, what it has spent, and a way to change it. */
function ModelRow({ employee }: { employee: Employee }) {
  const usage = useStatus(employee.id).data?.usage;
  const catalog = useModels().data;
  const setModel = useSetEmployeeModel();
  const [error, setError] = useState<string>();
  const model = catalog?.models.find((m) => m.id === employee.model);
  const spent = usage ? spend(usage.models) : undefined;
  const choose = (id: string) => {
    if (id === employee.model) return;
    setError(undefined);
    setModel.mutate(
      { employee, model: id },
      {
        onError: () => setError("That model couldn't be saved. The previous one is still in use."),
      },
    );
  };
  return (
    <div className="flex flex-col gap-2 rounded-card bg-sheet-tint px-4 py-3">
      <div className="flex items-center gap-3">
        <Cpu className="size-4 shrink-0 text-ink-3" aria-hidden />
        <div className="flex min-w-0 flex-col gap-0.5">
          <span className="text-detail text-ink-3">Model</span>
          <span className="text-body font-semibold text-ink" data-testid="employee-model">
            {model?.label ?? employee.model}
          </span>
          {model && (
            <span className="text-detail text-ink-2">
              {model.provider} · {perTurn(model)}
            </span>
          )}
        </div>
        <span className="ml-auto" />
        {catalog && (
          <ModelPicker
            catalog={catalog}
            value={employee.model}
            onChange={choose}
            trigger={
              <Button
                variant="quiet"
                size="compact"
                aria-label={`Change model for ${employee.name}`}
              >
                Change <ChevronDown />
              </Button>
            }
          />
        )}
      </div>
      {spent && spent.total > 0 && (
        <span className="text-detail tabular-nums text-ink-3">
          Spent {dollars(spent.total)}
          {spent.cacheShare !== undefined &&
            ` · ${Math.round(spent.cacheShare * 100)}% of input from cache`}
        </span>
      )}
      {error && (
        <span role="alert" className="flex items-center gap-1.5 text-detail text-red">
          <TriangleAlert className="size-3.5 shrink-0" aria-hidden />
          {error}
        </span>
      )}
    </div>
  );
}

/** The business's memory, as the Chief of Staff keeps it. */
function MemoryPane() {
  const memory = useMemory();
  return (
    <div className="flex flex-col gap-3">
      <span className="text-heading font-semibold text-ink">What I remember</span>
      {memory.isPending ? (
        <Spinner />
      ) : memory.isError ? (
        <EmptyNote>{problemOf(memory.error, "Memory is unavailable.")}</EmptyNote>
      ) : memory.data.length === 0 ? (
        <EmptyNote>Nothing remembered yet.</EmptyNote>
      ) : (
        memory.data.map((claim) => (
          <Card key={claim.key}>
            <div className="flex flex-col gap-1">
              <span className="text-body text-ink">{claim.content}</span>
              <span className="text-detail text-ink-3">
                {claim.source_kind === "user" ? "From you" : "Inferred from conversation"}
              </span>
            </div>
          </Card>
        ))
      )}
    </div>
  );
}

/** What an employee may do, from the server: each grant, how it runs, and its limits. */
function AccessPane({ employee }: { employee: Employee }) {
  const businessId = useBusinessId();
  const grant = useGrant();
  const revoke = useRevoke();
  const list = useQuery({
    queryKey: keys.access(businessId, employee.id),
    queryFn: () => api.access(businessId, employee.id),
  });
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-2">
        <span className="text-heading font-semibold text-ink">Standing access</span>
        <span className="ml-auto" />
        {list.data && list.data.available.length > 0 && (
          <DropdownMenu>
            <DropdownMenuTrigger
              render={
                <Button variant="quiet" size="compact">
                  <Plus /> Add access
                </Button>
              }
            />
            <DropdownMenuContent align="end" className="w-auto">
              {list.data.available.map((capability) => (
                // Anything that reaches outside the business asks first by default.
                <DropdownMenuItem
                  key={capability.capability}
                  onClick={() =>
                    grant.mutate({
                      employeeId: employee.id,
                      capability: capability.capability,
                      mode: capability.effect === "external" ? "ask" : "auto",
                    })
                  }
                >
                  {accessTitle(capability.capability)}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>
      {list.isPending ? (
        <Spinner />
      ) : list.isError ? (
        <EmptyNote>{problemOf(list.error, "Access is unavailable.")}</EmptyNote>
      ) : (
        <>
          {list.data.grants.length === 0 && (
            <EmptyNote>
              No access yet. {employee.name} can talk with you but can't act until you grant
              something.
            </EmptyNote>
          )}
          {list.data.grants.map((each) => (
            <GrantRow
              key={each.id}
              grant={each}
              revoke={() => revoke.mutate({ employeeId: employee.id, grantId: each.id })}
            />
          ))}
        </>
      )}
    </div>
  );
}

function GrantRow({ grant, revoke }: { grant: AccessList["grants"][number]; revoke: () => void }) {
  const hosts = Array.isArray(grant.constraints.hosts)
    ? grant.constraints.hosts.filter((host): host is string => typeof host === "string")
    : [];
  const [hovering, setHovering] = useState(false);
  const asks = grant.mode === "ask";
  const Icon = asks ? ScanFace : KeyRound;
  return (
    <div
      className="flex items-start gap-3 py-1.5"
      onPointerEnter={() => setHovering(true)}
      onPointerLeave={() => setHovering(false)}
    >
      <Icon className={cn("mt-0.5 size-4 shrink-0", asks ? "text-amber" : "text-ink-3")} />
      <div className="flex min-w-0 flex-col gap-0.5">
        <span className="flex items-baseline gap-1.5">
          <span className="text-body font-semibold text-ink">{accessTitle(grant.capability)}</span>
          <span className={cn("text-caption", asks ? "text-amber" : "text-ink-3")}>
            {asks ? "Asks first" : "Runs"}
          </span>
        </span>
        {grant.description && (
          <span className="line-clamp-2 text-detail text-ink-2">{grant.description}</span>
        )}
        {hosts.length ? (
          <span className="text-detail text-ink-3">Only {hosts.join(", ")}</span>
        ) : null}
      </div>
      <span className="ml-auto" />
      <Button
        variant="quiet"
        size="compact"
        onClick={revoke}
        className={hovering ? "opacity-100" : "opacity-55"}
      >
        Revoke
      </Button>
    </div>
  );
}
