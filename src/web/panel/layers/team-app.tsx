/**
 * A remote app (`devys:team/app/<id>`): an MCP server the business connects. Its card in a
 * conversation and in Needs you shows its logo, name and why, and Connect; its layer is the one
 * review card (what it can do on its own, what asks first, what employees never get, and who uses
 * it), where Turn on makes the owner's choices its policy. No addresses, scopes or tool names show.
 */
import { Check, Plug } from "lucide-react";
import { useState } from "react";
import type { InstalledApp, Line } from "../../../apps/contract.ts";
import type { AppReview } from "../../../app/wire.ts";
import { useAppReview, useApps, useEmployees } from "../../app/data.ts";
import { useAcceptApp, useConnectApp } from "../../app/mutations.ts";
import { useNav } from "../../app/navigation.ts";
import { ref } from "../../../protocol/ref.ts";
import { EmptyNote, StatusChip } from "../../design/primitives.tsx";
import { Button } from "@/components/ui/button";
import { NativeSelect } from "@/components/ui/native-select";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";

/** An app's logo as Devys serves it, or its first letter on a tile. */
export function AppLogo({
  logo,
  name,
  size = 22,
}: {
  logo: string | null | undefined;
  name: string;
  size?: number;
}) {
  const [broken, setBroken] = useState(false);
  const box = { width: size, height: size };
  if (logo && !broken)
    return (
      <img
        src={logo}
        alt=""
        style={box}
        onError={() => setBroken(true)}
        className="shrink-0 rounded-[22%] bg-sheet object-contain shadow-resting"
      />
    );
  return (
    <span
      style={{ ...box, fontSize: Math.round(size * 0.5) }}
      className="grid shrink-0 place-items-center rounded-[22%] bg-indigo/14 font-semibold text-indigo"
      aria-hidden
    >
      {name.trim().charAt(0).toUpperCase() || "A"}
    </span>
  );
}

/** One of the business's remote apps, from the directory. */
export const useRemoteApp = (id: string) =>
  useApps().data?.find((app) => app.id === id && app.state !== null);

/** Connect, Reconnect or Review, as the app's state calls for. */
function AppAction({ app, compact }: { app: InstalledApp; compact?: boolean }) {
  const connect = useConnectApp();
  const nav = useNav();
  const size = compact ? "compact" : "regular";
  if (app.state === "connecting" || app.state === "lapsed")
    return (
      <Button variant="aurora" size={size} onClick={() => connect(app.id)}>
        <Plug /> {app.state === "lapsed" ? "Reconnect" : "Connect"}
      </Button>
    );
  if (app.state === "review")
    return (
      <Button
        variant="aurora"
        size={size}
        onClick={() => nav.openLayer({ kind: "record", ref: ref("team", "app", app.id) })}
      >
        Review
      </Button>
    );
  return (
    <StatusChip tone="done" small>
      On
    </StatusChip>
  );
}

const card =
  "mx-auto flex w-full max-w-[520px] items-center gap-2.5 rounded-card border border-hairline bg-sheet px-3 py-2 text-left shadow-resting";

/** The connect card in a conversation: logo, name, the one line why, and Connect. */
export function AppCard({ id, text }: { id: string; text: string }) {
  const app = useRemoteApp(id);
  const nav = useNav();
  if (!app)
    return (
      <div className={card}>
        <Plug className="size-4 text-indigo" />
        <span className="min-w-0 truncate text-detail text-ink-2">{text}</span>
      </div>
    );
  const why = text || app.summary;
  return (
    <div className={card} data-testid="app-card">
      <button
        type="button"
        title="Open"
        onClick={() => nav.openLayer({ kind: "record", ref: ref("team", "app", app.id) })}
        className="flex min-w-0 flex-1 items-center gap-2.5 text-left"
      >
        <AppLogo logo={app.logo} name={app.name} size={30} />
        <span className="flex min-w-0 flex-col">
          <span className="truncate text-control font-semibold text-ink">{app.name}</span>
          {why && <span className="line-clamp-2 text-caption text-ink-3">{why}</span>}
        </span>
      </button>
      <AppAction app={app} compact />
    </div>
  );
}

const sections: { line: Line; title: string }[] = [
  { line: "own", title: "Can do on its own" },
  { line: "ask", title: "Asks you first" },
  { line: "never", title: "Never available to employees" },
];

const lineNames: Record<Line, string> = {
  own: "On its own",
  ask: "Asks you first",
  never: "Never",
};

