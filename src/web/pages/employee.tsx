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
import { useEffect, useState } from "react";
import { api, type Employee, type Grant, type RuntimeState } from "../app/api.ts";
import { accessTitle, isOpen, moodOf, templateTitle } from "../app/names.ts";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { Field, fieldClass } from "../design/fields.tsx";
import { WorkRow } from "./work.tsx";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { dollars, ModelPicker, perTurn, spend } from "../design/model-picker.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { Card, EmptyNote, LiveTag, PageBody, SectionHeader } from "../design/primitives.tsx";
import { Spinner } from "../design/spinner.tsx";
import { SegmentedTabs } from "../design/tabs.tsx";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";

export function PausedBanner({ employee }: { employee: Employee }) {
  const { actions } = useWorkspace();
  return (
    <div className="flex items-center gap-2.5 rounded-card bg-sheet-tint p-3">
      <CirclePause className="size-4 shrink-0 fill-gray text-sheet-tint" />
      <span className="text-body text-ink-2">{employee.name} is paused and takes no actions.</span>
      <span className="ml-auto" />
      <DevysButton compact onClick={() => actions.togglePause(employee)}>
        Resume
      </DevysButton>
    </div>
  );
}

export function EmployeePage({ id }: { id?: string }) {
  const state = useWorkspace();
  const { employees, employeeTab, actions } = state;
  const employee = employees.find((e) => e.id === id) ?? employees[0];
  if (!employee)
    return (
      <PageBody>
        <EmptyNote>No employees yet.</EmptyNote>
      </PageBody>
    );
  const isOperations = employee.id === state.operations?.id;
  const owned = (valueOf(state.work) ?? []).filter(
    (item) => item.owner_employee_id === employee.id,
  );
  return (
    <PageBody>
      <div className="flex flex-wrap items-center gap-4">
        <EmployeePortrait
          employee={employee}
          size={56}
          mood={moodOf(state, employee)}
          label={employee.name}
        />
        <div className="flex min-w-0 flex-col gap-0.5">
          <EditableName key={employee.id} employee={employee} />
          {templateTitle(employee.template) !== employee.name && (
            <span className="text-body text-ink-2">{templateTitle(employee.template)}</span>
          )}
        </div>
        <span className="ml-auto" />
        <div className="flex items-center gap-2">
          <DevysButton compact onClick={() => actions.message(employee.id)}>
            Message
          </DevysButton>
          <DevysButton compact onClick={() => actions.newTask({ owner: employee.id })}>
            <Plus /> New task
          </DevysButton>
          {employee.template !== "operations" && <RetireButton employee={employee} />}
        </div>
      </div>
      <ModelRow employee={employee} />
      <SegmentedTabs
        label="Employee"
        value={employeeTab}
        options={[
          { value: "activity", title: "Activity" },
          { value: "responsibilities", title: "Responsibilities" },
          { value: "memory", title: "Memory" },
          { value: "access", title: "Access" },
        ]}
        onChange={actions.setEmployeeTab}
      />
      {employee.paused && <PausedBanner employee={employee} />}
      {employeeTab === "activity" ? (
        <div className="flex flex-col gap-2">
          <SectionHeader title="Open work" count={owned.filter((i) => isOpen(i.state)).length} />
          {owned.filter((i) => isOpen(i.state)).length === 0 && (
            <EmptyNote>Nothing open. Give {employee.name} a task.</EmptyNote>
          )}
          {owned
            .filter((i) => isOpen(i.state))
            .map((item) => (
              <WorkRow key={item.id} item={item} />
            ))}
        </div>
      ) : employeeTab === "responsibilities" ? (
        <ResponsibilitiesPane key={employee.id} employee={employee} />
      ) : employeeTab === "memory" ? (
        <MemoryPane isOperations={isOperations} />
      ) : (
        <AccessPane employee={employee} />
      )}
    </PageBody>
  );
}

