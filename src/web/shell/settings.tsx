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
import { api, type StartingRole } from "../app/api.ts";
import type { InstalledApp } from "../../apps/contract.ts";
import type { Business, Device, Employee, Look, SettableLook } from "../../identity/contract.ts";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  useApps,
  useBusinessId,
  useBusinesses,
  useEmployees,
  useOwnerPhoto,
  usePerson,
} from "../app/data.ts";
import {
  useCreateBusiness,
  useInstallApp,
  useOwnerPhotoChange,
  usePinApp,
  useRename,
  useSetBusinessLook,
  useSetEmployeeLook,
  useSignOut,
  useUpdateBusiness,
  useUploadLookPhoto,
} from "../app/mutations.ts";
import { useNav, useSettingsSection } from "../app/navigation.ts";
import { keys } from "../app/query.ts";
import { DriveConnection } from "./drive-settings.tsx";
import { useTheme, type Theme } from "../app/theme.ts";
import {
  availableVoices,
  loadVoiceSettings,
  saveVoiceSettings,
  speak,
  type VoiceSettings,
} from "../app/voice.ts";
import { Face, faceFor, PersonPortrait, tileGradients, tintFor } from "../design/face.tsx";
import { palettes, shapes, tints } from "../../identity/contract.ts";
import { BusinessPortrait, EmployeePortrait } from "../design/portrait.tsx";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Switch } from "@/components/ui/switch";
import { Spinner } from "../design/spinner.tsx";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { shortDate } from "../lib/format.ts";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { NativeSelect } from "@/components/ui/native-select";
import { Textarea } from "@/components/ui/textarea";

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
  const nav = useNav();
  const open = useSettingsSection();
  // The section is the URL's; while the dialog closes it keeps showing the last one.
  const [shown, setShown] = useState(open);
  if (open && open !== shown) setShown(open);
  const section: Section = sections.some((s) => s.value === shown) ? (shown as Section) : "account";
  const setSection = nav.setSettingsSection;
  return (
    <Dialog open={Boolean(open)} onOpenChange={(next) => !next && nav.closeSettings()}>
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
      <Button size="compact" onClick={() => input.current?.click()}>
        <Image /> {title}
      </Button>
      <Input
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

/** The name the owner goes by, saved with Enter or the Save button. */
function NameField({ current }: { current: string }) {
  const rename = useRename();
  const [name, setName] = useState(current);
  useEffect(() => setName(current), [current]);
  const changed = name.trim() !== current && name.trim().length > 0;
  return (
    <form
      aria-label="Your name"
      className="flex items-center gap-2"
      onSubmit={(event) => {
        event.preventDefault();
        if (changed) rename.mutate(name);
      }}
    >
      <Input
        aria-label="Your name"
        value={name}
        maxLength={80}
        onChange={(event) => setName(event.target.value)}
        className="w-56"
      />
      {changed && (
        <Button size="compact" variant="raised" type="submit" disabled={rename.isPending}>
          Save
        </Button>
      )}
      {rename.isError && <span className="text-detail text-red">That name couldn't be saved.</span>}
    </form>
  );
}

function AccountPane() {
  const person = usePerson();
  const ownerPhoto = useOwnerPhoto();
  const photo = useOwnerPhotoChange();
  const signOut = useSignOut();
  const busy = photo.isPending;
  const error = photo.isError ? "That photo couldn't be used. Try a JPEG or PNG." : undefined;
  const run = (file: Blob | null) => photo.mutate(file);
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
          {person ? (
            <NameField current={person.display_name} />
          ) : (
            <span className="text-title font-semibold text-ink">You</span>
          )}
          <div className="flex gap-2">
            <PhotoChooser
              title={ownerPhoto ? "Change photo" : "Add photo"}
              choose={(file) => run(file)}
            />
            {ownerPhoto && (
              <Button variant="quiet" size="compact" onClick={() => run(null)}>
                Remove
              </Button>
            )}
          </div>
        </div>
      </div>
      {error && <p className="text-detail text-red">{error}</p>}
      <span className="mt-auto" />
      <Button className="self-start text-red" onClick={() => signOut.mutate()}>
        Sign out of this device
      </Button>
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
        "flex w-full items-center gap-2.5 rounded-small px-2 py-1.5 text-left text-control text-ink",
        selected && "bg-sheet-tint",
      )}
    >
      {children}
    </button>
  );
}

/** The skills an app ships, by name: what employees can load from it. */
function AppSkills({ app }: { app: InstalledApp }) {
  return app.skills.length ? (
    <span className="text-caption text-ink-3">
      Skills: {app.skills.map((skill) => skill.name).join(", ")}
    </span>
  ) : null;
}

