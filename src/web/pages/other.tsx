import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { inboxEmpty, templateTitle } from "../app/names.ts";
import { EmployeePortrait } from "../design/portrait.tsx";
import { dollars, spend } from "../design/model-picker.tsx";
import { EmptyNote, LiveTag, PageBody, PageHeader, SectionHeader } from "../design/primitives.tsx";
import { SegmentedTabs } from "../design/tabs.tsx";
import { DriveConnection } from "./drive.tsx";

export function InboxPage() {
  return (
    <PageBody>
      <PageHeader title="Inbox" />
      <EmptyNote>{inboxEmpty}</EmptyNote>
    </PageBody>
  );
}

/** What each employee has actually spent on models, from their runtimes. */
export function MoneyPage() {
  const { employees, statusOf, modelOf } = useWorkspace();
  const rows = employees.map((employee) => {
    const usage = valueOf(statusOf(employee.id))?.usage;
    return { employee, total: usage ? spend(usage.models).total : undefined };
  });
  const total = rows.reduce((sum, row) => sum + (row.total ?? 0), 0);
  return (
    <PageBody>
      <PageHeader title="Money" subtitle={`Model spend so far: ${dollars(total)}`} />
      <div className="flex flex-col gap-2">
        <SectionHeader title="Spend by employee" count={rows.length}>
          <LiveTag />
        </SectionHeader>
        {rows.length === 0 && <EmptyNote>No employees yet.</EmptyNote>}
        {rows.map(({ employee, total: spent }) => (
          <div
            key={employee.id}
            className="flex items-center gap-3 px-3 py-2.5"
            data-testid="employee-spend"
          >
            <EmployeePortrait employee={employee} size={28} />
            <div className="flex min-w-0 flex-col gap-px">
              <span className="text-body font-semibold text-ink">{employee.name}</span>
              <span className="text-detail text-ink-3">
                {[
                  templateTitle(employee.template) !== employee.name &&
                    templateTitle(employee.template),
                  modelOf(employee.model)?.label ?? employee.model,
                ]
                  .filter(Boolean)
                  .join(" · ")}
              </span>
            </div>
            <span className="ml-auto text-body tabular-nums text-ink">
              {spent === undefined ? "Nothing yet" : dollars(spent)}
            </span>
          </div>
        ))}
      </div>
      <div className="flex flex-col gap-2">
        <SectionHeader title="Budgets" />
        <EmptyNote>
          Budgets and spending limits aren't available yet, so nothing can be purchased.
        </EmptyNote>
      </div>
    </PageBody>
  );
}

/** Installed apps and account connections, switched in the page so a phone reaches both. */
export function AppsPage({ section }: { section: "installed" | "connections" }) {
  const { businessId, actions } = useWorkspace();
  return (
    <PageBody>
      <PageHeader title={section === "installed" ? "Installed" : "Connections"}>
        <SegmentedTabs
          label="Apps and connections"
          value={section}
          options={[
            { value: "installed", title: "Installed" },
            { value: "connections", title: "Connections" },
          ]}
          onChange={(next) => actions.selectPage({ kind: "apps", section: next })}
        />
      </PageHeader>
      {section === "installed" ? (
        <EmptyNote>Installed apps arrive with T1.</EmptyNote>
      ) : (
        <>
          {businessId && <DriveConnection businessId={businessId} />}
          <div className="flex flex-col gap-2">
            <SectionHeader title="Other accounts" />
            <EmptyNote>GitHub, Cloudflare, Meta, Ramp and other accounts arrive with T1.</EmptyNote>
          </div>
        </>
      )}
    </PageBody>
  );
}
