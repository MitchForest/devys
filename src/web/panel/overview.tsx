import { Code2, FileText, Plus } from "lucide-react";
import { useState } from "react";
import type { Project } from "../../work/contract.ts";
import type { Ref } from "../../protocol/ref.ts";
import { useEmployees, useProjects, useWork } from "../app/data.ts";
import { filterOf } from "../app/names.ts";
import { useNav } from "../app/navigation.ts";
import { ui } from "../app/ui.ts";
import { EmployeePortrait } from "../design/portrait.tsx";
import { EmptyNote } from "../design/primitives.tsx";
import { deadline, money } from "../lib/format.ts";
import { kindOf, useRecordTitle } from "./layers/titles.ts";
import { WorkRow } from "./work.tsx";
import { PanelBody, PanelHeader, PanelSection } from "./panel.tsx";

const groups = [
  { value: "needsYou", title: "Needs you" },
  { value: "inProgress", title: "In progress" },
  { value: "waiting", title: "Waiting" },
] as const;

/**
 * A channel's permanent view: what the project is for and by when, who is on it, its work by
 * status and the records it keeps. Everything opens a thread or a layer; the project itself is
 * changed by asking in its channel.
 */
export function Overview({ projectId, close }: { projectId: string; close: () => void }) {
  const project = useProjects().data?.find((p) => p.id === projectId);
  return (
    <section
      aria-label={project ? `${project.name} overview` : "Project"}
      className="flex h-full flex-col"
    >
      <PanelHeader title="Overview" close={close} />
      <PanelBody>
        {project ? (
          <ProjectSummary project={project} />
        ) : (
          <EmptyNote>This project no longer exists.</EmptyNote>
        )}
      </PanelBody>
    </section>
  );
}

/** A project at a glance: goal, deadline, budget, lead, team, progress, work and kept records. */
export function ProjectSummary({ project }: { project: Project }) {
  const nav = useNav();
  const employees = useEmployees();
  const allWork = useWork().data;
  const recordTitle = useRecordTitle();
  const [showDone, setShowDone] = useState(false);
  const work = (allWork ?? []).filter((item) => item.project_id === project.id);
  const done = work.filter((item) => filterOf(item.state) === "done");
  const lead = employees.find((e) => e.id === project.lead_employee_id);
  const members = employees.filter(
    (e) => project.member_ids.includes(e.id) && e.id !== project.lead_employee_id,
  );
  const kept = project.items.filter((item) => kindOf(item.ref));
  const open = (record: Ref) => nav.openLayer({ kind: "record", ref: record });
  return (
    <>
      <div className="flex flex-col gap-3">
        {project.goal && <p className="text-body text-ink">{project.goal}</p>}
        <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-detail">
          {project.deadline && (
            <>
              <dt className="text-ink-3">Deadline</dt>
              <dd className="text-ink">{deadline(project.deadline)}</dd>
            </>
          )}
          {project.budget && (
            <>
              <dt className="text-ink-3">Budget</dt>
              <dd className="text-ink">{money(project.budget)}</dd>
            </>
          )}
          {lead && (
            <>
              <dt className="text-ink-3">Lead</dt>
              <dd>
                <button
                  type="button"
                  onClick={() => nav.message(lead.id)}
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
                    onClick={() => nav.message(member.id)}
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
      <PanelSection
        title="Work"
        action={
          <button
            type="button"
            onClick={() => ui.newWorkItem({ projectId: project.id })}
            className="text-caption text-ink-3 hover:text-ink-2"
          >
            <Plus className="inline size-3" /> Thread
          </button>
        }
      >
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
      {kept.length > 0 && (
        <PanelSection title="Kept" count={kept.length}>
          {kept.map((item) => (
            <KeptRow
              key={item.id}
              title={recordTitle(item.ref)}
              code={kindOf(item.ref)?.kind === "code/session"}
              open={() => open(item.ref)}
            />
          ))}
        </PanelSection>
      )}
    </>
  );
}

function KeptRow({ title, code, open }: { title: string; code: boolean; open: () => void }) {
  const Icon = code ? Code2 : FileText;
  return (
    <button
      type="button"
      onClick={open}
      className="-mx-2 flex items-center gap-2 rounded-control px-2 py-1.5 text-left text-detail text-ink hover:bg-sheet-tint"
    >
      <Icon className="size-4 shrink-0 text-ink-3" />
      <span className="truncate">{title}</span>
    </button>
  );
}
