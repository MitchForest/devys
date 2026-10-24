import { useState } from "react";
import { palettes, shapes } from "../../identity/contract.ts";
import { useEmployees, useChiefOfStaff, useProjects, useRoles } from "../app/data.ts";
import {
  useCreateProject,
  useCreateWorkItem,
  useHire,
  useSetEmployeeLook,
} from "../app/mutations.ts";
import { ui, useUi, type WorkItemDefaults } from "../app/ui.ts";
import { Face, paletteInk } from "../design/face.tsx";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { EmployeePortrait } from "../design/portrait.tsx";
import type { ProjectChange } from "../../work/contract.ts";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { NativeSelect } from "@/components/ui/native-select";
import { Textarea } from "@/components/ui/textarea";

/**
 * New employee: their face large, a name, a role, and the Face's own looks (shape and color).
 * The role's template is copied; later edits stay on the employee.
 */
export function NewEmployeeSheet() {
  const hireOpen = useUi((state) => state.hireOpen);
  // Each opening starts a fresh form.
  const opening = useUi((state) => state.hireOpenings);
  return (
    <Dialog open={hireOpen} onOpenChange={ui.setHireOpen}>
      <DialogContent
        showCloseButton={false}
        className="w-[440px] max-w-[calc(100%-2rem)] gap-0 rounded-card! bg-sheet p-0 shadow-raised sm:max-w-[440px]"
      >
        <NewEmployeeForm key={opening} />
      </DialogContent>
    </Dialog>
  );
}

const randomFace = () => ({
  palette: palettes[Math.floor(Math.random() * palettes.length)]!,
  shape: shapes[Math.floor(Math.random() * shapes.length)]!,
  seed: Math.floor(Math.random() * 97),
});

function NewEmployeeForm() {
  const roles = useRoles();
  const hireEmployee = useHire();
  const setLook = useSetEmployeeLook();
  const [face, setFace] = useState(randomFace);
  const [roleId, setRoleId] = useState<string>();
  const [name, setName] = useState<string>();
  const [duties, setDuties] = useState("");
  const [error, setError] = useState<string>();
  const role = roles.data?.find((r) => r.id === roleId) ?? roles.data?.[0];
  const custom = role?.id === "custom";
  const shownName = name ?? role?.name ?? "";
  const responsibilities = custom ? duties.trim() : (role?.responsibilities ?? "");
  const busy = hireEmployee.isPending;
  const create = () => {
    if (!role || !shownName.trim() || !responsibilities) return;
    setError(undefined);
    hireEmployee.mutate(
      { template: role.id, name: shownName.trim(), responsibilities },
      {
        onSuccess: (hired) => {
          setLook.mutate({ employee: hired, look: { kind: "face", ...face } });
          ui.setHireOpen(false);
        },
        onError: () => setError("That didn't work. Try again."),
      },
    );
  };
  return (
    <form
      aria-label="New employee"
      className="flex flex-col items-center gap-5 p-6"
      onSubmit={(event) => {
        event.preventDefault();
        create();
      }}
    >
      <DialogTitle className="sr-only">New employee</DialogTitle>
      <Face spec={face} size={112} mood={busy ? "thinking" : "idle"} />
      <Input
        autoFocus
        aria-label="Name"
        placeholder="Name your employee"
        value={shownName}
        maxLength={80}
        onChange={(event) => setName(event.target.value)}
        className="h-11 rounded-row text-center text-[15px]"
      />
      <div className="flex w-full flex-col gap-1.5">
        <NativeSelect
          aria-label="Role"
          value={role?.id ?? ""}
          onChange={(event) => {
            setRoleId(event.target.value);
            setName(undefined);
          }}
        >
          {(roles.data ?? []).map((each) => (
            <option key={each.id} value={each.id}>
              {each.name || "Custom"}
            </option>
          ))}
        </NativeSelect>
        {role && !custom && <span className="px-1 text-detail text-ink-3">{role.summary}</span>}
        {custom && (
          <Textarea
            aria-label="What they do"
            placeholder="What they do, and how they work"
            className="min-h-20 resize-y leading-[1.4]"
            value={duties}
            maxLength={2000}
            onChange={(event) => setDuties(event.target.value)}
          />
        )}
      </div>
      <div className="grid grid-cols-8 gap-1.5" role="group" aria-label="Shape">
        {shapes.map((shape) => (
          <button
            key={shape}
            type="button"
            aria-label={shape}
            aria-pressed={face.shape === shape}
            onClick={() => setFace({ ...face, shape })}
            className={cn(
              "grid size-11 place-items-center rounded-control border-[1.5px] transition-colors",
              face.shape === shape ? "border-ink/70 bg-well" : "border-transparent hover:bg-well",
            )}
          >
            <Face spec={{ ...face, shape }} size={34} />
          </button>
        ))}
      </div>
      <div className="flex flex-wrap justify-center gap-2.5" role="group" aria-label="Color">
        {palettes.map((palette) => (
          <button
            key={palette}
            type="button"
            aria-label={palette.charAt(0).toUpperCase() + palette.slice(1)}
            aria-pressed={face.palette === palette}
            onClick={() => setFace({ ...face, palette })}
            className={cn(
              "size-6 rounded-full",
              face.palette === palette &&
                "outline outline-1 outline-offset-2 outline-ink ring-[2.5px] ring-sheet ring-inset",
            )}
            style={{ background: paletteInk[palette] }}
          />
        ))}
      </div>
      {error && (
        <p role="alert" className="text-detail text-red">
          {error}
        </p>
      )}
      <div className="flex w-full justify-end gap-2 pt-1">
        <Button variant="quiet" onClick={() => ui.setHireOpen(false)}>
          Cancel
        </Button>
        <Button
          type="submit"
          disabled={busy || !role || !shownName.trim() || !responsibilities}
          className="bg-ink! text-sheet!"
        >
          {busy ? "Creating…" : "Create"}
        </Button>
      </div>
    </form>
  );
}

