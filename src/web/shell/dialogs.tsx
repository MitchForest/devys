import { ChevronDown, ChevronLeft, KeyRound, UserPlus } from "lucide-react";
import { useState } from "react";
import { ApiError } from "../app/api.ts";
import type { RoleTemplate } from "../../identity/contract.ts";
import { useEmployees, useModels, useChiefOfStaff, useProjects, useRoles } from "../app/data.ts";
import { useCreateProject, useCreateWorkItem, useHire } from "../app/mutations.ts";
import { accessTitle } from "../app/names.ts";
import { problemOf } from "../app/query.ts";
import { ui, useUi, type WorkItemDefaults } from "../app/ui.ts";
import { ModelPicker, perTurn } from "../design/model-picker.tsx";
import { Spinner } from "../design/spinner.tsx";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Sheet, SheetContent, SheetTitle } from "@/components/ui/sheet";
import { cn } from "@/lib/utils";
import { EmployeePortrait } from "../design/portrait.tsx";
import type { ProjectChange } from "../../work/contract.ts";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { NativeSelect } from "@/components/ui/native-select";
import { Textarea } from "@/components/ui/textarea";

/**
 * Hiring: choose a role template, adjust its name, responsibilities and model, see the
 * access it starts with, then hire. The template is copied; later edits stay on the employee.
 */
export function HireSheet() {
  const hireOpen = useUi((state) => state.hireOpen);
  // Each opening starts from the roles again.
  const opening = useUi((state) => state.hireOpenings);
  return (
    <Sheet open={hireOpen} onOpenChange={ui.setHireOpen}>
      <SheetContent
        side="right"
        className="w-[460px] max-w-full gap-0 bg-sheet p-0 sm:max-w-[460px]"
      >
        <HireForm key={opening} />
      </SheetContent>
    </Sheet>
  );
}

function HireForm() {
  const roles = useRoles();
  const catalog = useModels().data;
  const hireEmployee = useHire();
  const [template, setTemplate] = useState<RoleTemplate>();
  const [name, setName] = useState("");
  const [responsibilities, setResponsibilities] = useState("");
  const [model, setModel] = useState<string>();
  const [error, setError] = useState<string>();
  const busy = hireEmployee.isPending;
  const chosenModel = model ?? catalog?.defaults.employee;
  const option = catalog?.models.find((m) => m.id === chosenModel);
  const choose = (role: RoleTemplate) => {
    setTemplate(role);
    setName(role.name);
    setResponsibilities(role.responsibilities);
    setModel(undefined);
    setError(undefined);
  };
  const hire = () => {
    if (!template) return;
    setError(undefined);
    hireEmployee.mutate(
      {
        template: template.id,
        name: name.trim(),
        responsibilities: responsibilities.trim(),
        ...(chosenModel ? { model: chosenModel } : {}),
      },
      {
        onSuccess: () => ui.setHireOpen(false),
        onError: (failure) =>
          setError(
            failure instanceof ApiError && failure.status === 400
              ? "Give the employee a name and responsibilities."
              : "The hire didn't go through. Try again.",
          ),
      },
    );
  };
  return (
    <>
      <div className="flex items-center gap-2 px-5 pt-5 pb-3">
        {template && (
          <button
            type="button"
            aria-label="Back to roles"
            className="text-ink-3 hover:text-ink-2"
            onClick={() => setTemplate(undefined)}
          >
            <ChevronLeft className="size-4" />
          </button>
        )}
        <SheetTitle className="text-heading font-semibold text-ink">
          {template ? `Hire ${template.name || "a custom role"}` : "Hire"}
        </SheetTitle>
      </div>
      <div className="flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto px-5 pb-6">
        {!template ? (
          <>
            <p className="text-body text-ink-2">
              Start from a role. You can change everything before and after hiring.
            </p>
            {roles.isPending ? (
              <Spinner />
            ) : roles.isError ? (
              <p role="alert" className="text-body text-ink-3">
                {problemOf(roles.error, "Roles are unavailable.")}
              </p>
            ) : (
              <div className="flex flex-col gap-2.5">
                {roles.data.map((role) => (
                  <button
                    key={role.id}
                    type="button"
                    aria-label={role.name || "Custom"}
                    onClick={() => choose(role)}
                    className="flex flex-col items-start gap-1 rounded-card bg-sheet-tint p-4 text-left transition duration-150 hover:-translate-y-px hover:bg-sheet hover:shadow-raised"
                  >
                    <span className="text-heading font-semibold text-ink">
                      {role.name || "Custom"}
                    </span>
                    <span className="text-detail text-ink-2">{role.summary}</span>
                  </button>
                ))}
              </div>
            )}
          </>
        ) : (
          <form
            className="flex flex-col gap-5"
            onSubmit={(event) => {
              event.preventDefault();
              hire();
            }}
          >
            <Field label="Name">
              <Input
                value={name}
                maxLength={80}
                placeholder="What they're called"
                onChange={(event) => setName(event.target.value)}
              />
            </Field>
            <Field label="Responsibilities" hint="Every turn starts from these.">
              <Textarea
                className="min-h-36 resize-y leading-[1.4]"
                value={responsibilities}
                maxLength={2000}
                placeholder="What they're accountable for, and how they work"
                onChange={(event) => setResponsibilities(event.target.value)}
              />
            </Field>
            <div className="flex flex-col gap-1.5">
              <span className="text-label font-medium text-ink-3">Model</span>
              <div className="flex items-center gap-3 rounded-control bg-well px-2.5 py-2">
                <div className="flex min-w-0 flex-col">
                  <span className="text-body font-semibold text-ink" data-testid="hire-model">
                    {option?.label ?? chosenModel ?? "Default"}
                  </span>
                  {option && (
                    <span className="text-detail text-ink-3">
                      {option.provider} · {perTurn(option)}
                    </span>
                  )}
                </div>
                <span className="ml-auto" />
                {catalog && chosenModel && (
                  <ModelPicker
                    catalog={catalog}
                    value={chosenModel}
                    onChange={setModel}
                    trigger={
                      <Button variant="quiet" size="compact" aria-label="Choose model">
                        Change <ChevronDown />
                      </Button>
                    }
                  />
                )}
              </div>
            </div>
            <div className="flex flex-col gap-1.5">
              <span className="text-label font-medium text-ink-3">Starts with access to</span>
              <ul aria-label="Starting access" className="flex flex-col gap-1">
                {template.capabilities.map((capability) => (
                  <li key={capability} className="flex items-center gap-2 text-body text-ink-2">
                    <KeyRound className="size-3.5 shrink-0 text-ink-3" aria-hidden />
                    {accessTitle(capability)}
                  </li>
                ))}
              </ul>
              <span className="text-detail text-ink-3">
                Change it on their Access tab at any time.
              </span>
            </div>
            {error && (
              <p role="alert" className="text-detail text-red">
                {error}
              </p>
            )}
            <Button
              variant="aurora"
              type="submit"
              disabled={busy || !name.trim() || !responsibilities.trim()}
              className="self-start"
            >
              <UserPlus /> {busy ? "Hiring…" : "Hire"}
            </Button>
          </form>
        )}
      </div>
    </>
  );
}

/** The end of the chosen day, in the owner's time zone. */
export const endOfDay = (date: string) => new Date(`${date}T23:59:00`).toISOString();

/** A new work item: what, who owns it, why, by when and which project it is in. Its thread opens. */
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
