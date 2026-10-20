import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { templateTitle } from "../app/names.ts";
import { EmployeePortrait } from "../design/portrait.tsx";
import { dollars, spend } from "../design/model-picker.tsx";
import { EmptyNote, LiveTag, PageBody, PageHeader, SectionHeader } from "../design/primitives.tsx";
import { DriveConnection } from "./drive.tsx";

export function InboxPage() {
  return (
    <PageBody>
      <PageHeader title="Inbox" />
      <EmptyNote>Mail arrives with E1.</EmptyNote>
    </PageBody>
  );
}

/** What each employee has actually spent on models, from their runtimes. */
export function MoneyPage() {
  const { employees, statusOf, modelOf } = useWorkspace();
  const rows = employees.map((employee) => {
    const usage = valueOf(statusOf(employee.id))?.usage;
    return { employee, total: usage ? spend(usage.models).total : 0 };
  });
  const total = rows.reduce((sum, row) => sum + row.total, 0);
  return (
    <PageBody>
      <PageHeader title="Money" subtitle={`${dollars(total)} spent on models`} />
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
            <span className="ml-auto text-body tabular-nums text-ink">{dollars(spent)}</span>
          </div>
        ))}
      </div>
      <div className="flex flex-col gap-2">
        <SectionHeader title="Budgets" />
        <EmptyNote>Budgets arrive with P1.</EmptyNote>
      </div>
    </PageBody>
  );
}

export function AppsPage({ section }: { section: "installed" | "connections" }) {
  const { businessId } = useWorkspace();
  return (
    <PageBody>
      <PageHeader title={section === "installed" ? "Installed" : "Connections"} />
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