/** The one review: suggested lines, who uses it; Turn on (or Save) makes it the policy. */
function Review({ app, review }: { app: InstalledApp; review: AppReview }) {
  const accept = useAcceptApp();
  const employees = useEmployees();
  const [editing, setEditing] = useState(false);
  const [lines, setLines] = useState<Record<string, Line>>(() =>
    Object.fromEntries(review.tools.map((tool) => [tool.capability, tool.line])),
  );
  const [users, setUsers] = useState<string[]>(() =>
    review.employees.filter((employee) => employee.uses).map((employee) => employee.id),
  );
  const on = app.state === "on";
  const turnOn = () =>
    accept.mutate(
      { app: app.id, acceptance: { lines, employees: users } },
      { onSuccess: () => setEditing(false) },
    );
  return (
    <div className="flex flex-col gap-4" data-testid="app-review">
      {sections.map(({ line, title }) => {
        const tools = review.tools.filter((tool) => (lines[tool.capability] ?? tool.line) === line);
        if (!tools.length && !editing) return null;
        return (
          <section key={line} className="flex flex-col gap-1.5">
            <div className="flex items-baseline gap-2">
              <span className="text-label font-medium text-ink-3">{title}</span>
              {!editing && (
                <button
                  type="button"
                  onClick={() => setEditing(true)}
                  className="ml-auto text-caption text-ink-3 hover:text-ink-2"
                >
                  Change
                </button>
              )}
            </div>
            {tools.map((tool) => (
              <div
                key={tool.capability}
                className="flex items-center gap-2 rounded-control bg-sheet-tint px-2.5 py-1.5"
                title={tool.description}
              >
                <span className="min-w-0 flex-1 truncate text-detail text-ink">{tool.title}</span>
                {editing && !tool.fixed && (
                  <NativeSelect
                    density="compact"
                    aria-label={`${tool.title}: who decides`}
                    value={lines[tool.capability]}
                    onChange={(event) =>
                      setLines({ ...lines, [tool.capability]: event.target.value as Line })
                    }
                    className="w-auto"
                  >
                    {(["own", "ask", "never"] as const).map((each) => (
                      <option key={each} value={each}>
                        {lineNames[each]}
                      </option>
                    ))}
                  </NativeSelect>
                )}
              </div>
            ))}
          </section>
        );
      })}
      <section className="flex flex-col gap-1.5">
        <div className="flex items-baseline gap-2">
          <span className="text-label font-medium text-ink-3">Who can use it</span>
          {!editing && (
            <button
              type="button"
              onClick={() => setEditing(true)}
              className="ml-auto text-caption text-ink-3 hover:text-ink-2"
            >
              Change
            </button>
          )}
        </div>
        {(editing ? employees : employees.filter((employee) => users.includes(employee.id))).map(
          (employee) => (
            <div key={employee.id} className="flex items-center gap-2 px-2.5 py-1">
              <span className="min-w-0 flex-1 truncate text-detail text-ink">{employee.name}</span>
              {editing && (
                <Switch
                  aria-label={`${employee.name} uses ${app.name}`}
                  checked={users.includes(employee.id)}
                  onCheckedChange={(checked) =>
                    setUsers(
                      checked ? [...users, employee.id] : users.filter((id) => id !== employee.id),
                    )
                  }
                />
              )}
            </div>
          ),
        )}
        {!editing && !users.length && <span className="px-2.5 text-detail text-ink-3">No one</span>}
      </section>
      {(!on || editing) && (
        <div className="flex items-center gap-2">
          <Button variant="aurora" onClick={turnOn} disabled={accept.isPending}>
            <Check /> {on ? "Save" : "Turn on"}
          </Button>
          {editing && on && (
            <Button variant="quiet" onClick={() => setEditing(false)}>
              Cancel
            </Button>
          )}
        </div>
      )}
    </div>
  );
}

/** A remote app as a layer: connect it, or its review card. */
export function AppLayer({ id }: { id: string }) {
  const app = useRemoteApp(id);
  return (
    <div className="h-full overflow-y-auto px-4 pt-3.5 pb-6">
      {app ? <AppDetail app={app} /> : <EmptyNote>This app was removed.</EmptyNote>}
    </div>
  );
}

function AppDetail({ app }: { app: InstalledApp }) {
  const reviewing = app.state === "review" || app.state === "on";
  const review = useAppReview(app.id);
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-3">
        <AppLogo logo={app.logo} name={app.name} size={40} />
        <div className="flex min-w-0 flex-col">
          <span className="truncate text-heading font-semibold text-ink">{app.name}</span>
          {app.summary && (
            <span className="line-clamp-2 text-detail text-ink-2">{app.summary}</span>
          )}
        </div>
      </div>
      {!reviewing && (
        <div className={cn("flex flex-col items-start gap-2")}>
          <span className="text-detail text-ink-2">
            {app.state === "lapsed"
              ? `${app.name}'s sign-in stopped working. Sign in again to keep using it.`
              : `Sign in to ${app.name} to connect it. You choose what employees may do next.`}
          </span>
          <AppAction app={app} />
        </div>
      )}
      {reviewing && review.data && <Review key={`${app.state}`} app={app} review={review.data} />}
    </div>
  );
}
