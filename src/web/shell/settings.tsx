import {
  AudioLines,
  Building2,
  CircleUserRound,
  Check,
  Copy,
  Download,
  Image,
  Laptop,
  LayoutGrid,
  Play,
  Plus,
  Rabbit,
  Smile,
  SunMoon,
  Turtle,
  Users,
  type LucideIcon,
} from "lucide-react";
import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  api,
  type AppEntry,
  type Business,
  type Device,
  type Employee,
  type Look,
  type SettableLook,
  type StartingRole,
} from "../app/api.ts";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { DriveConnection } from "../pages/drive.tsx";
import { useTheme, type Theme } from "../app/theme.ts";
import {
  availableVoices,
  loadVoiceSettings,
  saveVoiceSettings,
  speak,
  type VoiceSettings,
} from "../app/voice.ts";
import { DevysButton } from "../design/buttons.tsx";
import { Field, fieldClass, Switch } from "../design/fields.tsx";
import {
  Face,
  faceFor,
  palettes,
  PersonPortrait,
  shapes,
  tileGradients,
  tintFor,
  tints,
} from "../design/face.tsx";
import { BusinessPortrait, EmployeePortrait } from "../design/portrait.tsx";
import { SegmentedTabs } from "../design/tabs.tsx";
import { Spinner } from "../design/spinner.tsx";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

type Section = "account" | "apps" | "team" | "businesses" | "devices" | "voice" | "appearance";
const sections: { value: Section; title: string; icon: LucideIcon }[] = [
  { value: "account", title: "Account", icon: CircleUserRound },
  { value: "apps", title: "Apps", icon: LayoutGrid },
  { value: "team", title: "Team", icon: Users },
  { value: "businesses", title: "Businesses", icon: Building2 },
  { value: "devices", title: "Devices", icon: Laptop },
  { value: "voice", title: "Voice", icon: AudioLines },
  { value: "appearance", title: "Appearance", icon: SunMoon },
];