/**
 * The app directory for the current business: Devys apps to install, pin to the sidebar or
 * remove, the system apps every business has, and the accounts apps use.
 */
function AppsPane() {
  const businessId = useBusinessId();
  const list = useApps().data ?? [];
  const pin = usePinApp();
  const install = useInstallApp();
  const available = list.filter((app) => app.kind === "business");
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
              <Switch
                checked={app.pinned}
                onCheckedChange={(on) => pin.mutate({ app: app.id, pinned: on })}
              >
                <span className="text-caption text-ink-3">Sidebar</span>
              </Switch>
            )}
            <Button
              size="compact"
              variant={app.installed ? "quiet" : "raised"}
              onClick={() => install.mutate({ app: app.id, on: !app.installed })}
            >
              {app.installed ? "Remove" : "Install"}
            </Button>
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
      <div className="flex flex-col gap-2">
        <span className="text-label font-medium text-ink-3">Connections</span>
        {businessId && <DriveConnection businessId={businessId} />}
      </div>
    </div>
  );
}

/** The current business's team, each employee's look editable; looks are saved on the server. */
function TeamPane() {
  const employees = useEmployees();
  const setLook = useSetEmployeeLook();
  const uploadPhoto = useUploadLookPhoto();
  const [selected, setSelected] = useState<string>();
  const employee = employees.find((e) => e.id === selected) ?? employees[0];
  const save = (target: Employee, look: SettableLook) => setLook.mutate({ employee: target, look });
  return (
    <div className="flex gap-6 p-4 max-sm:flex-col">
      <div className="flex w-[200px] shrink-0 flex-col gap-0.5">
        {employees.map((e) => (
          <ListRow key={e.id} selected={e.id === employee?.id} onClick={() => setSelected(e.id)}>
            <EmployeePortrait employee={e} size={24} />
            <span className="truncate">{e.name}</span>
          </ListRow>
        ))}
      </div>
      {employee ? (
        <LookEditor
          key={employee.id}
          title={employee.name}
          current={employee.look}
          kind={{ kind: "employee", fallback: faceFor(employee.id) }}
          preview={<EmployeePortrait employee={employee} size={84} label={employee.name} />}
          set={(look) => save(employee, look)}
          photo={(file) =>
            uploadPhoto.mutate({
              target: { businessId: employee.business_id, employeeId: employee.id },
              file,
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
  const businesses = useBusinesses();
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
export function NewBusiness({ created }: { created: () => void }) {
  const createBusiness = useCreateBusiness();
  const [name, setName] = useState("");
  const [brief, setBrief] = useState("");
  const [team, setTeam] = useState<StartingRole[]>(startingRoles.map((r) => r.value));
  const [error, setError] = useState<string>();
  const busy = createBusiness.isPending;
  return (
    <form
      aria-label="New business"
      className="flex min-w-0 flex-1 flex-col gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        if (!name.trim()) return;
        setError(undefined);
        createBusiness.mutate(
          { name, brief, team },
          {
            onSuccess: created,
            onError: () => setError("The business couldn't be created. Try again."),
          },
        );
      }}
    >
      <span className="text-heading font-semibold text-ink">New business</span>
      <Field label="Name">
        <Input
          value={name}
          maxLength={80}
          placeholder="What it's called"
          onChange={(event) => setName(event.target.value)}
        />
      </Field>
      <Field label="Brief" hint="What it does, its goals and constraints. Every employee reads it.">
        <Textarea
          className="min-h-24 resize-y leading-[1.4]"
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
            onCheckedChange={(on) =>
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
      <Button variant="aurora" type="submit" disabled={busy || !name.trim()} className="self-start">
        {busy ? "Creating…" : "Create business"}
      </Button>
    </form>
  );
}

/** Rename a business, rewrite its brief, and change its look. */
function BusinessDetails({ business }: { business: Business }) {
  const updateBusiness = useUpdateBusiness();
  const setLook = useSetBusinessLook();
  const uploadPhoto = useUploadLookPhoto();
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
          updateBusiness.mutate(
            { id: business.id, change: { name: name.trim(), brief: brief.trim() } },
            {
              onSuccess: () => setSaved(true),
              onError: () => setError("Those changes couldn't be saved."),
              onSettled: () => setSaving(false),
            },
          );
        }}
      >
        <Field label="Name">
          <Input
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
          <Textarea
            className="min-h-28 resize-y leading-[1.4]"
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
          <Button type="submit" disabled={saving || !changed || !name.trim()}>
            {saving ? "Saving…" : "Save"}
          </Button>
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
        set={(look) => setLook.mutate({ id: business.id, look })}
        photo={(file) => uploadPhoto.mutate({ target: { businessId: business.id }, file })}
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

const countdown = (ms: number) => {
  const seconds = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
};

/** Copies text and says so briefly. */
function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <Button
      size="compact"
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
    </Button>
  );
}

/**
 * Signed-in devices, and a single-use code that signs an iPhone or iPad in as you. The
 * link opens the app with this server; the code works for ten minutes.
 */
function DevicesPane() {
  const client = useQueryClient();
  const [code, setCode] = useState<{ code: string; expires_at: string }>();
  const [now, setNow] = useState(Date.now());
  // While a code is showing, watch for the new device to appear.
  const devices = useQuery({
    queryKey: keys.devices,
    queryFn: api.devices,
    select: (result) => result.devices,
    refetchInterval: code ? 5_000 : false,
  });
  const list: readonly Device[] | undefined = devices.data;
  const issuing = useMutation({
    mutationFn: api.issueDeviceCode,
    onSuccess: (issued) => {
      setCode(issued);
      setNow(Date.now());
    },
  });
  const revoke = useMutation({
    mutationFn: (id: string) => api.revokeDevice(id),
    onSettled: () => client.invalidateQueries({ queryKey: keys.devices }),
  });
  const failed = devices.isError || issuing.isError || revoke.isError;
  // While a code is showing, count down.
  useEffect(() => {
    if (!code) return;
    const tick = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(tick);
  }, [code]);
  const issue = () => issuing.mutate();
  const remaining = code ? Date.parse(code.expires_at) - now : 0;
  const link = code
    ? `devys://enroll?server=${encodeURIComponent(location.origin)}&code=${code.code}`
    : "";
  return (
    <div className="flex flex-col gap-6 p-6">
      <div className="flex flex-col gap-3">
        <div className="flex items-center">
          <span className="text-heading font-semibold text-ink">Add a device</span>
          <span className="ml-auto" />
          <Button size="compact" onClick={issue} disabled={issuing.isPending}>
            <Plus /> {code ? "New code" : "Add a device"}
          </Button>
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
                    {device.current ? "This device · " : ""}Added {shortDate(device.created_at)}
                  </span>
                </div>
                <span className="ml-auto" />
                {!device.current && (
                  <Button
                    variant="quiet"
                    size="compact"
                    aria-label={`Revoke ${name}`}
                    onClick={() => revoke.mutate(device.id)}
                  >
                    Revoke
                  </Button>
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
  | { kind: "business"; tint: (typeof tints)[number] };
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
        : ({ palette: "blue", shape: "roundedSquare", seed: 1 } as const);
  const tint =
    current?.kind === "emoji" ? current.tint : kind.kind === "business" ? kind.tint : "blue";
  const emoji = current?.kind === "emoji" ? current.emoji : "🙂";
  const face = (palette: (typeof palettes)[number], shape: (typeof shapes)[number]) =>
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
            <Button
              variant="quiet"
              size="compact"
              onClick={() => {
                setChosen(undefined);
                set(null);
              }}
            >
              Reset
            </Button>
          )}
        </div>
      </div>
      <Tabs value={mode} onValueChange={(next) => choose(next as typeof mode)}>
        <TabsList aria-label="Look">
          {modes.map((m) => (
            <TabsTrigger key={m} value={m}>
              {modeTitles[m]}
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
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
            <Input
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
              className="w-24 py-[5px] text-center text-[15px] placeholder:text-detail"
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
          <NativeSelect
            aria-label="Reply voice"
            value={settings.voiceURI ?? ""}
            onChange={(event) => change({ voiceURI: event.target.value || null })}
            className="h-[30px] max-w-[280px] flex-1 rounded-small px-2 py-0 text-control"
          >
            <option value="">Best available</option>
            {voices.map((voice) => (
              <option key={voice.voiceURI} value={voice.voiceURI}>
                {voice.name}
                {voice.localService ? "" : " · Online"}
              </option>
            ))}
          </NativeSelect>
          <Button
            size="compact"
            onClick={() =>
              void speak("Hi, this is how I'll sound when I read replies aloud.", settings)
            }
          >
            <Play className="fill-current" /> Preview
          </Button>
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
      <Switch
        checked={settings.speaksReplies}
        onCheckedChange={(on) => change({ speaksReplies: on })}
      >
        Read replies aloud
      </Switch>
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
      <Tabs value={theme} onValueChange={(next) => setTheme(next as Theme)}>
        <TabsList aria-label="Appearance">
          <TabsTrigger value="system">System</TabsTrigger>
          <TabsTrigger value="light">Light</TabsTrigger>
          <TabsTrigger value="dark">Dark</TabsTrigger>
        </TabsList>
      </Tabs>
    </div>
  );
}
