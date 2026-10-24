/**
 * The HTTP API's responses, by route: what the web and native clients read. Records are defined
 * once by the component that owns them (in its contract); this module composes them into each
 * route's response. Handlers encode with these schemas (`respond`), the web client decodes with
 * them, and the server's wire test writes golden JSON from them for the native client.
 *
 * Imported by the web client, so it imports only contracts, the shared kernel and Effect.
 */
import { Schema } from "effect";
import { Ref } from "../protocol/ref.ts";
import { FoundApp, InstalledApp, Line, ListedApp } from "../apps/contract.ts";
import { LiveCodingSession } from "../apps/code/contract.ts";
import { Artifact } from "../apps/documents/contract.ts";
import { Decision, DeviceKey, Grant } from "../authority/contract.ts";
import {
  ConversationKey,
  ConversationSummary,
  Message,
  ShownMessage,
} from "../conversations/contract.ts";
import { Business, Employee, Look, Person, RoleTemplate } from "../identity/contract.ts";
import { Timestamp } from "../protocol/time.ts";
import { TerminalSession } from "../terminal/contract.ts";
import { Project, Routine, WorkItem, WorkItemState } from "../work/contract.ts";
import { FileEntry, FileText } from "../workspace/contract.ts";
import { SecretEntry } from "../vault/contract.ts";

// The person and their businesses.

/** `GET /api/me`. */
export const Me = Schema.Struct({ person: Person, businesses: Schema.Array(Business) });
/** `POST /api/businesses`: the business and its Chief of Staff, its only employee to start. */
export const BusinessCreated = Schema.Struct({
  business: Business,
  chief_of_staff: Employee,
});
/** `PUT /api/businesses/:id`. */
export const BusinessUpdated = Schema.Struct({ business: Business });
/** `GET /api/businesses/:id`: the business, its team, its members and its latest artifacts. */
export const BusinessDetail = Schema.Struct({
  business: Business,
  employees: Schema.Array(Employee),
  members: Schema.Array(Person),
  artifacts: Schema.Array(Artifact),
});
/** `GET /api/roles`: the templates a new employee is hired from. */
export const Roles = Schema.Struct({ roles: Schema.Array(RoleTemplate) });
/** `POST …/look` and `PUT …/look/photo`. */
export const LookChanged = Schema.Struct({ look: Schema.NullOr(Look) });

/** A model employees can use, priced in dollars per million tokens. */
const ModelOption = Schema.Struct({
  id: Schema.String,
  label: Schema.String,
  vendor: Schema.String,
  /** The provider's display name. */
  provider: Schema.String,
  summary: Schema.String,
  effort: Schema.Literals(["low", "medium", "high"]),
  price: Schema.Struct({
    input: Schema.Number,
    output: Schema.Number,
    cache_read: Schema.Number,
  }),
  /** A typical employee turn in dollars. */
  typical_turn_usd: Schema.Number,
});
export type ModelOption = typeof ModelOption.Type;
/** `GET /api/models`: the deployment's models and its defaults, without keys. */
export const ModelCatalog = Schema.Struct({
  defaults: Schema.Struct({ employee: Schema.String, background: Schema.String }),
  models: Schema.Array(ModelOption),
});
export type ModelCatalog = typeof ModelCatalog.Type;

// Employees.

/** `PUT …/employees/:id/profile`: the fields that changed. */
export const ProfileChanged = Schema.Struct({
  name: Schema.optionalKey(Schema.String),
  responsibilities: Schema.optionalKey(Schema.String),
});
/** `POST …/employees/:id/retire`. */
export const Retired = Schema.Struct({
  retired: Schema.Literal(true),
  reassigned_to: Schema.String,
});
/** `PUT …/employees/:id/model`. */
export const ModelChanged = Schema.Struct({ model: Schema.String });
/** `POST …/employees/:id/pause` and `…/resume`. */
export const PausedChanged = Schema.Struct({ paused: Schema.Boolean });
/** `POST …/employees/:id/stop`. */
export const Stopped = Schema.Struct({ stopped: Schema.Boolean });
/** `POST …/employees/:id/channels`. */
export const Bound = Schema.Struct({ bound: Schema.Literal(true) });

