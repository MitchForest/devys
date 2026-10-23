/**
 * Connect apps: the outside services a business connects (G4). Search across them, category
 * chips, the listed apps with their logos and Add, then whatever the MCP Registry finds; "N
 * connected" shows the business's own. Documents, Code and the browser are what employees do,
 * never apps here.
 */
import { ChevronLeft, ChevronRight, Search, X } from "lucide-react";
import { useEffect, useState } from "react";
import type { FoundApp, InstalledApp, ListedApp } from "../../apps/contract.ts";
import { ref } from "../../protocol/ref.ts";
import { useAppSearch, useApps, useListedApps } from "../app/data.ts";
import { useAddApp, useConnectApp, useRemoveApp } from "../app/mutations.ts";
import { useNav, useSettingsSection } from "../app/navigation.ts";
import { ui, useUi } from "../app/ui.ts";
import { AppLogo } from "../panel/layers/team-app.tsx";
import { Spinner } from "../design/spinner.tsx";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

/** The business's connected (or connecting) outside apps: remote apps, never built-in ones. */
export const useConnectedApps = () =>
  (useApps().data ?? []).filter(
    (app): app is InstalledApp & { state: NonNullable<InstalledApp["state"]> } =>
      Boolean(app.state),
  );

/** Up to three logos for the sidebar's button: the connected apps', else the listed ones'. */
export function useAppLogos() {
  const connected = useConnectedApps();
  const listed = useListedApps().data ?? [];
  const shown = connected.length ? connected : listed;
  return shown.slice(0, 3).map((app) => ({ name: app.name, logo: app.logo }));
}

/** The sidebar's Connect apps button: a wide pill with a few overlapping logos. */
export function ConnectAppsButton() {
  const logos = useAppLogos();
  return (
    <button
      type="button"
      onClick={() => ui.openConnect()}
      className="flex h-9 min-w-0 flex-1 items-center gap-2 rounded-full bg-sheet pr-3.5 pl-2 text-control font-medium text-ink shadow-resting transition hover:-translate-y-px"
    >
      {logos.length > 0 && (
        <span className="flex -space-x-1.5" aria-hidden>
          {logos.map((app) => (
            <span key={app.name} className="rounded-[22%] ring-2 ring-sheet">
              <AppLogo logo={app.logo} name={app.name} size={20} />
            </span>
          ))}
        </span>
      )}
      <span className="truncate">Connect apps</span>
    </button>
  );
}

/** The Connect apps sheet. */
export function ConnectAppsSheet() {
  const open = useUi((state) => state.connectOpen);
  const connectedShown = useUi((state) => state.connectedShown);
  return (
    <Dialog open={open} onOpenChange={(next) => !next && ui.closeConnect()}>
      <DialogContent
        showCloseButton={false}
        className="flex h-[min(680px,calc(100dvh-4rem))] w-[760px] max-w-[calc(100%-2rem)] flex-col gap-0 overflow-hidden rounded-card! bg-sheet p-0 shadow-raised sm:max-w-[760px]"
      >
        {connectedShown ? <ConnectedView /> : <Directory />}
      </DialogContent>
    </Dialog>
  );
}

function SheetHeader({
  title,
  back,
  trailing,
}: {
  title: string;
  back?: () => void;
  trailing?: React.ReactNode;
}) {
  return (
    <div className="flex shrink-0 items-center gap-2 px-6 pt-5 pb-3">
      {back && (
        <button
          type="button"
          aria-label="Back"
          onClick={back}
          className="-ml-1.5 grid size-7 place-items-center rounded-full text-ink-2 hover:bg-track"
        >
          <ChevronLeft className="size-4" />
        </button>
      )}
      <DialogTitle className="text-title font-semibold tracking-tight text-ink">
        {title}
      </DialogTitle>
      <span className="ml-auto" />
      {trailing}
      <button
        type="button"
        aria-label="Close"
        onClick={ui.closeConnect}
        className="grid size-7 place-items-center rounded-full text-ink-3 hover:bg-track hover:text-ink-2"
      >
        <X className="size-4" />
      </button>
    </div>
  );
}