/** The end of the chosen day, in the owner's time zone. */
export const endOfDay = (date: string) => new Date(`${date}T23:59:00`).toISOString();

/** A new work item: what, who owns it, why, by when and which project it is in. It opens beside the conversation. */
export function NewWorkItemDialog() {
  const defaults = useUi((state) => state.newWorkItem);
  // The opening's defaults are kept while it closes, and each opening is a fresh form.
  const [shown, setShown] = useState(defaults);
  if (defaults && defaults !== shown) setShown(defaults);
  return (
    <Dialog open={Boolean(defaults)} onOpenChange={(open) => !open && ui.closeNewWorkItem()}>
      <DialogContent className="w-[480px] max-w-[calc(100%-2rem)] gap-0 rounded-card! bg-sheet p-0 shadow-raised sm:max-w-[480px]">
        {shown && <NewWorkItemForm key={shown.opening} defaults={shown} />}
      </DialogContent>
    </Dialog>
  );
}

function NewWorkItemForm({ defaults }: { defaults: WorkItemDefaults }) {
  const employees = useEmployees();
  const chiefOfStaff = useChiefOfStaff();
  const projects = useProjects().data;
  const createWorkItem = useCreateWorkItem();
  const [title, setTitle] = useState("");
  const [owner, setOwner] = useState(defaults.owner ?? chiefOfStaff?.id ?? "");
  const [objective, setObjective] = useState("");
  const [due, setDue] = useState("");
  const [projectId, setProjectId] = useState(defaults.projectId ?? "");
  const [error, setError] = useState<string>();
  const busy = createWorkItem.isPending;
  const create = () => {
    if (!title.trim() || !owner) return;
    setError(undefined);
    createWorkItem.mutate(
      {
        title: title.trim().slice(0, 200),
        owner,
        ...(objective.trim() ? { objective: objective.trim() } : {}),
        ...(due ? { due_at: endOfDay(due) } : {}),
        ...(projectId ? { project_id: projectId } : {}),
      },
      {
        onSuccess: ui.closeNewWorkItem,
        onError: () => setError("The work item couldn't be saved. Try again."),
      },
    );
  };
  return (
    <form
      className="flex flex-col gap-4 p-6"
      onSubmit={(event) => {
        event.preventDefault();
        create();
      }}
    >
      <DialogTitle className="text-heading font-semibold text-ink">New work item</DialogTitle>
      <Field label="Title">
        <Input
          autoFocus
          value={title}
          maxLength={200}
          placeholder="Something the business owes"
          onChange={(event) => setTitle(event.target.value)}
        />
      </Field>
      <div className="grid grid-cols-2 gap-3 max-sm:grid-cols-1">
        <Field label="Owner">
          <NativeSelect value={owner} onChange={(event) => setOwner(event.target.value)}>
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>
                {employee.name}
              </option>
            ))}
          </NativeSelect>
        </Field>
        <Field label="Due">
          <Input type="date" value={due} onChange={(event) => setDue(event.target.value)} />
        </Field>
      </div>
      <Field label="Objective">
        <Textarea
          className="min-h-20 resize-y leading-[1.4]"
          value={objective}
          maxLength={4000}
          placeholder="What done looks like"
          onChange={(event) => setObjective(event.target.value)}
        />
      </Field>
      <Field label="Project">
        <NativeSelect value={projectId} onChange={(event) => setProjectId(event.target.value)}>
          <option value="">No project</option>
          {(projects ?? []).map((project) => (
            <option key={project.id} value={project.id}>
              {project.name}
            </option>
          ))}
        </NativeSelect>
      </Field>
      {error && (
        <p role="alert" className="text-detail text-red">
          {error}
        </p>
      )}
      <div className="flex justify-end gap-2 pt-1">
        <Button variant="quiet" onClick={ui.closeNewWorkItem}>
          Cancel
        </Button>
        <Button variant="aurora" type="submit" disabled={busy || !title.trim() || !owner}>
          {busy ? "Creating…" : "Create work item"}
        </Button>
      </div>
    </form>
  );
}

