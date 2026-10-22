/**
 * The Devys HTTP API as the web app uses it: the same endpoints as the native apps,
 * authenticated by the browser's session cookie. Mutations are same-origin POSTs. Every
 * response is decoded with the schema its route answers with (`src/app/wire.ts` and the
 * components' contracts), so a drifted shape fails here, plainly, instead of deep in the UI.
 */
import { Schema } from "effect";
import type { Ref } from "../../protocol/ref.ts";
import type { RoleTemplateId } from "../../protocol/roles.ts";
import { Transcript, WorkingDiff } from "../../apps/code/contract.ts";
import type { RemotePolicy } from "../../apps/contract.ts";
import { Grant } from "../../authority/contract.ts";
import { BrowserStatus, PageState, Screenshot, type OwnerInput } from "../../browser/contract.ts";
import type { ConversationKey } from "../../conversations/contract.ts";
import { DeviceCode, DeviceList, Employee, type SettableLook } from "../../identity/contract.ts";
import { ClaimPage } from "../../memory/contract.ts";
import { Authorization, Disconnected } from "../../connections/contract.ts";
import { TerminalSession } from "../../terminal/contract.ts";
import {
  Project,
  ProjectItem,
  Routine,
  WorkItem,
  type NewWorkItem,
  type ProjectChange,
  type WorkItemState,
} from "../../work/contract.ts";
import { FileText, SavedFile } from "../../workspace/contract.ts";
import type { NewSecret } from "../../vault/contract.ts";
import {
  AccessList,
  Answered,
  AppChanged,
  AppReview,
  Apps,
  AppSearch,
  Connecting,
  BusinessCreated,
  BusinessDetail,
  BusinessUpdated,
  BytesConflict,
  Closed,
  CodedWork,
  CodingSessions,
  CodingStarted,
  ConversationPage,
  Conversations,
  Decisions,
  DrivePicker,
  DriveSelected,
  Folder,
  Following,
  GoogleConnection,
  Home,
  Interrupted,
  LookChanged,
  Me,
  ModelCatalog,
  ModelChanged,
  PausedChanged,
  Posted,
  ProfileChanged,
  Projects,
  Read,
  Removed,
  Routines,
  Retired,
  Secrets,
  Revoked,
  Roles,
  RuntimeStatus,
  Steered,
  Stopped,
  Terminals,
  TextConflict,
  WorkItems,
  type FileComments,
  type TextSave,
} from "../../app/wire.ts";