/** Tokens and dollars spent, as the model library reports them. */
const Usage = Schema.Struct({
  input: Schema.Number,
  output: Schema.Number,
  cache_read: Schema.Number,
  cache_write: Schema.Number,
  cache_write_1h: Schema.optionalKey(Schema.Number),
  reasoning: Schema.optionalKey(Schema.Number),
  total_tokens: Schema.Number,
  cost: Schema.Struct({
    input: Schema.Number,
    output: Schema.Number,
    cache_read: Schema.Number,
    cache_write: Schema.Number,
    total: Schema.Number,
  }),
});
export type Usage = typeof Usage.Type;
/** The employee runtime's state: its run, its latest inputs and replies, checkpoint and spend. */
const RuntimeState = Schema.Struct({
  run: Schema.NullOr(
    Schema.Struct({
      id: Schema.String,
      stopped: Schema.Boolean,
      deadline: Schema.NullOr(Schema.Number),
      /** The conversation the running turn is in (`work:<id>`, `direct:<id>`, `project:<id>`). */
      conversation: Schema.NullOr(Schema.String),
      /** What it is doing now, in the owner's words ("Opening godaddy.com", "Thinking"). */
      doing: Schema.String,
    }),
  ),
  inbox: Schema.Array(
    Schema.Struct({
      id: Schema.String,
      text: Schema.optionalKey(Schema.String),
      /** Milliseconds since the epoch. */
      received_at: Schema.Number,
      status: Schema.Literals(["queued", "running", "done", "failed"]),
    }),
  ),
  outbox: Schema.Array(
    Schema.Struct({
      id: Schema.String,
      chat_id: Schema.String,
      text: Schema.String,
      /** Devys answered for the employee: the turn took too long, failed, or found it paused. */
      notice: Schema.optionalKey(Schema.Literals(["too_long", "failed", "paused", "unreadable"])),
      reply_to: Schema.optionalKey(Schema.String),
      attempts: Schema.Number,
      status: Schema.Literals(["pending", "sent", "uncertain", "cancelled"]),
    }),
  ),
  /** The workspace's last checkpoint, absent until one was tried. */
  checkpoint: Schema.optionalKey(
    Schema.Union([
      Schema.Struct({
        status: Schema.Literal("saved"),
        at: Schema.Number,
        kind: Schema.Literal("snapshot"),
        snapshot_id: Schema.String,
        bytes: Schema.Number,
      }),
      Schema.Struct({
        status: Schema.Literal("saved"),
        at: Schema.Number,
        kind: Schema.Literal("durable"),
      }),
      Schema.Struct({
        status: Schema.Literal("failed"),
        at: Schema.Number,
        message: Schema.String,
      }),
    ]),
  ),
  /** Spend by "provider/modelId" and by tool. */
  usage: Schema.optionalKey(
    Schema.Struct({
      models: Schema.Record(Schema.String, Usage),
      tools: Schema.Record(Schema.String, Usage),
    }),
  ),
});
export type RuntimeState = typeof RuntimeState.Type;
/**
 * `GET …/conversations/:key/messages/:id/steps`: the steps the turn behind an employee's reply
 * took, in the owner's words. Empty once the employee no longer keeps them.
 */
export const Steps = Schema.Struct({ steps: Schema.Array(Schema.String) });

/** `GET …/employees/:id/status`. */
export const RuntimeStatus = Schema.Struct({ state: RuntimeState });

/** What a capability is, as the access list shows it. */
const Described = {
  description: Schema.optionalKey(Schema.String),
  effect: Schema.optionalKey(Schema.Literals(["read", "change", "external"])),
  /** The capability has limits a grant can set. */
  limits: Schema.optionalKey(Schema.Boolean),
};
/** `GET …/employees/:id/access`: its grants, and the capabilities it could be granted. */
export const AccessList = Schema.Struct({
  grants: Schema.Array(Schema.Struct({ ...Grant.fields, ...Described })),
  available: Schema.Array(Schema.Struct({ capability: Schema.String, ...Described })),
});
export type AccessList = typeof AccessList.Type;
/** `POST …/employees/:id/access/:grant/revoke`. */
export const Revoked = Schema.Struct({ revoked: Schema.Literal(true) });

// Conversations.

