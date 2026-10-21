import { FileText, Pencil, Plus } from "lucide-react";
import { useState } from "react";
import type { Project, ProjectChange } from "../app/api.ts";
import { filterOf, useWorkspace, valueOf } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { Field, fieldClass } from "../design/fields.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { EmptyNote } from "../design/primitives.tsx";
import { WorkRow } from "../pages/work.tsx";
import { PanelBody, PanelHeader, PanelSection } from "./panel.tsx";
import { cn } from "@/lib/utils";

const groups = [
  { value: "needsYou", title: "Needs you" },
  { value: "inProgress", title: "In progress" },
  { value: "waiting", title: "Waiting" },
] as const;

export const formatMoney = (budget: { cents: number; currency: string }) =>
  (budget.cents / 100).toLocaleString(undefined, {
    style: "currency",
    currency: budget.currency,
    maximumFractionDigits: 0,
  });

const formatDeadline = (deadline: string) => {
  const date = new Date(`${deadline}T00:00:00`);
  const days = Math.ceil((date.getTime() - Date.now()) / 86_400_000);
  const label = date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  return days < 0
    ? `${label} · ${-days}d late`
    : days === 0
      ? `${label} · today`
      : `${label} · ${days}d`;
};

/**
 * A channel's permanent view: what the project is for and by when, who is on it, its work by
 * status and the records it keeps. Everything opens a thread or a layer.
 */
export function Overview({ projectId, close }: { projectId: string; close: () => void }) {
  const state = useWorkspace();
  const { actions, employees, artifacts, artifactName } = state;
  const [editing, setEditing] = useState(false);
  const [showDone, setShowDone] = useState(false);
  const project = valueOf(state.projects)?.find((p) => p.id === projectId);
  if (!project)
    return (
      <section className="flex h-full flex-col">
        <PanelHeader title="Project" close={close} />
        <PanelBody>
          <EmptyNote>This project no longer exists.</EmptyNote>
        </PanelBody>
      </section>
    );
  const work = (valueOf(state.work) ?? []).filter((item) => item.project_id === project.id);
  const done = work.filter((item) => filterOf(item.state) === "done");
  const lead = employees.find((e) => e.id === project.lead_employee_id);
  const members = employees.filter(
    (e) => project.member_ids.includes(e.id) && e.id !== project.lead_employee_id,
  );
  const pages = project.items.filter(
    (item) => item.kind === "artifact" && artifacts.some((a) => a.id === item.ref),
  );
  const files = project.items.filter((item) => item.kind === "file");
  return (
    <section aria-label={`${project.name} overview`} className="flex h-full flex-col">
      <PanelHeader title="Overview" close={close}>
        {!editing && (
          <DevysButton
            kind="quiet"
            compact
            aria-label="Edit project"
            onClick={() => setEditing(true)}
          >
            <Pencil />
          </DevysButton>
        )}
      </PanelHeader>
      <PanelBody>
        {editing ? (
          <EditProject project={project} done={() => setEditing(false)} />
        ) : (
          <div className="flex flex-col gap-3">
            {project.goal ? (
              <p className="text-body text-ink">{project.goal}</p>
            ) : (
              <button
                type="button"
                onClick={() => setEditing(true)}
                className="self-start text-detail text-ink-3 hover:text-ink-2"
              >
                Add a goal
              </button>
            )}
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-detail">
              {project.deadline && (
                <>
                  <dt className="text-ink-3">Deadline</dt>
                  <dd className="text-ink">{formatDeadline(project.deadline)}</dd>
                </>
              )}
              {project.budget && (
                <>
                  <dt className="text-ink-3">Budget</dt>
                  <dd className="text-ink">{formatMoney(project.budget)}</dd>
                </>
              )}
              {lead && (
                <>
                  <dt className="text-ink-3">Lead</dt>
                  <dd>
                    <button
                      type="button"
                      onClick={() => actions.message(lead.id)}
                      className="flex items-center gap-1.5 text-ink hover:underline"
                    >
                      <EmployeePortrait employee={lead} size={18} />
                      {lead.name}
                    </button>
                  </dd>
                </>
              )}
              {members.length > 0 && (
                <>
                  <dt className="text-ink-3">Team</dt>
                  <dd className="flex flex-wrap gap-1">
                    {members.map((member) => (
                      <button
                        key={member.id}
                        type="button"
                        title={member.name}
                        aria-label={member.name}
                        onClick={() => actions.message(member.id)}
                      >
                        <EmployeePortrait employee={member} size={20} />
                      </button>
                    ))}
                  </dd>
                </>
              )}
              {work.length > 0 && (
                <>
                  <dt className="text-ink-3">Progress</dt>
                  <dd className="flex items-center gap-2 text-ink">
                    <span className="h-1.5 w-24 overflow-hidden rounded-full bg-track">
                      <span
                        className="block h-full rounded-full bg-green"
                        style={{ width: `${(done.length / work.length) * 100}%` }}
                      />
                    </span>
                    {done.length} of {work.length}
                  </dd>
                </>
              )}
            </dl>
          </div>
        )}
        <PanelSection
          title="Work"
          action={
            <button
              type="button"
              onClick={() => actions.newTask({ projectId: project.id })}
              className="text-caption text-ink-3 hover:text-ink-2"
            >
              <Plus className="inline size-3" /> Thread
            </button>
          }
        >
          {work.length === 0 && (
            <span className="text-detail text-ink-3">
              No threads yet. Ask in the channel and work starts here.
            </span>
          )}
          {groups.map((group) => {
            const items = work.filter((item) => filterOf(item.state) === group.value);
            return (
              items.length > 0 && (
                <div key={group.value} className="flex flex-col">
                  <span className="pt-1.5 text-caption text-ink-3">{group.title}</span>
                  {items.map((item) => (
                    <WorkRow key={item.id} item={item} compact />
                  ))}
                </div>
              )
            );
          })}
          {done.length > 0 && (
            <div className="flex flex-col">
              <button
                type="button"
                onClick={() => setShowDone(!showDone)}
                aria-expanded={showDone}
                className="self-start pt-1.5 text-caption text-ink-3 hover:text-ink-2"
              >
                {showDone ? "Hide done" : `Done · ${done.length}`}
              </button>
              {showDone && done.map((item) => <WorkRow key={item.id} item={item} compact />)}
            </div>
          )}
        </PanelSection>
        {(pages.length > 0 || files.length > 0) && (
          <PanelSection title="Kept" count={pages.length + files.length}>
            {pages.map((item) => (
              <KeptRow
                key={item.id}
                title={artifactName(item.ref)}
                open={() => actions.openLayer({ kind: "artifact", id: item.ref })}
              />
            ))}
            {files.map((item) => (
              <KeptRow
                key={item.id}
                title={item.ref.split("/").at(-1)!}
                open={() => actions.openLayer({ kind: "file", path: item.ref })}
              />
            ))}
          </PanelSection>
        )}
      </PanelBody>
    </section>
  );
}