/** Listed apps by category, search, and Add. */
function Directory() {
  const listed = useListedApps();
  const connected = useConnectedApps();
  const builtIn = new Set((useApps().data ?? []).filter((app) => !app.state).map((app) => app.id));
  const [query, setQuery] = useState("");
  const [typed, setTyped] = useState("");
  const [category, setCategory] = useState<string>();
  useEffect(() => {
    const timer = window.setTimeout(() => setTyped(query.trim()), 300);
    return () => window.clearTimeout(timer);
  }, [query]);
  const found = useAppSearch(typed);
  const apps = listed.data ?? [];
  const categories = [...new Set(apps.map((app) => app.category))];
  const searching = typed.length > 1;
  // Search finds listed apps first, then the Registry's; built-in apps are not outside apps.
  const results = (found.data ?? []).filter((app) => !builtIn.has(app.app));
  return (
    <>
      <SheetHeader
        title="Connect apps"
        trailing={
          connected.length > 0 && (
            <button
              type="button"
              onClick={() => ui.showConnected(true)}
              className="mr-1 flex items-center gap-0.5 text-control text-ink-2 hover:text-ink"
            >
              {connected.length} connected <ChevronRight className="size-3.5" />
            </button>
          )
        }
      />
      <div className="flex shrink-0 flex-col gap-3 px-6 pb-3">
        <label className="flex h-10 items-center gap-2 rounded-full bg-well px-3.5">
          <Search className="size-4 text-ink-3" />
          <input
            autoFocus
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search across apps and skills"
            aria-label="Search apps"
            className="min-w-0 flex-1 bg-transparent text-body text-ink outline-none placeholder:text-ink-3"
          />
        </label>
        {!searching && categories.length > 0 && (
          <div
            role="group"
            aria-label="Categories"
            className="flex gap-1.5 overflow-x-auto [scrollbar-width:none]"
          >
            {[undefined, ...categories].map((each) => (
              <button
                key={each ?? "all"}
                type="button"
                aria-pressed={category === each}
                onClick={() => setCategory(each)}
                className={cn(
                  "shrink-0 rounded-full px-3 py-1.5 text-control transition-colors",
                  category === each ? "bg-ink text-sheet" : "bg-well text-ink-2 hover:text-ink",
                )}
              >
                {each ?? "All"}
              </button>
            ))}
          </div>
        )}
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-6" data-testid="app-results">
        {searching ? (
          found.isFetching && !found.data ? (
            <div className="flex justify-center pt-10">
              <Spinner />
            </div>
          ) : results.length === 0 ? (
            <p className="pt-6 text-body text-ink-3">No apps found.</p>
          ) : (
            <AppGrid apps={results} />
          )
        ) : listed.isPending ? (
          <div className="flex justify-center pt-10">
            <Spinner />
          </div>
        ) : category ? (
          <AppGrid apps={apps.filter((app) => app.category === category)} />
        ) : (
          <div className="flex flex-col gap-6">
            <Section title="Recommended for you">
              <AppGrid apps={recommended(apps)} />
            </Section>
            {categories.map((each) => {
              const inCategory = apps.filter((app) => app.category === each);
              return (
                <Section
                  key={each}
                  title={each}
                  {...(inCategory.length > 4 ? { more: () => setCategory(each) } : {})}
                >
                  <AppGrid apps={inCategory.slice(0, 4)} />
                </Section>
              );
            })}
          </div>
        )}
      </div>
    </>
  );
}

/** The first app of each category not yet added: a little of everything, up to four. */
const recommended = (apps: readonly ListedApp[]) =>
  [...new Set(apps.map((app) => app.category))]
    .flatMap((category) => apps.find((app) => app.category === category && !app.installed) ?? [])
    .slice(0, 4);

function Section({
  title,
  more,
  children,
}: {
  title: string;
  more?: () => void;
  children: React.ReactNode;
}) {
  return (
    <section aria-label={title} className="flex flex-col gap-2">
      <div className="flex items-baseline">
        <h3 className="text-heading font-semibold text-ink">{title}</h3>
        {more && (
          <button
            type="button"
            onClick={more}
            className="ml-auto text-control text-ink-3 hover:text-ink-2"
          >
            View all
          </button>
        )}
      </div>
      {children}
    </section>
  );
}