/** `GET …/conversations`. */
export const Conversations = Schema.Struct({ conversations: Schema.Array(ConversationSummary) });
/** `GET …/conversations/:key`: a page of messages, and who answers the next plain message. */
export const ConversationPage = Schema.Struct({
  messages: Schema.Array(ShownMessage),
  respondent: Schema.NullOr(Schema.String),
});
/** `POST …/conversations/:key/messages` and `POST …/files/comments`: the message and who answers. */
export const Posted = Schema.Struct({ message: Message, to: Schema.Array(Schema.String) });
/** `POST …/files/upload?name=`: the file the owner gave, in the business folder's Uploads. */
export const Uploaded = Schema.Struct({ ref: Ref });
/** `POST …/welcome`: whether the Chief of Staff was asked to greet (once, in an empty chat). */
export const Welcomed = Schema.Struct({ welcomed: Schema.Boolean });
/** `POST …/conversations/:key/read`. */
export const Read = Schema.Struct({ read: Schema.Literal(true) });
/** `POST …/conversations/:key/follow`. */
export const Following = Schema.Struct({ following: Schema.Boolean });
/** `POST …/conversations/:key/sidebar`: any of pinned, hidden, unread. */
export const SidebarMark = Schema.Struct({
  pinned: Schema.optionalKey(Schema.Boolean),
  hidden: Schema.optionalKey(Schema.Boolean),
  unread: Schema.optionalKey(Schema.Boolean),
});

// Work, decisions and projects.

/** `GET …/work`. */
export const WorkItems = Schema.Struct({ work_items: Schema.Array(WorkItem) });
/** `GET …/decisions`. */
export const Decisions = Schema.Struct({ decisions: Schema.Array(Decision) });
/** `POST …/decisions/:id/approve` and `…/reject`. */
export const Answered = Schema.Struct({ status: Decision.fields.status });
/** Base64 of at most `max` characters. */
const Base64 = (max: number) =>
  Schema.String.check(Schema.isPattern(/^[A-Za-z0-9+/]+={0,2}$/), Schema.isMaxLength(max));
/**
 * `POST …/decisions/:id/approve` for a spend approval: the device key's DER signature of the
 * request's canonical payload (src/authority/signing.ts), made on the owner's Mac or iPhone.
 */
export const SpendSignature = Schema.Struct({ key_id: Schema.String, signature: Base64(200) });

// Device signing keys (the owner's Mac and iPhone apps).

/** `GET /api/device-keys`: the person's keys; `current` is this device's. */
export const DeviceKeys = Schema.Struct({
  keys: Schema.Array(Schema.Struct({ ...DeviceKey.fields, current: Schema.Boolean })),
});
/** `POST /api/device-keys`: this device's public key (X9.63, base64), from its Secure Enclave. */
export const KeyEnrollment = Schema.Struct({ public_key: Base64(100) });
/** `POST /api/device-keys/:id/endorse`: an active key's signature letting another device sign. */
export const KeyEndorsement = SpendSignature;
/**
 * `POST /api/joins/:id/allow` (or `deny`): the joined device's key when it sent one, pending
 * until an active key signs it (the allowing app does so at once) unless it is the person's first.
 */
export const JoinAnswered = Schema.Struct({ key: Schema.NullOr(DeviceKey) });
/** `GET …/projects`. */
export const Projects = Schema.Struct({ projects: Schema.Array(Project) });
/** `POST …/projects/:id/items/:item/remove`. */
export const Removed = Schema.Struct({ removed: Schema.Literal(true) });
/**
 * `GET …/routines`, `?employee=` for an employee's desk and `?project=` for a project's overview.
 * `POST …/routines/:id/pause` and `…/resume` answer with the `Routine`.
 */
export const Routines = Schema.Struct({ routines: Schema.Array(Routine) });

// Apps.

/** `GET …/apps`. */
export const Apps = Schema.Struct({ apps: Schema.Array(InstalledApp) });
/** `POST …/apps/:id/install`, `…/uninstall` and `…/pin`. */
export const AppChanged = Schema.Struct({ app: InstalledApp });
/** `GET …/apps/search?q=`: the business's apps and the MCP Registry's that fit. */
/** `GET …/apps/listed`: the Connect apps sheet's list, by category. */
export const AppsListed = Schema.Struct({ apps: Schema.Array(ListedApp) });
export const AppSearch = Schema.Struct({ apps: Schema.Array(FoundApp) });
/** `POST …/apps/add`: an app as `appSearch` found it (id or registry name) or an MCP address. */
export const AddApp = Schema.Struct({
  app: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(2000)),
});
/**
 * `POST …/apps/:id/connect`: the provider's sign-in page to open, or null when the app needed
 * none (it is connected now, waiting for review).
 */
