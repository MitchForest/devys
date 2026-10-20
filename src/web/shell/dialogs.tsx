import { ChevronDown, ChevronLeft, KeyRound, UserPlus } from "lucide-react";
import { useEffect, useState } from "react";
import { ApiError, type RoleTemplate } from "../app/api.ts";
import { accessTitle } from "../app/names.ts";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { Field, fieldClass } from "../design/fields.tsx";
import { ModelPicker, perTurn } from "../design/model-picker.tsx";
import { Spinner } from "../design/spinner.tsx";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Sheet, SheetContent, SheetTitle } from "@/components/ui/sheet";
import { cn } from "@/lib/utils";

/**
 * Hiring: choose a role template, adjust its name, responsibilities and model, see the
 * access it starts with, then hire. The template is copied; later edits stay on the employee.
 */
export function HireSheet() {
  const { hireOpen, actions, roles, models } = useWorkspace();
  const [template, setTemplate] = useState<RoleTemplate>();
  const [name, setName] = useState("");
  const [responsibilities, setResponsibilities] = useState("");
  const [model, setModel] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  useEffect(() => {
    if (hireOpen) return;
    setTemplate(undefined);
    setError(undefined);
    setBusy(false);
  }, [hireOpen]);
  const catalog = valueOf(models);
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
    setBusy(true);
    setError(undefined);
    actions
      .hire({
        template: template.id,
        name: name.trim(),
        responsibilities: responsibilities.trim(),
        ...(chosenModel ? { model: chosenModel } : {}),
      })
      .then(() => actions.setHireOpen(false))
      .catch((failure: unknown) =>
        setError(
          failure instanceof ApiError && failure.status === 400
            ? "Give the employee a name and responsibilities."
            : "The hire didn't go through. Try again.",
        ),
      )
      .finally(() => setBusy(false));
  };
  return (
    <Sheet open={hireOpen} onOpenChange={actions.setHireOpen}>
      <SheetContent
        side="right"
        className="w-[460px] max-w-full gap-0 bg-sheet p-0 sm:max-w-[460px]"
      >
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
              {roles.status === "loading" ? (
                <Spinner />
              ) : roles.status === "failed" ? (
                <p className="text-body text-ink-3">{roles.message}</p>
              ) : (
                <div className="flex flex-col gap-2.5">
                  {roles.value.map((role) => (
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
                <input
                  className={fieldClass}
                  value={name}
                  maxLength={80}
                  placeholder="What they're called"
                  onChange={(event) => setName(event.target.value)}
                />
              </Field>
              <Field label="Responsibilities" hint="Every turn starts from these.">
                <textarea
                  className={cn(fieldClass, "min-h-36 resize-y leading-[1.4]")}
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
                        <DevysButton kind="quiet" compact aria-label="Choose model">
                          Change <ChevronDown />
                        </DevysButton>
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
              <DevysButton
                kind="aurora"
                type="submit"
                disabled={busy || !name.trim() || !responsibilities.trim()}
                className="self-start"
              >
                <UserPlus /> {busy ? "Hiring…" : "Hire"}
              </DevysButton>
            </form>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}

/** The end of the chosen day, in the owner's time zone. */
const endOfDay = (date: string) => new Date(`${date}T23:59:00`).toISOString();

/** A new task: what, who owns it, why, by when and where it is shown. */
export function NewTaskDialog() {
  const { taskDefaults, actions, employees, spaces, operations } = useWorkspace();
  const [title, setTitle] = useState("");
  const [owner, setOwner] = useState("");
  const [objective, setObjective] = useState("");
  const [due, setDue] = useState("");
  const [spaceId, setSpaceId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  useEffect(() => {
    if (!taskDefaults) return;
    setTitle("");
    setObjective("");
    setDue("");
    setOwner(taskDefaults.owner ?? operations?.id ?? "");
    setSpaceId(taskDefaults.spaceId ?? "");
    setError(undefined);
    setBusy(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [taskDefaults]);
  const create = () => {
    if (!title.trim() || !owner) return;
    setBusy(true);
    setError(undefined);
    actions
      .createTask({
        title: title.trim().slice(0, 200),
        owner,
        ...(objective.trim() ? { objective: objective.trim() } : {}),
        ...(due ? { dueAt: endOfDay(due) } : {}),
        ...(spaceId ? { spaceId } : {}),
      })
      .then(() => actions.closeNewTask())
      .catch(() => setError("The task couldn't be saved. Try again."))
      .finally(() => setBusy(false));
  };
  return (
    <Dialog open={Boolean(taskDefaults)} onOpenChange={(open) => !open && actions.closeNewTask()}>
      <DialogContent className="w-[480px] max-w-[calc(100%-2rem)] gap-0 rounded-card! bg-sheet p-0 shadow-raised sm:max-w-[480px]">
        <form
          className="flex flex-col gap-4 p-6"
          onSubmit={(event) => {
            event.preventDefault();
            create();
          }}
        >
          <DialogTitle className="text-heading font-semibold text-ink">New task</DialogTitle>
          <Field label="Title">
            <input
              autoFocus
              className={fieldClass}
              value={title}
              maxLength={200}
              placeholder="Something the business owes"
              onChange={(event) => setTitle(event.target.value)}
            />
          </Field>
          <div className="grid grid-cols-2 gap-3 max-sm:grid-cols-1">
            <Field label="Owner">
              <select
                className={fieldClass}
                value={owner}
                onChange={(event) => setOwner(event.target.value)}
              >
                {employees.map((employee) => (
                  <option key={employee.id} value={employee.id}>
                    {employee.name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Due">
              <input
                type="date"
                className={fieldClass}
                value={due}
                onChange={(event) => setDue(event.target.value)}
              />
            </Field>
          </div>
          <Field label="Objective">
            <textarea
              className={cn(fieldClass, "min-h-20 resize-y leading-[1.4]")}
              value={objective}
              maxLength={4000}
              placeholder="What done looks like"
              onChange={(event) => setObjective(event.target.value)}
            />
          </Field>
          <Field label="Space">
            <select
              className={fieldClass}
              value={spaceId}
              onChange={(event) => setSpaceId(event.target.value)}
            >
              <option value="">No space</option>
              {(valueOf(spaces) ?? []).map((space) => (
                <option key={space.id} value={space.id}>
                  {space.name}
                </option>
              ))}
            </select>
          </Field>
          {error && (
            <p role="alert" className="text-detail text-red">
              {error}
            </p>
          )}
          <div className="flex justify-end gap-2 pt-1">
            <DevysButton kind="quiet" onClick={actions.closeNewTask}>
              Cancel
            </DevysButton>
            <DevysButton kind="aurora" type="submit" disabled={busy || !title.trim() || !owner}>
              {busy ? "Creating…" : "Create task"}
            </DevysButton>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