/** Settings, as the native Settings window: a section bar over one 640×480 pane. */
export function Settings() {
  const { settingsOpen, settingsSection, actions } = useWorkspace();
  const [section, setSection] = useState<Section>("account");
  useEffect(() => {
    if (settingsOpen) setSection((settingsSection as Section | undefined) ?? "account");
  }, [settingsOpen, settingsSection]);
  return (
    <Dialog open={settingsOpen} onOpenChange={(open) => actions.setSettingsOpen(open)}>
      <DialogContent className="w-[640px] max-w-[calc(100%-2rem)] gap-0 overflow-hidden rounded-card! bg-sheet p-0 shadow-raised sm:max-w-[640px]">
        <DialogTitle className="sr-only">Settings</DialogTitle>
        <div className="flex justify-center gap-1 overflow-x-auto border-b border-hairline pt-3 pr-12 pb-2 pl-4">
          {sections.map((s) => (
            <button
              key={s.value}
              type="button"
              aria-pressed={section === s.value}
              onClick={() => setSection(s.value)}
              className={cn(
                "flex w-[72px] shrink-0 flex-col items-center gap-1 rounded-control py-1.5 text-caption transition-colors",
                section === s.value ? "bg-track text-ink" : "text-ink-2 hover:text-ink",
              )}
            >
              <s.icon className="size-5" strokeWidth={1.7} />
              {s.title}
            </button>
          ))}
        </div>
        <div className="h-[480px] max-h-[70dvh] overflow-y-auto">
          {section === "account" ? (
            <AccountPane />
          ) : section === "apps" ? (
            <AppsPane />
          ) : section === "team" ? (
            <TeamPane />
          ) : section === "businesses" ? (
            <BusinessesPane />
          ) : section === "devices" ? (
            <DevicesPane />
          ) : section === "voice" ? (
            <VoicePane />
          ) : (
            <AppearancePane />
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** Choose a photo from disk; the browser downscales it before upload. */
function PhotoChooser({ title, choose }: { title: string; choose: (file: File) => void }) {
  const input = useRef<HTMLInputElement>(null);
  return (
    <>
      <DevysButton compact onClick={() => input.current?.click()}>
        <Image /> {title}
      </DevysButton>
      <input
        ref={input}
        type="file"
        accept="image/*"
        hidden
        aria-label={title}
        onChange={(event) => {
          const file = event.target.files?.[0];
          if (file) choose(file);
          event.target.value = "";
        }}
      />
    </>
  );
}

function AccountPane() {
  const { person, ownerPhoto, actions } = useWorkspace();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const run = (work: Promise<unknown>) => {
    setBusy(true);
    setError(undefined);
    void work
      .catch(() => setError("That photo couldn't be used. Try a JPEG or PNG."))
      .finally(() => setBusy(false));
  };
  return (
    <div className="flex h-full flex-col gap-6 p-6">
      <div className="flex items-center gap-4">
        <span className="relative">
          <PersonPortrait
            name={person?.display_name ?? ""}
            size={72}
            {...(ownerPhoto ? { photo: ownerPhoto } : {})}
          />
          {busy && (
            <span className="absolute inset-0 grid place-items-center">
              <Spinner />
            </span>
          )}
        </span>
        <div className="flex flex-col gap-2">
          <span className="text-title font-semibold text-ink">{person?.display_name ?? "You"}</span>
          <div className="flex gap-2">
            <PhotoChooser
              title={ownerPhoto ? "Change photo" : "Add photo"}
              choose={(file) => run(actions.uploadOwnerPhoto(file))}
            />
            {ownerPhoto && (
              <DevysButton kind="quiet" compact onClick={() => run(actions.removeOwnerPhoto())}>
                Remove
              </DevysButton>
            )}
          </div>
        </div>
      </div>
      {error && <p className="text-detail text-red">{error}</p>}
      <span className="mt-auto" />
      <DevysButton className="self-start text-red" onClick={() => void actions.signOut()}>
        Sign out of this device
      </DevysButton>
    </div>
  );
}

function ListRow({
  selected,
  onClick,
  children,
}: {
  selected: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-2.5 rounded-[9px] px-2 py-1.5 text-left text-control text-ink",
        selected && "bg-sheet-tint",
      )}
    >
      {children}
    </button>
  );
}

/** The skills an app ships, by name: what employees can load from it. */
function AppSkills({ app }: { app: AppEntry }) {
  return app.skills.length ? (
    <span className="text-caption text-ink-3">
      Skills: {app.skills.map((skill) => skill.name).join(", ")}
    </span>
  ) : null;
}

/**
 * The app directory for the current business: Devys apps to install, pin to the sidebar or
 * remove, those coming later, the system apps every business has, and the accounts apps use.
 */
function AppsPane() {
  const { apps, businessId, actions } = useWorkspace();
  const list = valueOf(apps) ?? [];
  const available = list.filter((app) => app.kind === "business" && app.status === "available");
  const coming = list.filter((app) => app.status === "coming");
  const system = list.filter((app) => app.kind === "system");
  return (
    <div className="flex flex-col gap-5 p-5">
      <div className="flex flex-col gap-1">
        <span className="text-label font-medium text-ink-3">Devys apps</span>
        {available.map((app) => (
          <div key={app.id} className="flex items-center gap-3 py-1.5">
            <div className="flex min-w-0 flex-col">
              <span className="text-control font-semibold text-ink">{app.name}</span>
              <span className="text-detail text-ink-2">{app.summary}</span>
              <AppSkills app={app} />
            </div>
            <span className="ml-auto" />
            {app.installed && (
              <Switch checked={app.pinned} onChange={(on) => void actions.pinApp(app.id, on)}>
                <span className="text-caption text-ink-3">Sidebar</span>
              </Switch>
            )}
            <DevysButton
              compact
              kind={app.installed ? "quiet" : "raised"}
              onClick={() => void actions.installApp(app.id, !app.installed)}
            >
              {app.installed ? "Remove" : "Install"}
            </DevysButton>
          </div>
        ))}
      </div>
      <div className="flex flex-col gap-1">
        <span className="text-label font-medium text-ink-3">Built in</span>
        {system.map((app) => (
          <div key={app.id} className="flex flex-col py-1">
            <span className="text-control text-ink">{app.name}</span>
            <span className="text-detail text-ink-3">{app.summary}</span>
            <AppSkills app={app} />
          </div>
        ))}
      </div>
      {coming.length > 0 && (
        <div className="flex flex-col gap-1">
          <span className="text-label font-medium text-ink-3">Coming</span>
          {coming.map((app) => (
            <div key={app.id} className="flex flex-col py-1 opacity-70">
              <span className="text-control text-ink">{app.name}</span>
              <span className="text-detail text-ink-3">{app.summary}</span>
            </div>
          ))}
        </div>
      )}
      <div className="flex flex-col gap-2">
        <span className="text-label font-medium text-ink-3">Connections</span>
        {businessId && <DriveConnection businessId={businessId} />}
      </div>
    </div>
  );
}

/** Every business's team, each employee's look editable; looks are saved on the server. */
function TeamPane() {
  const { businesses, businessId, employees, actions } = useWorkspace();
  const [teams, setTeams] = useState<Record<string, Employee[]>>({});
  const [selected, setSelected] = useState<string>();
  useEffect(() => {
    void Promise.all(
      businesses.map(
        async (b) =>
          [b.id, b.id === businessId ? employees : (await api.business(b.id)).employees] as const,
      ),
    ).then((entries) => setTeams(Object.fromEntries(entries)));
  }, [businesses, businessId, employees]);
  const all = Object.values(teams).flat();
  const employee = all.find((e) => e.id === selected) ?? all[0];
  const save = async (target: Employee, look: SettableLook) => {
    if (target.business_id === businessId) actions.setEmployeeLook(target.id, look);
    else await api.setEmployeeLook(target.business_id, target.id, look);
    setTeams((current) => ({
      ...current,
      [target.business_id]: (current[target.business_id] ?? []).map((e) =>
        e.id === target.id ? { ...e, look } : e,
      ),
    }));
  };
  return (
    <div className="flex gap-6 p-4 max-sm:flex-col">
      <div className="flex w-[200px] shrink-0 flex-col gap-0.5">
        {businesses.map((b) => (
          <div key={b.id} className="flex flex-col gap-0.5">
            <span className="px-2 pt-2.5 text-label font-medium text-ink-3">{b.name}</span>
            {(teams[b.id] ?? []).map((e) => (
              <ListRow
                key={e.id}
                selected={e.id === employee?.id}
                onClick={() => setSelected(e.id)}
              >
                <EmployeePortrait employee={e} size={24} />
                <span className="truncate">{e.name}</span>
              </ListRow>
            ))}
          </div>
        ))}
      </div>
      {employee ? (
        <LookEditor
          key={employee.id}
          title={employee.name}
          current={employee.look}
          kind={{ kind: "employee", fallback: faceFor(employee.id) }}
          preview={<EmployeePortrait employee={employee} size={84} label={employee.name} />}
          set={(look) => void save(employee, look)}
          photo={(file) =>
            void actions
              .uploadLookPhoto({ businessId: employee.business_id, employeeId: employee.id }, file)
              .then(async () => {
                const fresh = (await api.business(employee.business_id)).employees;
                setTeams((current) => ({ ...current, [employee.business_id]: fresh }));
              })
          }
        />
      ) : (
        <Spinner />
      )}
    </div>
  );
}

const startingRoles: { value: StartingRole; title: string; summary: string }[] = [
  { value: "engineering", title: "Engineering", summary: "Builds, fixes and ships software" },
  { value: "growth", title: "Growth", summary: "Research, positioning and outreach" },
  {
    value: "business-operations",
    title: "Business Operations",
    summary: "Records, documents, suppliers and admin",
  },
];

/** Every business you belong to: its name, brief and look, and a way to start another. */
function BusinessesPane() {
  const { businesses } = useWorkspace();
  const [selected, setSelected] = useState<string>();
  const [creating, setCreating] = useState(false);
  const business = businesses.find((b) => b.id === selected) ?? businesses[0];
  return (
    <div className="flex gap-6 p-4 max-sm:flex-col">
      <div className="flex w-[200px] shrink-0 flex-col gap-0.5">
        {businesses.map((b) => (
          <ListRow
            key={b.id}
            selected={!creating && b.id === business?.id}
            onClick={() => {
              setCreating(false);
              setSelected(b.id);
            }}
          >
            <BusinessPortrait business={b} size={24} />
            <span className="truncate">{b.name}</span>
          </ListRow>
        ))}
        <ListRow selected={creating} onClick={() => setCreating(true)}>
          <Plus className="size-4 w-6 text-ink-2" />
          <span>New business</span>
        </ListRow>
      </div>
      {creating || !business ? (
        <NewBusiness created={() => setCreating(false)} />
      ) : (
        <BusinessDetails key={business.id} business={business} />
      )}
    </div>
  );
}

/** A business starts with a Head of Operations and, if you like, a starting team. */
function NewBusiness({ created }: { created: () => void }) {
  const { actions } = useWorkspace();
  const [name, setName] = useState("");
  const [brief, setBrief] = useState("");
  const [team, setTeam] = useState<StartingRole[]>(startingRoles.map((r) => r.value));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  return (
    <form
      aria-label="New business"
      className="flex min-w-0 flex-1 flex-col gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        if (!name.trim()) return;
        setBusy(true);
        setError(undefined);
        void actions
          .createBusiness({ name, brief, team })
          .then(created)
          .catch(() => setError("The business couldn't be created. Try again."))
          .finally(() => setBusy(false));
      }}
    >
      <span className="text-heading font-semibold text-ink">New business</span>
      <Field label="Name">
        <input
          className={fieldClass}
          value={name}
          maxLength={80}
          placeholder="What it's called"
          onChange={(event) => setName(event.target.value)}
        />
      </Field>
      <Field label="Brief" hint="What it does, its goals and constraints. Every employee reads it.">
        <textarea
          className={cn(fieldClass, "min-h-24 resize-y leading-[1.4]")}
          value={brief}
          maxLength={4000}
          onChange={(event) => setBrief(event.target.value)}
        />
      </Field>
      <div className="flex flex-col gap-2.5">
        <span className="text-label font-medium text-ink-3">Starting team</span>
        <span className="text-detail text-ink-2">A Head of Operations always, and:</span>
        {startingRoles.map((role) => (
          <Switch
            key={role.value}
            checked={team.includes(role.value)}
            onChange={(on) =>
              setTeam((current) =>
                on
                  ? startingRoles
                      .map((r) => r.value)
                      .filter((v) => v === role.value || current.includes(v))
                  : current.filter((v) => v !== role.value),
              )
            }
          >
            <span className="flex flex-col">
              <span>{role.title}</span>
              <span className="text-detail text-ink-3">{role.summary}</span>
            </span>
          </Switch>
        ))}
      </div>
      {error && (
        <p role="alert" className="text-detail text-red">
          {error}
        </p>
      )}
      <DevysButton
        kind="aurora"
        type="submit"
        disabled={busy || !name.trim()}
        className="self-start"
      >
        {busy ? "Creating…" : "Create business"}
      </DevysButton>
    </form>
  );
}