function AppGrid({ apps }: { apps: readonly FoundApp[] }) {
  return (
    <div className="grid grid-cols-2 gap-x-6 gap-y-1 max-sm:grid-cols-1">
      {apps.map((app) => (
        <AppRow key={app.app} app={app} />
      ))}
    </div>
  );
}

/** One app: logo, name, a line about it, and Add (connecting it with its own sign-in). */
function AppRow({ app }: { app: FoundApp }) {
  const add = useAddApp();
  const connect = useConnectApp();
  const connected = useConnectedApps();
  const added = app.installed || connected.some((each) => each.name === app.name);
  const choose = () =>
    add.mutate(app.app, {
      onSuccess: ({ app: next }) => {
        if (next.state === "connecting" || next.state === "lapsed") connect(next.id);
      },
    });
  return (
    <div className="flex items-center gap-3 py-2.5" data-testid="app-row">
      <AppLogo logo={app.logo} name={app.name} size={40} />
      <div className="flex min-w-0 flex-col">
        <span className="truncate text-control font-semibold text-ink">{app.name}</span>
        {app.description && (
          <span className="line-clamp-1 text-detail text-ink-3">{app.description}</span>
        )}
      </div>
      <span className="ml-auto" />
      {added ? (
        <span className="text-caption text-ink-3">Added</span>
      ) : (
        <button
          type="button"
          aria-label={`Add ${app.name}`}
          onClick={choose}
          disabled={add.isPending}
          className="shrink-0 rounded-full bg-well px-3.5 py-1 text-control font-medium text-ink transition-colors hover:bg-track disabled:opacity-50"
        >
          Add
        </button>
      )}
    </div>
  );
}

function ConnectedView() {
  const connected = useConnectedApps();
  return (
    <>
      <SheetHeader title="Connected" back={() => ui.showConnected(false)} />
      <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-6">
        <ConnectedApps />
        {connected.length === 0 && <p className="text-body text-ink-3">Nothing connected yet.</p>}
      </div>
    </>
  );
}

/** The connected apps, each with where it stands and what to do next. */
export function ConnectedApps() {
  const connected = useConnectedApps();
  return (
    <div className="flex flex-col">
      {connected.map((app) => (
        <ConnectedRow key={app.id} app={app} />
      ))}
    </div>
  );
}

function ConnectedRow({ app }: { app: InstalledApp }) {
  const nav = useNav();
  const connect = useConnectApp();
  const remove = useRemoveApp();
  const inSettings = useSettingsSection() !== undefined;
  const review = () => {
    ui.closeConnect();
    if (inSettings) nav.closeSettings();
    nav.openLayer({ kind: "record", ref: ref("team", "app", app.id) });
  };
  return (
    <div className="flex items-center gap-3 py-2.5">
      <AppLogo logo={app.logo} name={app.name} size={36} />
      <div className="flex min-w-0 flex-col">
        <span className="truncate text-control font-semibold text-ink">{app.name}</span>
        <span className="text-detail text-ink-3">
          {app.state === "on"
            ? "On"
            : app.state === "review"
              ? "Connected · waiting for you to turn it on"
              : app.state === "lapsed"
                ? "Its sign-in stopped working"
                : "Not connected yet"}
        </span>
      </div>
      <span className="ml-auto" />
      {app.state === "connecting" || app.state === "lapsed" ? (
        <Button size="compact" variant="raised" onClick={() => connect(app.id)}>
          {app.state === "lapsed" ? "Reconnect" : "Connect"}
        </Button>
      ) : (
        <Button size="compact" variant="raised" onClick={review}>
          {app.state === "review" ? "Review" : "Change"}
        </Button>
      )}
      <Button size="compact" variant="quiet" onClick={() => remove.mutate(app.id)}>
        Remove
      </Button>
    </div>
  );
}