/** The templates a new business can start its team with, beside the Head of Operations. */
export type StartingRole = Exclude<RoleTemplateId, "operations" | "custom">;
interface OutgoingMessage {
  /** The sender's own id, so a retried post is stored once. */
  id: string;
  text: string;
  reply_to?: string;
  mentions?: string[];
  via_voice?: boolean;
  /** The record the owner is viewing beside the conversation. */
  ref?: Ref;
}
export interface NewCodingSession {
  client_id: string;
  employee: string;
  provider: "codex" | "claude";
  objective: string;
  repository?: string;
  new_repository?: string;
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

/** A response whose shape is not the one its route's schema defines. */
class WireError extends Error {
  constructor(path: string, cause: unknown) {
    super(
      `The server's answer to ${path} was not in the expected shape: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
}

/** A JSON value decoded with its route's schema. */
const decode = <T, E>(schema: Schema.Codec<T, E>, path: string, value: unknown): T => {
  try {
    return Schema.decodeUnknownSync(schema)(value);
  } catch (error) {
    throw new WireError(path, error);
  }
};

async function request<T, E>(
  schema: Schema.Codec<T, E>,
  path: string,
  init?: RequestInit,
): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: init?.body ? { "content-type": "application/json", ...init.headers } : init?.headers,
  });
  if (!response.ok) throw new ApiError(response.status, await response.text());
  const text = await response.text();
  let value: unknown;
  try {
    value = text ? JSON.parse(text) : undefined;
  } catch (error) {
    throw new WireError(path, error);
  }
  return decode(schema, path, value);
}
const get = <T, E>(schema: Schema.Codec<T, E>, path: string) => request(schema, path);
const post = <T, E>(schema: Schema.Codec<T, E>, path: string, body: unknown = {}) =>
  request(schema, path, { method: "POST", body: JSON.stringify(body) });
const put = <T, E>(schema: Schema.Codec<T, E>, path: string, body: unknown) =>
  request(schema, path, { method: "PUT", body: JSON.stringify(body) });
/** A call whose answer carries nothing to read (sign-in, sign-out, a reaction's 204). */
async function send(path: string, init: RequestInit) {
  const response = await fetch(path, {
    ...init,
    headers: init.body ? { "content-type": "application/json", ...init.headers } : init.headers,
  });
  if (!response.ok) throw new ApiError(response.status, await response.text());
}
/** Both refusals the save routes answer with 409, decoded like any other answer. */
const conflictOf = async <T, E>(schema: Schema.Codec<T, E>, path: string, response: Response) =>
  decode(schema, path, await response.json());

const business = (id: string) => `/api/businesses/${id}`;
const employee = (b: string, e: string) => `${business(b)}/employees/${e}`;
const conversation = (b: string, key: ConversationKey) =>
  `${business(b)}/conversations/${encodeURIComponent(key)}`;

export const api = {
  enroll: (token: string) =>
    send("/api/enroll", { method: "POST", body: JSON.stringify({ token }) }),
  logout: () => send("/api/logout", { method: "POST", body: "{}" }),
  me: () => get(Me, "/api/me"),
  rename: (displayName: string) => put(Me, "/api/me", { display_name: displayName }),
  createBusiness: (input: { name: string; brief: string; team: StartingRole[] }) =>
    post(BusinessCreated, "/api/businesses", input),
  updateBusiness: (id: string, change: { name?: string; brief?: string }) =>
    put(BusinessUpdated, business(id), change),
  business: (id: string) => get(BusinessDetail, business(id)),
  roles: () => get(Roles, "/api/roles"),
  hire: (
    b: string,
    input: { template: string; name?: string; responsibilities?: string; model?: string },
  ) => post(Employee, `${business(b)}/employees`, input),
  setProfile: (b: string, e: string, change: { name?: string; responsibilities?: string }) =>
    put(ProfileChanged, `${employee(b, e)}/profile`, change),
  retire: (b: string, e: string, reassignTo: string) =>
    post(Retired, `${employee(b, e)}/retire`, { reassign_to: reassignTo }),
  devices: () => get(DeviceList, "/api/devices"),
  issueDeviceCode: () => post(DeviceCode, "/api/devices/codes"),
  revokeDevice: (id: string) => post(Revoked, `/api/devices/${id}/revoke`),
  models: () => get(ModelCatalog, "/api/models"),
  setEmployeeModel: (b: string, e: string, model: string) =>
    put(ModelChanged, `${employee(b, e)}/model`, { model }),
  status: (b: string, e: string) => get(RuntimeStatus, `${employee(b, e)}/status`),
  stop: (b: string, e: string) => post(Stopped, `${employee(b, e)}/stop`),
  setPaused: (b: string, e: string, paused: boolean) =>
    post(PausedChanged, `${employee(b, e)}/${paused ? "pause" : "resume"}`),
  react: (
    b: string,
    e: string,
    reaction: { target_id: string; target_text: string; emoji: string; on: boolean },
  ) => send(`${employee(b, e)}/reactions`, { method: "POST", body: JSON.stringify(reaction) }),
  access: (b: string, e: string) => get(AccessList, `${employee(b, e)}/access`),
  grant: (b: string, e: string, capability: string, mode: "auto" | "ask") =>
    post(Grant, `${employee(b, e)}/access`, { capability, mode }),
  revoke: (b: string, e: string, grantId: string) =>
    post(Revoked, `${employee(b, e)}/access/${grantId}/revoke`),
  follow: (b: string, key: ConversationKey, on: boolean) =>
    post(Following, `${conversation(b, key)}/follow`, { on }),
  conversations: (b: string) => get(Conversations, `${business(b)}/conversations`),
  /** The newest 50 messages, oldest first, or the 50 before a message. */
  conversation: (b: string, key: ConversationKey, before?: string) =>
    get(
      ConversationPage,
      `${conversation(b, key)}${before ? `?before=${encodeURIComponent(before)}` : ""}`,
    ),
  /** Posts in a conversation; `to` is who answers. A 409 says everyone who would is paused. */
  post: (b: string, key: ConversationKey, message: OutgoingMessage) =>
    post(Posted, `${conversation(b, key)}/messages`, message),
  markRead: (b: string, key: ConversationKey, at: string) =>
    post(Read, `${conversation(b, key)}/read`, { at }),
  memory: (b: string) => get(ClaimPage, `${business(b)}/memory`),
  work: (b: string) => get(WorkItems, `${business(b)}/work`),
  createWorkItem: (b: string, workItem: NewWorkItem) =>
    post(WorkItem, `${business(b)}/work`, workItem),
  updateWorkItem: (
    b: string,
    item: WorkItem,
    change: {
      state?: WorkItemState;
      owner?: string;
      next_action?: string;
      wait_condition?: string | null;
      due_at?: string | null;
    },
  ) =>
    post(WorkItem, `${business(b)}/work/${item.id}`, {
      expected_revision: item.revision,
      ...change,
    }),
  setTakeover: (b: string, id: string, takeOver: boolean) =>
    post(WorkItem, `${business(b)}/work/${id}/${takeOver ? "takeover" : "release"}`),
  codingSessions: (b: string, work: string) =>
    get(CodingSessions, `${business(b)}/work/${work}/sessions`),
  sessionTranscript: (b: string, work: string, session: string) =>
    get(Transcript, `${business(b)}/work/${work}/sessions/${session}/transcript`),
  sessionDiff: (b: string, work: string, session: string) =>
    get(WorkingDiff, `${business(b)}/work/${work}/sessions/${session}/diff`),
  steerSession: (b: string, work: string, session: string, text: string) =>
    post(Steered, `${business(b)}/work/${work}/sessions/${session}/send`, { text }),
  stopSession: (b: string, work: string, session: string) =>
    post(Interrupted, `${business(b)}/work/${work}/sessions/${session}/interrupt`),
  /** Work items that have coding sessions, newest first. */
  codingWork: (b: string) => get(CodedWork, `${business(b)}/coding`),
  startCoding: (b: string, session: NewCodingSession) =>
    post(CodingStarted, `${business(b)}/coding`, session),
  files: (b: string, path?: string) =>
    get(Folder, `${business(b)}/files${path ? `?path=${encodeURIComponent(path)}` : ""}`),
  fileText: (b: string, path: string) =>
    get(FileText, `${business(b)}/files/text?path=${encodeURIComponent(path)}`),
  /** Saves over the revision that was read; a newer file on the Mac comes back as `conflict`. */
  saveFile: async (
    b: string,
    work: string,
    path: string,
    content: string,
    expectedRevision: string | null,
  ) => {
    const url = `${business(b)}/files/text`;
    const save: TextSave = { path, content, expected_revision: expectedRevision, work };
    const response = await fetch(url, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(save),
    });
    if (response.status === 409) return await conflictOf(TextConflict, url, response);
    if (!response.ok)
      throw new ApiError(response.status, (await response.text()) || "The file couldn't be saved.");
    return { conflict: false as const, ...decode(SavedFile, url, await response.json()) };
  },
  /** A file's bytes and the revision they were read at. */
  fileBytes: async (b: string, path: string) => {
    const response = await fetch(`${business(b)}/files/raw?path=${encodeURIComponent(path)}`);
    if (!response.ok) throw new ApiError(response.status, "This file couldn't be opened.");
    return {
      bytes: await response.arrayBuffer(),
      revision: response.headers.get("x-devys-revision") ?? "",
    };
  },
  /**
   * Saves bytes over the revision that was read (`null`: the file must not exist yet). With no
   * revision at all it overwrites, which only derived copies such as a deck's .pptx do. Saving
   * by hand is for the work item the owner has taken over (`work`).
   */
  saveFileBytes: async (
    b: string,
    work: string,
    path: string,
    bytes: ArrayBuffer,
    expectedRevision?: string | null,
  ) => {
    const revision =
      expectedRevision === undefined ? "" : `&expected_revision=${expectedRevision ?? "none"}`;
    const url = `${business(b)}/files/raw?path=${encodeURIComponent(path)}&work=${encodeURIComponent(work)}${revision}`;
    const response = await fetch(url, { method: "PUT", body: bytes });
    if (response.status === 409) return await conflictOf(BytesConflict, url, response);
    if (!response.ok)
      throw new ApiError(response.status, (await response.text()) || "The file couldn't be saved.");
    return { conflict: false as const, ...decode(SavedFile, url, await response.json()) };
  },
  fileUrl: (b: string, path: string) => `${business(b)}/files/raw?path=${encodeURIComponent(path)}`,
  /** Comments sent as one message: to an employee's DM, or a work item's thread (its owner). */
  commentOnFile: (b: string, comment: typeof FileComments.Encoded) =>
    post(Posted, `${business(b)}/files/comments`, comment),
  terminals: (b: string) => get(Terminals, `${business(b)}/terminals`),
  openTerminal: (b: string, open: { work?: string; resume?: string; cols: number; rows: number }) =>
    post(TerminalSession, `${business(b)}/terminals`, open),
  closeTerminal: (b: string, id: string) => post(Closed, `${business(b)}/terminals/${id}/close`),
  terminalSocket: (b: string, id: string, offset: number) =>
    `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}${business(b)}/terminals/${id}/socket?offset=${offset}`,
  /** One work item's requests, answered ones included. */
  workDecisions: (b: string, workItem: string) =>
    get(Decisions, `${business(b)}/decisions?work_item=${encodeURIComponent(workItem)}`),
  answer: (b: string, id: string, approve: boolean) =>
    post(Answered, `${business(b)}/decisions/${id}/${approve ? "approve" : "reject"}`),
  /** The business's secrets by name; values are never read back. */
  secrets: (b: string) => get(Secrets, `${business(b)}/secrets`),
  /**
   * The secure entry sheet's one post: the value goes straight to the server (and on to the Mac
   * host, which seals it), never into a query cache, a conversation or a log.
   */
  addSecret: (b: string, entry: NewSecret) => post(Secrets, `${business(b)}/secrets`, entry),
  removeSecret: (b: string, name: string) =>
    request(Secrets, `${business(b)}/secrets/${encodeURIComponent(name)}`, { method: "DELETE" }),
  projects: (b: string) => get(Projects, `${business(b)}/projects`),
  routines: (b: string) => get(Routines, `${business(b)}/routines`),
  setRoutinePaused: (b: string, id: string, paused: boolean) =>
    post(Routine, `${business(b)}/routines/${id}/${paused ? "pause" : "resume"}`),
  createProject: (b: string, project: ProjectChange & { name: string }) =>
    post(Project, `${business(b)}/projects`, project),
  addToProject: (b: string, project: string, ref: Ref) =>
    post(ProjectItem, `${business(b)}/projects/${project}/items`, { ref }),
  removeFromProject: (b: string, project: string, item: string) =>
    post(Removed, `${business(b)}/projects/${project}/items/${item}/remove`),
  apps: (b: string) => get(Apps, `${business(b)}/apps`),
  installApp: (b: string, app: string, on: boolean) =>
    post(AppChanged, `${business(b)}/apps/${app}/${on ? "install" : "uninstall"}`),
  pinApp: (b: string, app: string, pinned: boolean) =>
    post(AppChanged, `${business(b)}/apps/${app}/pin`, { pinned }),
  searchApps: (b: string, query: string) =>
    get(AppSearch, `${business(b)}/apps/search?q=${encodeURIComponent(query)}`),
  addApp: (b: string, app: string) => post(AppChanged, `${business(b)}/apps/add`, { app }),
  connectApp: (b: string, app: string) =>
    post(Connecting, `${business(b)}/apps/${app}/connect`, { native: false }),
  appReview: (b: string, app: string) => get(AppReview, `${business(b)}/apps/${app}/review`),
  acceptApp: (b: string, app: string, acceptance: RemotePolicy) =>
    post(AppChanged, `${business(b)}/apps/${app}/accept`, acceptance),
  home: (b: string) => get(Home, `${business(b)}/home`),
  artifactText: async (b: string, id: string) => {
    const response = await fetch(`${business(b)}/artifacts/${id}`);
    if (!response.ok) throw new ApiError(response.status, "This file couldn't be opened.");
    return response.text();
  },
  artifactUrl: (b: string, id: string) => `${business(b)}/artifacts/${id}`,
  /** The business's browser: where it is and which work drives it. */
  browserStatus: (b: string) => get(BrowserStatus, `${business(b)}/browser`),
  browserScreenshot: (b: string) => get(Screenshot, `${business(b)}/browser/screenshot`),
  browserInput: (b: string, action: OwnerInput) =>
    post(PageState, `${business(b)}/browser/input`, action),
  exportUrl: (b: string) => `${business(b)}/export`,
  /** Google Drive for Documents: the connection, connecting, the picker and picked files. */
  google: (b: string) => get(GoogleConnection, `${business(b)}/connections/google`),
  connectGoogle: (b: string) => post(Authorization, `${business(b)}/connections/google/connect`),
  disconnectGoogle: (b: string) =>
    post(Disconnected, `${business(b)}/connections/google/disconnect`),
  drivePicker: (b: string) => post(DrivePicker, `${business(b)}/connections/google/picker`),
  selectDrive: (b: string, ids: string[]) =>
    post(DriveSelected, `${business(b)}/connections/google/select`, { ids }),
  setBusinessLook: (b: string, look: SettableLook) =>
    post(LookChanged, `${business(b)}/look`, { look }),
  setEmployeeLook: (b: string, e: string, look: SettableLook) =>
    post(LookChanged, `${employee(b, e)}/look`, { look }),
  /** Uploads a photo already downscaled by the browser; the server makes it the look. */
  uploadLookPhoto: (path: string, image: Blob) =>
    request(LookChanged, `${path}/look/photo`, {
      method: "PUT",
      body: image,
      headers: { "content-type": image.type },
    }),
  businessPath: business,
  employeePath: employee,
  profilePhotoUrl: "/api/profile/photo",
  uploadProfilePhoto: (image: Blob) =>
    send(`/api/profile/photo`, {
      method: "PUT",
      body: image,
      headers: { "content-type": image.type },
    }),
  removeProfilePhoto: () => send(`/api/profile/photo`, { method: "DELETE" }),
};