function KeptRow({ title, open }: { title: string; open: () => void }) {
  return (
    <button
      type="button"
      onClick={open}
      className="-mx-2 flex items-center gap-2 rounded-[9px] px-2 py-1.5 text-left text-detail text-ink hover:bg-sheet-tint"
    >
      <FileText className="size-4 shrink-0 text-ink-3" />
      <span className="truncate">{title}</span>
    </button>
  );
}

/** Name, goal, deadline, budget, lead and team, saved as one change. */
export function ProjectFields({
  initial,
  submit,
  cancel,
  submitLabel,
}: {
  initial: Partial<Project>;
  submit: (change: ProjectChange & { name: string }) => Promise<boolean>;
  cancel: () => void;
  submitLabel: string;
}) {
  const { employees, operations } = useWorkspace();
  const [name, setName] = useState(initial.name ?? "");
  const [goal, setGoal] = useState(initial.goal ?? "");
  const [deadline, setDeadline] = useState(initial.deadline ?? "");
  const [budget, setBudget] = useState(
    initial.budget ? String(Math.round(initial.budget.cents / 100)) : "",
  );
  const [lead, setLead] = useState(initial.lead_employee_id ?? operations?.id ?? "");
  const [members, setMembers] = useState<string[]>(initial.member_ids ?? []);
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
              ? { cents: Math.round(amount * 100), currency: initial.budget?.currency ?? "USD" }
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
        <input
          autoFocus
          className={fieldClass}
          value={name}
          maxLength={80}
          placeholder="Launch"
          onChange={(event) => setName(event.target.value)}
        />
      </Field>
      <Field label="Goal">
        <textarea
          className={cn(fieldClass, "min-h-16 resize-y leading-[1.4]")}
          value={goal}
          maxLength={500}
          placeholder="What done looks like (optional)"
          onChange={(event) => setGoal(event.target.value)}
        />
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Deadline">
          <input
            type="date"
            className={fieldClass}
            value={deadline}
            onChange={(event) => setDeadline(event.target.value)}
          />
        </Field>
        <Field label="Budget">
          <input
            inputMode="decimal"
            className={fieldClass}
            value={budget}
            placeholder="None"
            onChange={(event) => setBudget(event.target.value.replace(/[^0-9.]/g, ""))}
          />
        </Field>
      </div>
      <Field label="Lead">
        <select
          className={fieldClass}
          value={lead}
          onChange={(event) => setLead(event.target.value)}
        >
          {employees.map((employee) => (
            <option key={employee.id} value={employee.id}>
              {employee.name}
            </option>
          ))}
        </select>
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
        <DevysButton kind="quiet" onClick={cancel}>
          Cancel
        </DevysButton>
        <DevysButton kind="aurora" type="submit" disabled={busy || !name.trim()}>
          {busy ? "Saving…" : submitLabel}
        </DevysButton>
      </div>
    </form>
  );
}

function EditProject({ project, done }: { project: Project; done: () => void }) {
  const { actions } = useWorkspace();
  return (
    <ProjectFields
      initial={project}
      submitLabel="Save"
      cancel={done}
      submit={(change) => actions.updateProject(project.id, change)}
    />
  );
}