/** Rename a business, rewrite its brief, and change its look. */
function BusinessDetails({ business }: { business: Business }) {
  const { actions } = useWorkspace();
  const [name, setName] = useState(business.name);
  const [brief, setBrief] = useState(business.brief ?? "");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string>();
  const changed = name.trim() !== business.name || brief.trim() !== (business.brief ?? "").trim();
  return (
    <div className="flex min-w-0 flex-1 flex-col gap-6">
      <form
        aria-label="Business details"
        className="flex flex-col gap-4"
        onSubmit={(event) => {
          event.preventDefault();
          if (!name.trim()) return;
          setSaving(true);
          setError(undefined);
          void actions
            .updateBusiness(business.id, { name: name.trim(), brief: brief.trim() })
            .then(() => setSaved(true))
            .catch(() => setError("Those changes couldn't be saved."))
            .finally(() => setSaving(false));
        }}
      >
        <Field label="Name">
          <input
            className={fieldClass}
            value={name}
            maxLength={80}
            onChange={(event) => {
              setName(event.target.value);
              setSaved(false);
            }}
          />
        </Field>
        <Field
          label="Brief"
          hint="What it does, its goals and constraints. Every employee reads it."
        >
          <textarea
            className={cn(fieldClass, "min-h-28 resize-y leading-[1.4]")}
            value={brief}
            maxLength={4000}
            onChange={(event) => {
              setBrief(event.target.value);
              setSaved(false);
            }}
          />
        </Field>
        {error && (
          <p role="alert" className="text-detail text-red">
            {error}
          </p>
        )}
        <div className="flex items-center gap-2">
          <DevysButton type="submit" disabled={saving || !changed || !name.trim()}>
            {saving ? "Saving…" : "Save"}
          </DevysButton>
          {saved && !changed && (
            <span className="flex items-center gap-1 text-detail text-green">
              <Check className="size-3.5" /> Saved
            </span>
          )}
        </div>
      </form>
      <LookEditor
        title={business.name}
        current={business.look}
        kind={{ kind: "business", tint: tintFor(business.id) }}
        preview={<BusinessPortrait business={business} size={84} />}
        set={(look) => void actions.setBusinessLook(business.id, look)}
        photo={(file) => void actions.uploadLookPhoto({ businessId: business.id }, file)}
      />
      <div className="flex flex-col items-start gap-1.5">
        <span className="text-label font-medium text-ink-3">Your data</span>
        <a
          href={api.exportUrl(business.id)}
          download
          className="inline-flex items-center gap-1.5 rounded-full bg-sheet px-3.5 py-2 text-control font-medium text-ink shadow-resting transition duration-150 hover:-translate-y-px [&_svg]:size-[14px]"
        >
          <Download /> Export business data
        </a>
        <span className="text-detail text-ink-3">
          {business.name}'s conversations, memory and file index as one file. Credentials are left
          out, and saved files download separately.
        </span>
      </div>
    </div>
  );
}