/** A new project: a name and, optionally, its goal, deadline, budget, lead and team. */
export function NewProjectDialog() {
  const projectOpen = useUi((state) => state.projectOpen);
  const createProject = useCreateProject();
  return (
    <Dialog open={projectOpen} onOpenChange={ui.setProjectOpen}>
      <DialogContent className="w-[480px] max-w-[calc(100%-2rem)] gap-4 rounded-card! bg-sheet p-6 shadow-raised sm:max-w-[480px]">
        <DialogTitle className="text-heading font-semibold text-ink">New project</DialogTitle>
        {projectOpen && (
          <ProjectFields
            cancel={() => ui.setProjectOpen(false)}
            submit={(project) => {
              const name = project.name.trim().slice(0, 80);
              if (!name) return Promise.resolve(false);
              return createProject.mutateAsync({ ...project, name }).then(
                () => true,
                () => false,
              );
            }}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

/** Name, goal, deadline, budget, lead and team, created as one project. */
function ProjectFields({
  submit,
  cancel,
}: {
  submit: (project: ProjectChange & { name: string }) => Promise<boolean>;
  cancel: () => void;
}) {
  const employees = useEmployees();
  const chiefOfStaff = useChiefOfStaff();
  const [name, setName] = useState("");
  const [goal, setGoal] = useState("");
  const [deadline, setDeadline] = useState("");
  const [budget, setBudget] = useState("");
  const [lead, setLead] = useState(chiefOfStaff?.id ?? "");
  const [members, setMembers] = useState<readonly string[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const amount = Number(budget);
  return (
    <form
      className="flex flex-col gap-3"
      onSubmit={(event) => {
        event.preventDefault();
        if (!name.trim()) return;
        setBusy(true);
        setError(undefined);
        void submit({
          name: name.trim(),
          goal: goal.trim() || null,
          deadline: deadline || null,
          budget:
            budget && Number.isFinite(amount) && amount >= 0
              ? { cents: Math.round(amount * 100), currency: "USD" }
              : null,
          ...(lead ? { lead } : {}),
          members,
        })
          .then((ok) => (ok ? cancel() : setError("That couldn't be saved.")))
          .finally(() => setBusy(false));
      }}
      onKeyDown={(event) => event.key === "Escape" && cancel()}
    >
      <Field label="Name">
        <Input
          autoFocus
          value={name}
          maxLength={80}
          placeholder="Launch"
          onChange={(event) => setName(event.target.value)}
        />
      </Field>
      <Field label="Goal">
        <Textarea
          className="min-h-16 resize-y leading-[1.4]"
          value={goal}
          maxLength={500}
          placeholder="What done looks like (optional)"
          onChange={(event) => setGoal(event.target.value)}
        />
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Deadline">
          <Input
            type="date"
            value={deadline}
            onChange={(event) => setDeadline(event.target.value)}
          />
        </Field>
        <Field label="Budget">
          <Input
            inputMode="decimal"
            value={budget}
            placeholder="None"
            onChange={(event) => setBudget(event.target.value.replace(/[^0-9.]/g, ""))}
          />
        </Field>
      </div>
      <Field label="Lead">
        <NativeSelect value={lead} onChange={(event) => setLead(event.target.value)}>
          {employees.map((employee) => (
            <option key={employee.id} value={employee.id}>
              {employee.name}
            </option>
          ))}
        </NativeSelect>
      </Field>
      <Field label="Team">
        <div className="flex flex-wrap gap-1.5">
          {employees
            .filter((employee) => employee.id !== lead)
            .map((employee) => {
              const on = members.includes(employee.id);
              return (
                <button
                  key={employee.id}
                  type="button"
                  aria-label={employee.name}
                  aria-pressed={on}
                  onClick={() =>
                    setMembers(
                      on ? members.filter((id) => id !== employee.id) : [...members, employee.id],
                    )
                  }
                  className={cn(
                    "flex items-center gap-1.5 rounded-full py-0.5 pr-2.5 pl-0.5 text-caption transition-colors",
                    on ? "bg-ink text-sheet" : "bg-sheet-tint text-ink-2 hover:text-ink",
                  )}
                >
                  <EmployeePortrait employee={employee} size={18} />
                  {employee.name}
                </button>
              );
            })}
        </div>
      </Field>
      {error && (
        <p role="alert" className="text-detail text-red">
          {error}
        </p>
      )}
      <div className="flex justify-end gap-2">
        <Button variant="quiet" onClick={cancel}>
          Cancel
        </Button>
        <Button variant="aurora" type="submit" disabled={busy || !name.trim()}>
          {busy ? "Creating…" : "Create project"}
        </Button>
      </div>
    </form>
  );
}