/** The employee's name; click the pencil to rename them. */
function EditableName({ employee }: { employee: Employee }) {
  const { actions } = useWorkspace();
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(employee.name);
  const save = () => {
    const next = name.trim();
    setEditing(false);
    if (!next || next === employee.name) return setName(employee.name);
    void actions.setProfile(employee, { name: next }).then((ok) => ok || setName(employee.name));
  };
  if (editing)
    return (
      <form
        onSubmit={(event) => {
          event.preventDefault();
          save();
        }}
      >
        <input
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
          className={cn(fieldClass, "py-0.5 text-title font-semibold")}
        />
      </form>
    );
  return (
    <div className="group/name flex items-center gap-1.5">
      <h1 className="text-title font-semibold text-ink">{employee.name}</h1>
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
  const { actions } = useWorkspace();
  const [text, setText] = useState(employee.role);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string }>();
  const changed = text.trim() !== employee.role.trim();
  return (
    <form
      className="flex flex-col gap-3"
      onSubmit={(event) => {
        event.preventDefault();
        if (!text.trim()) return;
        setSaving(true);
        setMessage(undefined);
        void actions
          .setProfile(employee, { responsibilities: text.trim() })
          .then((ok) =>
            setMessage(
              ok
                ? { ok, text: "Saved. The next turn starts from these." }
                : { ok, text: "Those responsibilities couldn't be saved." },
            ),
          )
          .finally(() => setSaving(false));
      }}
    >
      <Field label="Accountable for" hint={`${text.length} of 2000 characters`}>
        <textarea
          aria-label="Responsibilities"
          className={cn(fieldClass, "min-h-48 resize-y leading-[1.45]")}
          value={text}
          maxLength={2000}
          onChange={(event) => {
            setText(event.target.value);
            setMessage(undefined);
          }}
        />
      </Field>
      <div className="flex items-center gap-2.5">
        <DevysButton type="submit" disabled={saving || !changed || !text.trim()}>
          {saving ? "Saving…" : "Save responsibilities"}
        </DevysButton>
        {changed && (
          <DevysButton kind="quiet" onClick={() => setText(employee.role)}>
            Discard
          </DevysButton>
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
  const { employees, operations, work, actions } = useWorkspace();
  const [open, setOpen] = useState(false);
  const others = employees.filter((e) => e.id !== employee.id);
  const [successor, setSuccessor] = useState("");
  const [busy, setBusy] = useState(false);
  const chosen = successor || operations?.id || others[0]?.id || "";
  const openWork = (valueOf(work) ?? []).filter(
    (item) => item.owner_employee_id === employee.id && isOpen(item.state),
  ).length;
  return (
    <>
      <DevysButton kind="quiet" compact onClick={() => setOpen(true)}>
        <UserMinus /> Retire…
      </DevysButton>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="w-[420px] max-w-[calc(100%-2rem)] gap-0 rounded-card! bg-sheet p-0 shadow-raised sm:max-w-[420px]">
          <form
            className="flex flex-col gap-4 p-6"
            onSubmit={(event) => {
              event.preventDefault();
              if (!chosen) return;
              setBusy(true);
              void actions
                .retire(employee, chosen)
                .then((ok) => ok && setOpen(false))
                .finally(() => setBusy(false));
            }}
          >
            <DialogTitle className="text-heading font-semibold text-ink">
              Retire {employee.name}?
            </DialogTitle>
            <p className="text-body text-ink-2">
              {openWork === 0
                ? `${employee.name} has no open work.`
                : `${employee.name}'s ${openWork} open ${openWork === 1 ? "task moves" : "tasks move"} to the colleague you choose.`}
            </p>
            <Field label="Hand open work to">
              <select
                className={fieldClass}
                value={chosen}
                onChange={(event) => setSuccessor(event.target.value)}
              >
                {others.map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.name}
                  </option>
                ))}
              </select>
            </Field>
            <div className="flex justify-end gap-2">
              <DevysButton kind="quiet" onClick={() => setOpen(false)}>
                Cancel
              </DevysButton>
              <DevysButton type="submit" disabled={busy || !chosen} className="text-red">
                {busy ? "Retiring…" : "Retire"}
              </DevysButton>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}

/** Which model the employee thinks with, what it has spent, and a way to change it. */
function ModelRow({ employee }: { employee: Employee }) {
  const { businessId, models, modelOf, actions } = useWorkspace();
  const [usage, setUsage] = useState<RuntimeState["usage"]>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    setUsage(undefined);
    setError(undefined);
    let current = true;
    api
      .status(businessId, employee.id)
      .then((result) => current && setUsage(result.state.usage))
      .catch(() => undefined);
    return () => {
      current = false;
    };
  }, [businessId, employee.id]);
  const catalog = valueOf(models);
  const model = modelOf(employee.model);
  const spent = usage ? spend(usage.models) : undefined;
  const choose = async (id: string) => {
    if (id === employee.model) return;
    setError(undefined);
    if (!(await actions.setEmployeeModel(employee, id)))
      setError("That model couldn't be saved. The previous one is still in use.");
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
            onChange={(id) => void choose(id)}
            trigger={
              <DevysButton kind="quiet" compact aria-label={`Change model for ${employee.name}`}>
                Change <ChevronDown />
              </DevysButton>
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

function MemoryPane({ isOperations }: { isOperations: boolean }) {
  const { memory } = useWorkspace();
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-2">
        <span className="text-heading font-semibold text-ink">What I remember</span>
        {isOperations && <LiveTag />}
      </div>
      {!isOperations ? (
        <EmptyNote>No memory yet</EmptyNote>
      ) : memory.status === "loading" ? (
        <Spinner />
      ) : memory.status === "failed" ? (
        <EmptyNote>{memory.message}</EmptyNote>
      ) : memory.value.length === 0 ? (
        <EmptyNote>Nothing remembered yet.</EmptyNote>
      ) : (
        memory.value.map((claim) => (
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
  const { access, actions } = useWorkspace();
  useEffect(() => {
    actions.loadAccess(employee.id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [employee.id]);
  const list = access?.employeeId === employee.id ? access.list : { status: "loading" as const };
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-2">
        <span className="text-heading font-semibold text-ink">Standing access</span>
        <LiveTag />
        <span className="ml-auto" />
        {list.status === "loaded" && list.value.available.length > 0 && (
          <DropdownMenu>
            <DropdownMenuTrigger
              render={
                <DevysButton kind="quiet" compact>
                  <Plus /> Add access
                </DevysButton>
              }
            />
            <DropdownMenuContent align="end" className="w-auto">
              {list.value.available.map((capability) => (
                // Anything that reaches outside the business asks first by default.
                <DropdownMenuItem
                  key={capability.capability}
                  onClick={() =>
                    actions.grant(
                      employee.id,
                      capability.capability,
                      capability.effect === "external" ? "ask" : "auto",
                    )
                  }
                >
                  {accessTitle(capability.capability)}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>
      {list.status === "loading" ? (
        <Spinner />
      ) : list.status === "failed" ? (
        <EmptyNote>{list.message}</EmptyNote>
      ) : (
        <>
          {list.value.grants.length === 0 && (
            <EmptyNote>
              No access yet. {employee.name} can talk with you but can't act until you grant
              something.
            </EmptyNote>
          )}
          {list.value.grants.map((grant) => (
            <GrantRow
              key={grant.id}
              grant={grant}
              revoke={() => actions.revoke(employee.id, grant.id)}
            />
          ))}
        </>
      )}
    </div>
  );
}

function GrantRow({ grant, revoke }: { grant: Grant; revoke: () => void }) {
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
        {grant.constraints.hosts?.length ? (
          <span className="text-detail text-ink-3">Only {grant.constraints.hosts.join(", ")}</span>
        ) : null}
      </div>
      <span className="ml-auto" />
      <DevysButton
        kind="quiet"
        compact
        onClick={revoke}
        className={hovering ? "opacity-100" : "opacity-55"}
      >
        Revoke
      </DevysButton>
    </div>
  );
}