export const Connecting = Schema.Struct({ url: Schema.NullOr(Schema.String), app: InstalledApp });
/**
 * `GET …/apps/:id/review`: the one review card. Each tool's line (suggested from its own hints
 * until the owner accepts; a tool that issues payment credentials is fixed at never) and who
 * uses the app. `POST …/apps/:id/accept` takes `{lines, employees}` (`RemotePolicy`).
 */
export const AppReview = Schema.Struct({
  app: InstalledApp,
  tools: Schema.Array(
    Schema.Struct({
      capability: Schema.String,
      title: Schema.String,
      description: Schema.String,
      line: Line,
      /** Never available, whatever the owner chooses (it hands out payment credentials). */
      fixed: Schema.Boolean,
    }),
  ),
  employees: Schema.Array(
    Schema.Struct({ id: Schema.String, name: Schema.String, uses: Schema.Boolean }),
  ),
});
export type AppReview = typeof AppReview.Type;
/** `GET …/connections/google`: whether Google is set up and connected, and the files picked. */
export const GoogleConnection = Schema.Struct({
  configured: Schema.Boolean,
  connected: Schema.Boolean,
  files: Schema.Array(
    Schema.Struct({ id: Schema.String, name: Schema.String, mime_type: Schema.String }),
  ),
});
/** `POST …/connections/google/picker`: what Google's file picker opens with. */
export const DrivePicker = Schema.Struct({
  /** A short-lived access token for the picker only. */
  token: Schema.String,
  key: Schema.String,
  app_id: Schema.String,
});
/** `POST …/connections/google/select`: how many picked files Devys may now read. */
export const DriveSelected = Schema.Struct({ selected: Schema.Number });

// Home.

/** A work item as Home shows it, with what a client needs to open its thread. */
const WorkCard = Schema.Struct({
  id: Schema.String,
  title: Schema.String,
  employee_id: Schema.String,
  project_id: Schema.NullOr(Schema.String),
  conversation: ConversationKey,
  state: WorkItemState,
  wait_condition: Schema.NullOr(Schema.String),
  due_at: Schema.NullOr(Timestamp),
  updated_at: Timestamp,
  /** Where its steps stand, "2 of 5 · Setting up email"; null without steps. */
  progress: Schema.NullOr(Schema.String),
});
export type WorkCard = typeof WorkCard.Type;
/** A remote app as Needs you names it: its id (for its card and review), name and logo. */
const AppBadge = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  logo: Schema.NullOr(Schema.String),
});
/**
 * One thing waiting on the owner: a request by its kind (a decision, an approve, a take over, a
 * secret or a connect; the whole request, so Needs you is answered from this one read), work that
 * needs one, or a remote app whose sign-in stopped working.
 */
const NeedsYouItem = Schema.Union([
  Schema.Struct({
    ...Decision.fields,
    title: Schema.String,
    work_id: Schema.NullOr(Schema.String),
    project_id: Schema.NullOr(Schema.String),
    /**
     * For `routineActivate`, the proposal it decides, readable as a whole (its schedule in
     * words); null when the routine has since moved to another revision, or for any other.
     */
    routine: Schema.NullOr(Routine),
    /** For a connect request, or a remote app's capability held in `ask` mode, the app. */
    app: Schema.NullOr(AppBadge),
    at: Timestamp,
  }),
  Schema.Struct({
    ...WorkCard.fields,
    kind: Schema.Literal("work"),
    work_id: Schema.String,
    at: Timestamp,
  }),
  Schema.Struct({
    kind: Schema.Literal("reconnect"),
    app: AppBadge,
    at: Timestamp,
  }),
]);
export type NeedsYouItem = typeof NeedsYouItem.Type;
/** A request in Needs you: a decision, an approve, a take over, a secret or a connect. */
export type NeedsYouRequest = Exclude<NeedsYouItem, { kind: "work" } | { kind: "reconnect" }>;
/**
 * `GET …/home`: what needs the owner, work at a glance, and the Chief of Staff's briefing when it was
 * posted by this read (`since` is when they last read their direct chat).
 */
export const Home = Schema.Struct({
  needs_you: Schema.Array(NeedsYouItem),
  glance: Schema.Struct({
    moving: Schema.Array(WorkCard),
    stuck: Schema.Array(WorkCard),
    /** Signed spend approvals in US cents; null before any. */
    spent_cents: Schema.NullOr(Schema.Number),
  }),
  since: Schema.NullOr(Timestamp),
  briefing: Schema.NullOr(Message),
});
export type Home = typeof Home.Type;

// Coding, terminals, files and the browser (the owner's Mac, local mode).