const added = (iso: string) =>
  new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
const countdown = (ms: number) => {
  const seconds = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
};

/** Copies text and says so briefly. */
function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <DevysButton
      compact
      aria-label={label}
      onClick={() =>
        void navigator.clipboard
          .writeText(text)
          .then(() => {
            setCopied(true);
            setTimeout(() => setCopied(false), 1500);
          })
          .catch(() => undefined)
      }
    >
      {copied ? <Check /> : <Copy />} {copied ? "Copied" : "Copy"}
    </DevysButton>
  );
}

/**
 * Signed-in devices, and a single-use code that signs an iPhone or iPad in as you. The
 * link opens the app with this server; the code works for ten minutes.
 */
function DevicesPane() {
  const [list, setList] = useState<Device[]>();
  const [failed, setFailed] = useState(false);
  const [code, setCode] = useState<{ code: string; expiresAt: string }>();
  const [issuing, setIssuing] = useState(false);
  const [now, setNow] = useState(Date.now());
  const load = () =>
    api
      .devices()
      .then((result) => {
        setList(result.devices);
        setFailed(false);
      })
      .catch(() => setFailed(true));
  useEffect(() => {
    void load();
  }, []);
  // While a code is showing, count down and watch for the new device to appear.
  useEffect(() => {
    if (!code) return;
    const tick = setInterval(() => setNow(Date.now()), 1000);
    const poll = setInterval(() => void load(), 5000);
    return () => {
      clearInterval(tick);
      clearInterval(poll);
    };
  }, [code]);
  const issue = () => {
    setIssuing(true);
    void api
      .issueDeviceCode()
      .then((issued) => {
        setCode(issued);
        setNow(Date.now());
      })
      .catch(() => setFailed(true))
      .finally(() => setIssuing(false));
  };
  const remaining = code ? Date.parse(code.expiresAt) - now : 0;
  const link = code
    ? `devys://enroll?server=${encodeURIComponent(location.origin)}&code=${code.code}`
    : "";
  return (
    <div className="flex flex-col gap-6 p-6">
      <div className="flex flex-col gap-3">
        <div className="flex items-center">
          <span className="text-heading font-semibold text-ink">Add a device</span>
          <span className="ml-auto" />
          <DevysButton compact onClick={issue} disabled={issuing}>
            <Plus /> {code ? "New code" : "Add a device"}
          </DevysButton>
        </div>
        {code ? (
          <div
            className="flex flex-col gap-3 rounded-card bg-sheet-tint p-4"
            aria-label="Device code"
          >
            {remaining > 0 ? (
              <>
                <p className="text-body text-ink-2">
                  On your iPhone or iPad, open this link, or paste the code into Devys. It works
                  once.
                </p>
                <div className="flex flex-col gap-1.5">
                  <span className="text-label font-medium text-ink-3">Link</span>
                  <div className="flex items-center gap-2">
                    <code
                      className="min-w-0 flex-1 truncate rounded-control bg-well px-2.5 py-[7px] font-mono text-[12px] text-ink select-all"
                      data-testid="device-link"
                    >
                      {link}
                    </code>
                    <CopyButton text={link} label="Copy link" />
                  </div>
                </div>
                <div className="flex flex-col gap-1.5">
                  <span className="text-label font-medium text-ink-3">Code</span>
                  <div className="flex items-center gap-2">
                    <code
                      className="min-w-0 flex-1 rounded-control bg-well px-2.5 py-[7px] font-mono text-[12px] break-all text-ink select-all"
                      data-testid="device-code"
                    >
                      {code.code}
                    </code>
                    <CopyButton text={code.code} label="Copy code" />
                  </div>
                </div>
                <span className="text-detail tabular-nums text-ink-3" role="timer">
                  Expires in {countdown(remaining)}
                </span>
              </>
            ) : (
              <p className="text-body text-ink-3">That code expired. Make a new one.</p>
            )}
          </div>
        ) : (
          <p className="text-detail text-ink-3">
            Sign in an iPhone or iPad as you with a single-use code.
          </p>
        )}
      </div>
      <div className="flex flex-col gap-2">
        <span className="text-heading font-semibold text-ink">Signed in</span>
        {failed && <p className="text-detail text-red">Devices couldn't be loaded.</p>}
        {!list && !failed && <Spinner />}
        <ul aria-label="Devices" className="flex flex-col">
          {list?.map((device) => {
            const name = device.label ?? "Web browser";
            return (
              <li key={device.id} className="flex items-center gap-3 py-2">
                <Laptop className="size-4 shrink-0 text-ink-3" aria-hidden />
                <div className="flex min-w-0 flex-col gap-px">
                  <span className="truncate text-body font-semibold text-ink">{name}</span>
                  <span className="text-detail text-ink-3">
                    {device.current ? "This device · " : ""}Added {added(device.created_at)}
                  </span>
                </div>
                <span className="ml-auto" />
                {!device.current && (
                  <DevysButton
                    kind="quiet"
                    compact
                    aria-label={`Revoke ${name}`}
                    onClick={() =>
                      void api
                        .revokeDevice(device.id)
                        .then(load)
                        .catch(() => setFailed(true))
                    }
                  >
                    Revoke
                  </DevysButton>
                )}
              </li>
            );
          })}
        </ul>
      </div>
    </div>
  );
}

/** Native palette dot colors (`AvatarPalette.eyeInk`). */
const paletteInk: Record<string, string> = {
  brown: "rgb(138 102 69)",
  red: "rgb(217 79 87)",
  orange: "rgb(224 107 46)",
  amber: "rgb(217 153 38)",
  green: "rgb(64 153 79)",
  teal: "rgb(46 158 140)",
  blue: "rgb(54 120 217)",
  purple: "rgb(122 99 217)",
  pink: "rgb(217 74 138)",
  gray: "rgb(110 115 125)",
};
const emojiGroups: { title: string; emoji: string[] }[] = [
  {
    title: "Work",
    emoji: [
      "🧭",
      "🛠️",
      "📈",
      "📊",
      "💼",
      "🤝",
      "🧠",
      "📣",
      "🗂️",
      "💡",
      "🧾",
      "🎯",
      "📬",
      "🔍",
      "🗓️",
      "🚀",
      "🧮",
      "📝",
      "📦",
      "🏗️",
      "⚙️",
      "🔧",
      "💬",
      "📞",
    ],
  },
  {
    title: "People",
    emoji: [
      "🙂",
      "😎",
      "🤓",
      "🧐",
      "🤖",
      "👩‍💼",
      "👨‍💼",
      "🧑‍💻",
      "👩‍🔬",
      "🧑‍🎨",
      "🧑‍🏫",
      "🧑‍🔧",
      "🕵️",
      "🦸",
      "🧙",
      "👋",
      "👍",
      "🙌",
      "💪",
      "🫶",
    ],
  },
  {
    title: "Animals",
    emoji: [
      "🦉",
      "🐝",
      "🦊",
      "🐙",
      "🐢",
      "🦁",
      "🐼",
      "🐧",
      "🦄",
      "🐬",
      "🦅",
      "🐺",
      "🐨",
      "🐸",
      "🦋",
      "🐳",
      "🐯",
      "🦒",
      "🐘",
      "🦔",
    ],
  },
  {
    title: "Nature",
    emoji: [
      "🌱",
      "🌿",
      "🍀",
      "🌻",
      "🌲",
      "🌊",
      "⛰️",
      "🌙",
      "☀️",
      "⭐️",
      "🔥",
      "⚡️",
      "❄️",
      "🌈",
      "🍎",
      "🍋",
      "🌵",
      "🍄",
      "🪴",
      "🌸",
    ],
  },
  {
    title: "Objects",
    emoji: [
      "🎨",
      "📚",
      "✏️",
      "🖋️",
      "📐",
      "🔬",
      "🔭",
      "💎",
      "🧲",
      "🎧",
      "📷",
      "🎬",
      "🎵",
      "🏆",
      "🎁",
      "🔑",
      "🧩",
      "♟️",
      "🪁",
      "🛰️",
    ],
  },
  {
    title: "Symbols",
    emoji: [
      "❤️",
      "🧡",
      "💛",
      "💚",
      "💙",
      "💜",
      "🖤",
      "✨",
      "💫",
      "✅",
      "➕",
      "♾️",
      "🔷",
      "🔶",
      "🟣",
      "🟢",
      "🔴",
      "⚪️",
      "🔺",
      "🔵",
    ],
  },
];
type Mode = "face" | "initials" | "emoji" | "photo";
type EditorKind =
  | { kind: "employee"; fallback: ReturnType<typeof faceFor> }
  | { kind: "business"; tint: string };
const modeTitles: Record<Mode, string> = {
  face: "Face",
  initials: "Initials",
  emoji: "Emoji",
  photo: "Photo",
};

/** Edits one look: a Face (shape and color), an emoji on a tile, or a photo, as native `LookEditor`. */
function LookEditor({
  title,
  current,
  kind,
  preview,
  set,
  photo,
}: {
  title: string;
  current: Look | null;
  kind: EditorKind;
  preview: ReactNode;
  set: (look: SettableLook) => void;
  photo: (file: File) => void;
}) {
  const [chosen, setChosen] = useState<Mode>();
  const [custom, setCustom] = useState("");
  const modes: Mode[] =
    kind.kind === "employee" ? ["face", "emoji", "photo"] : ["initials", "emoji", "photo"];
  const mode: Mode =
    chosen ??
    (current?.kind === "emoji"
      ? "emoji"
      : current?.kind === "photo"
        ? "photo"
        : kind.kind === "business"
          ? "initials"
          : "face");
  const spec =
    current?.kind === "face"
      ? current
      : kind.kind === "employee"
        ? kind.fallback
        : { palette: "blue", shape: "roundedSquare", seed: 1 };
  const tint =
    current?.kind === "emoji" ? current.tint : kind.kind === "business" ? kind.tint : "blue";
  const emoji = current?.kind === "emoji" ? current.emoji : "🙂";
  const face = (palette: string, shape: string) =>
    set({ kind: "face", palette, shape, seed: spec.seed });
  // Choosing a mode applies it at once; a photo waits until one is chosen.
  const choose = (next: Mode) => {
    setChosen(next);
    if (next === "face") face(spec.palette, spec.shape);
    if (next === "initials") set(null);
    if (next === "emoji") set({ kind: "emoji", emoji, tint });
  };
  return (
    <div className="flex min-w-0 flex-1 flex-col gap-4">
      <div
        className="flex items-center gap-4"
        title="Drop an image to use it"
        onDragOver={(event) => event.preventDefault()}
        onDrop={(event) => {
          event.preventDefault();
          const file = event.dataTransfer.files[0];
          if (file?.type.startsWith("image/")) photo(file);
        }}
      >
        {preview}
        <div className="flex flex-col items-start gap-1.5">
          <span className="text-heading font-semibold text-ink">{title}</span>
          {current && (
            <DevysButton
              kind="quiet"
              compact
              onClick={() => {
                setChosen(undefined);
                set(null);
              }}
            >
              Reset
            </DevysButton>
          )}
        </div>
      </div>
      <SegmentedTabs
        label="Look"
        value={mode}
        options={modes.map((m) => ({ value: m, title: modeTitles[m] }))}
        onChange={choose}
      />
      {mode === "face" && (
        <div className="flex flex-col gap-3">
          <div className="grid w-fit grid-cols-8 gap-2.5 max-sm:grid-cols-4">
            {shapes.map((shape) => (
              <Option
                key={shape}
                label={shape}
                selected={spec.shape === shape}
                onClick={() => face(spec.palette, shape)}
              >
                <Face spec={{ palette: spec.palette, shape, seed: spec.seed }} size={38} />
              </Option>
            ))}
          </div>
          <div className="flex flex-wrap gap-2">
            {palettes.map((palette) => (
              <Dot
                key={palette}
                label={palette}
                color={paletteInk[palette]!}
                selected={spec.palette === palette}
                onClick={() => face(palette, spec.shape)}
              />
            ))}
          </div>
        </div>
      )}
      {mode === "emoji" && (
        <div className="flex flex-col gap-3">
          {/* Color applies at once: it recolors the current emoji, or starts with 🙂. */}
          <div className="flex items-center gap-2">
            {tints.map((t) => (
              <Dot
                key={t}
                label={t}
                color={tileGradients[t]![0]}
                selected={current?.kind === "emoji" && current.tint === t}
                onClick={() => set({ kind: "emoji", emoji, tint: t })}
              />
            ))}
            <span className="ml-auto" />
            <input
              aria-label="Any emoji"
              title="Type or paste any emoji"
              placeholder="Any emoji"
              value={custom}
              onChange={(event) => {
                const graphemes = [...new Intl.Segmenter().segment(event.target.value)].map(
                  (g) => g.segment,
                );
                const found = graphemes.reverse().find((g) => /\p{Extended_Pictographic}/u.test(g));
                if (!found) return setCustom(event.target.value);
                set({ kind: "emoji", emoji: found, tint });
                setCustom("");
              }}
              className="w-24 rounded-control bg-well py-[5px] text-center text-[15px] text-ink outline-none placeholder:text-detail placeholder:text-ink-3 focus-visible:ring-2 focus-visible:ring-indigo/40"
            />
            <Smile className="size-4 text-ink-2" aria-hidden />
          </div>
          <div className="flex max-h-[260px] flex-col gap-3 overflow-y-auto">
            {emojiGroups.map((group) => (
              <div key={group.title} className="flex flex-col gap-1.5">
                <span className="text-label font-medium text-ink-3">{group.title}</span>
                <div className="flex flex-wrap gap-1.5">
                  {group.emoji.map((e) => (
                    <Option
                      key={e}
                      label={e}
                      selected={
                        current?.kind === "emoji" && current.emoji === e && current.tint === tint
                      }
                      onClick={() => set({ kind: "emoji", emoji: e, tint })}
                    >
                      <span className="text-[22px] leading-none">{e}</span>
                    </Option>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
      {mode === "photo" && (
        <div className="flex gap-2">
          <PhotoChooser title="Choose photo" choose={photo} />
        </div>
      )}
    </div>
  );
}

function Option({
  label,
  selected,
  onClick,
  children,
}: {
  label: string;
  selected: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      aria-pressed={selected}
      onClick={onClick}
      className={cn(
        "grid size-10 place-items-center rounded-control border-[1.5px]",
        selected ? "border-indigo bg-well" : "border-transparent",
      )}
    >
      {children}
    </button>
  );
}

function Dot({
  label,
  color,
  selected,
  onClick,
}: {
  label: string;
  color: string;
  selected: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={label.charAt(0).toUpperCase() + label.slice(1)}
      aria-pressed={selected}
      onClick={onClick}
      className={cn(
        "size-5 rounded-full",
        selected &&
          "outline outline-1 outline-offset-2 outline-ink ring-[2.5px] ring-sheet ring-inset",
      )}
      style={{ background: color }}
    />
  );
}

function VoicePane() {
  const [settings, setSettings] = useState<VoiceSettings>(loadVoiceSettings);
  const [voices, setVoices] = useState<SpeechSynthesisVoice[]>([]);
  useEffect(() => {
    if (typeof speechSynthesis === "undefined") return;
    const update = () => setVoices(availableVoices());
    update();
    speechSynthesis.addEventListener("voiceschanged", update);
    return () => speechSynthesis.removeEventListener("voiceschanged", update);
  }, []);
  const change = (next: Partial<VoiceSettings>) => {
    const merged = { ...settings, ...next };
    setSettings(merged);
    saveVoiceSettings(merged);
  };
  return (
    <div className="flex flex-col gap-6 p-6">
      <div className="flex flex-col gap-2">
        <span className="text-heading font-semibold text-ink">Reply voice</span>
        <div className="flex items-center gap-2">
          <select
            aria-label="Reply voice"
            value={settings.voiceURI ?? ""}
            onChange={(event) => change({ voiceURI: event.target.value || null })}
            className="h-[30px] max-w-[280px] min-w-0 flex-1 rounded-small bg-well px-2 text-control text-ink outline-none focus-visible:ring-2 focus-visible:ring-indigo/40"
          >
            <option value="">Best available</option>
            {voices.map((voice) => (
              <option key={voice.voiceURI} value={voice.voiceURI}>
                {voice.name}
                {voice.localService ? "" : " · Online"}
              </option>
            ))}
          </select>
          <DevysButton
            compact
            onClick={() =>
              void speak("Hi, this is how I'll sound when I read replies aloud.", settings)
            }
          >
            <Play className="fill-current" /> Preview
          </DevysButton>
        </div>
      </div>
      <div className="flex flex-col gap-2">
        <span className="text-heading font-semibold text-ink">Speaking rate</span>
        <div className="flex items-center gap-2.5">
          <Turtle className="size-4 text-ink-3" aria-hidden />
          <input
            type="range"
            aria-label="Speaking rate"
            min={0.5}
            max={1.5}
            step={0.05}
            value={settings.rate}
            onChange={(event) => change({ rate: Number(event.target.value) })}
            className="w-[260px] accent-indigo"
          />
          <Rabbit className="size-4 text-ink-3" aria-hidden />
        </div>
      </div>
      <label className="flex w-fit cursor-pointer items-center gap-2.5 text-control text-ink">
        <input
          type="checkbox"
          role="switch"
          checked={settings.speaksReplies}
          onChange={(event) => change({ speaksReplies: event.target.checked })}
          className="peer sr-only"
        />
        <span className="relative h-[22px] w-[38px] rounded-full bg-track transition-colors peer-checked:bg-green peer-focus-visible:ring-2 peer-focus-visible:ring-indigo after:absolute after:top-0.5 after:left-0.5 after:size-[18px] after:rounded-full after:bg-white after:shadow-resting after:transition-transform peer-checked:after:translate-x-4" />
        Read replies aloud
      </label>
      <p className="text-detail text-ink-3">
        Your browser transcribes and speaks. It keeps speech on this device where it can; some
        browsers use their own speech service.
      </p>
    </div>
  );
}

function AppearancePane() {
  const [theme, setTheme] = useTheme();
  return (
    <div className="flex flex-col gap-4 p-6">
      <span className="text-heading font-semibold text-ink">Appearance</span>
      <SegmentedTabs<Theme>
        label="Appearance"
        value={theme}
        options={[
          { value: "system", title: "System" },
          { value: "light", title: "Light" },
          { value: "dark", title: "Dark" },
        ]}
        onChange={setTheme}
      />
    </div>
  );
}