/** `GET …/coding`: work items that have coding sessions, newest first. */
export const CodedWork = Schema.Struct({
  work: Schema.Array(Schema.String),
  /** Each started session and its work item, so a session's ref opens anywhere. */
  sessions: Schema.Array(Schema.Struct({ id: Schema.String, work_item_id: Schema.String })),
});
/** `POST …/coding`: the work item made for the session, and where the session started. */
export const CodingStarted = Schema.Struct({
  work: Schema.String,
  coding_session: Schema.String,
  provider_session_id: Schema.String,
  repository: Schema.String,
  base_commit: Schema.String,
  branch: Schema.String,
  worktree: Schema.String,
});
/** `GET …/work/:id/sessions`. */
export const CodingSessions = Schema.Struct({ sessions: Schema.Array(LiveCodingSession) });
/** `POST …/work/:id/sessions/:session/send`. */
export const Steered = Schema.Struct({ steered: Schema.Boolean });
/** `POST …/work/:id/sessions/:session/interrupt`. */
export const Interrupted = Schema.Struct({ interrupted: Schema.Literal(true) });
/** `GET …/terminals`. */
export const Terminals = Schema.Struct({ terminals: Schema.Array(TerminalSession) });
/** `POST …/terminals/:id/close`. */
export const Closed = Schema.Struct({ closed: Schema.Literal(true) });
/** `GET …/files`: a folder of the business's files. */
export const Folder = Schema.Struct({
  root: Schema.String,
  path: Schema.String,
  entries: Schema.Array(FileEntry),
});
/** `PUT …/files/text` refused with 409: the newer text, so the owner sees what changed. */
export const TextConflict = Schema.Struct({
  conflict: Schema.Literal(true),
  current: Schema.NullOr(FileText),
});
/** `PUT …/files/raw` refused with 409. */
export const BytesConflict = Schema.Struct({ conflict: Schema.Literal(true) });

// Requests a route decodes that no component owns: composed here beside their responses.

const Offset = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));
const Coordinate = Schema.Finite;
/** One anchored comment: a markdown source range, PDF page rectangles, or diff lines. */
const FileAnchor = Schema.Union([
  Schema.Struct({
    kind: Schema.Literal("text"),
    start: Offset,
    end: Offset,
    quote: Schema.String.check(Schema.isMaxLength(4_000)),
  }),
  Schema.Struct({
    kind: Schema.Literal("pdf"),
    page: Offset,
    rects: Schema.Array(
      Schema.Struct({ x: Coordinate, y: Coordinate, width: Coordinate, height: Coordinate }),
    ).check(Schema.isMaxLength(50)),
  }),
  Schema.Struct({ kind: Schema.Literal("lines"), start: Offset, end: Offset }),
]);
export type FileAnchor = typeof FileAnchor.Type;
/** `POST …/files/comments`: comments on a file, sent to an employee or a work item's thread. */
export const FileComments = Schema.Struct({
  /** The sender's own id, so a retried post is stored once. */
  id: Schema.String.check(Schema.isPattern(/^[A-Za-z0-9-]{8,64}$/)),
  path: Schema.String,
  employee: Schema.optional(Schema.String),
  /** A work item whose thread gets the comments, addressed to its owner, instead of a DM. */
  work: Schema.optional(Schema.String),
  comments: Schema.Array(
    Schema.Struct({ anchor: FileAnchor, text: Schema.String.check(Schema.isMaxLength(8_000)) }),
  ).check(Schema.isMinLength(1), Schema.isMaxLength(100)),
  message: Schema.optional(Schema.String.check(Schema.isMaxLength(8_000))),
});
export type FileComments = typeof FileComments.Type;
/**
 * `PUT …/files/text`: the owner's save of a text file, over the revision that was read. Saving by
 * hand is for the work item the owner has taken over (`work`); otherwise they ask.
 */
export const TextSave = Schema.Struct({
  path: Schema.String.check(Schema.isMaxLength(1024)),
  content: Schema.String,
  /** Absent or null: the file must not exist yet. */
  expected_revision: Schema.optional(Schema.NullOr(Schema.String)),
  /** The work item taken over; without it the save is refused (409), as with any other. */
  work: Schema.optional(Schema.String),
});
export type TextSave = typeof TextSave.Type;

// Secrets.

/** `GET`, `POST /api/businesses/:id/secrets` and `DELETE …/secrets/:name`: names, never values. */
export const Secrets = Schema.Struct({ secrets: Schema.Array(SecretEntry) });
