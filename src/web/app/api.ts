/**
 * The Devys HTTP API as the web app uses it: the same endpoints as the native apps,
 * authenticated by the browser's session cookie. Mutations are same-origin POSTs.
 */

export interface Person {
  id: string;
  display_name: string;
}
/** How a business or employee appears, the same in every client. */
export type Look =
  | { kind: "face"; palette: string; shape: string; seed: number }
  | { kind: "emoji"; emoji: string; tint: string }
  | { kind: "photo"; version: string };
export type SettableLook = Exclude<Look, { kind: "photo" }> | null;
export interface Business {
  id: string;
  name: string;
  look: Look | null;
  /** What the business does, its goals and constraints; every employee reads it. */
  brief: string;
}
export type RoleTemplateId =
  | "operations"
  | "engineering"
  | "growth"
  | "business-operations"
  | "custom";
/** A role to hire from: copied into an ordinary employee, with its starting access. */
export interface RoleTemplate {
  id: Exclude<RoleTemplateId, "operations">;
  name: string;
  summary: string;
  responsibilities: string;
  capabilities: string[];
}
/** The templates a new business can start its team with, beside the Head of Operations. */
export type StartingRole = "engineering" | "growth" | "business-operations";
/** A signed-in browser or app of the current person. */
export interface Device {
  id: string;
  /** The name an app gave when it signed in; browsers have none. */
  label: string | null;
  created_at: string;
  expires_at: string;
  current: boolean;
}
export interface Employee {
  id: string;
  business_id: string;
  name: string;
  /** Responsibilities, up to 2000 characters. */
  role: string;
  template: RoleTemplateId;
  paused: boolean;
  look: Look | null;
  /** A model id from the catalog. */
  model: string;
}
/** A model employees can use, priced in dollars per million tokens. */
export interface ModelOption {
  id: string;
  label: string;
  vendor: string;
  provider: string;
  summary: string;
  effort: "low" | "medium" | "high";
  price: { input: number; output: number; cacheRead: number };
  typicalTurnUsd: number;
}
export interface ModelCatalog {
  defaults: { employee: string; background: string };
  models: ModelOption[];
}
/** Tokens and dollars spent, as pi-ai reports them. */
export interface Usage {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  totalTokens: number;
  cost: { input: number; output: number; cacheRead: number; cacheWrite: number; total: number };
}
export interface Artifact {
  id: string;
  filename: string;
  content_type: string;
  byte_length: number;
  created_at: string;
}
export interface RuntimeState {
  run: { id: string; stopped: boolean; deadline: number | null } | null;
  inbox: { id: string; text?: string; receivedAt: number; status: string }[];
  outbox: { id: string; text: string; status: string }[];
  /** Spend by "provider/modelId" and by tool. */
  usage?: { models: Record<string, Usage>; tools: Record<string, Usage> };
}
/** `direct:<employee>`, `space:<space>` or `work:<commitment>`. */
export type ConversationKey = `${"direct" | "space" | "work"}:${string}`;
/** One entry in a conversation: something someone said, or an event such as a hand-off. */
export interface Message {
  id: string;
  conversation: ConversationKey;
  /** `person:<id>`, `employee:<id>` or `system`. */
  author: string;
  kind: "message" | "event";
  text: string;
  reply_to: string | null;
  /** Employee ids this message addresses. */
  mentions: string[];
  via_voice: boolean;
  /** What an event is about: the commitment a hand-off card opens. */
  ref: string | null;
  created_at: string;
}
export interface ShownMessage extends Message {
  reactions: string[];
}
export interface ConversationSummary {
  key: ConversationKey;
  last: Message | null;
  unread: number;
  /** The signed-in person follows it: a work thread they hear each milestone of. */
  following: boolean;
}
export interface OutgoingMessage {
  /** The sender's own id, so a retried post is stored once. */
  id: string;
  text: string;
  replyTo?: string;
  mentions?: string[];
  viaVoice?: boolean;
}
export type CommitmentState =
  | "proposed"
  | "ready"
  | "in_progress"
  | "waiting"
  | "needs_decision"
  | "completed"
  | "cancelled";
export interface Commitment {
  id: string;
  owner_employee_id: string;
  title: string;
  objective: string;
  next_action: string;
  wait_condition: string | null;
  due_at: string | null;
  state: CommitmentState;
  evidence: {
    by: string;
    note: string;
    at: string;
    commit?: string;
    check?: { command: string; exitCode: number | null };
    changes?: string;
    pullRequest?: string;
    deploy?: { stage: "preview" | "production"; url: string | null; live: boolean };
  }[];
  revision: number;
  taken_over_by: string | null;
  updated_at: string;
}
/** A Codex or Claude Code session on a work item, with its live state from the provider. */
export interface CodingSession {
  id: string;
  commitment_id: string;
  employee_id: string;
  provider: "codex" | "claude";
  purpose: "build" | "review";
  objective: string;
  repository: string | null;
  /** The commit the session's branch started from, which its diff is against. */
  base_commit: string | null;
  branch: string | null;
  worktree: string | null;
  created_at: string;
  state: "working" | "idle" | "interrupted" | "failed" | "unavailable";
  reply: string | null;
  diffStat: string;
  error: string | null;
}
/** One step of what a coding session did, read from the harness when asked. */
export interface TranscriptEntry {
  kind: "prompt" | "reply" | "plan" | "command" | "files" | "tool";
  text: string;
  detail?: string;
  failed?: boolean;
}
export interface WorkingDiff {
  files: { path: string; status: string; added: number; removed: number }[];
  patch: string;
}
/** A terminal on the owner's Mac; the host keeps it while devices come and go. */
export interface TerminalSession {
  id: string;
  title: string;
  cwd: string;
  assignmentId: string | null;
  startedAt: string;
  offset: number;
  writer: string | null;
  exit: { code: number | null } | null;
}

export interface FileEntry {
  name: string;
  path: string;
  kind: "file" | "directory" | "other";
  size: number;
}
export interface FileText {
  path: string;
  content: string;
  revision: string;
}
export type FileAnchor =
  | { kind: "text"; start: number; end: number; quote: string }
  | { kind: "pdf"; page: number; rects: { x: number; y: number; width: number; height: number }[] };

export interface NewCodingSession {
  clientId: string;
  employee: string;
  provider: "codex" | "claude";
  objective: string;
  repository?: string;
  newRepository?: string;
}

export interface Decision {
  id: string;
  employee_id: string;
  capability: string;
  input: unknown;
  commitment_id: string | null;
  status: "pending" | "approved" | "rejected" | "used";
  requested_at: string;
  expires_at: string;
}
export interface SpaceItem {
  id: string;
  kind: "commitment" | "artifact" | "file";
  ref: string;
}
export interface Space {
  id: string;
  name: string;
  purpose: string;
  /** The employee who answers in the space's thread unless the owner mentions someone. */
  lead_employee_id: string | null;
  items: SpaceItem[];
}
export interface NewTask {
  title: string;
  owner: string;
  objective?: string;
  dueAt?: string;
  spaceId?: string;
}
export interface Grant {
  id: string;
  capability: string;
  mode: "auto" | "ask";
  constraints: { hosts?: string[] };
  description?: string;
  effect?: string;
}
export interface AccessList {
  grants: Grant[];
  available: { capability: string; description: string; effect: string }[];
}
export interface MemoryClaim {
  key: string;
  content: string;
  source_kind: string;
  revision: number;
  updated_at: string;
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: init?.body ? { "content-type": "application/json", ...init.headers } : init?.headers,
  });
  if (!response.ok) throw new ApiError(response.status, await response.text());
  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}
const get = <T>(path: string) => request<T>(path);
const post = <T = unknown>(path: string, body: unknown = {}) =>
  request<T>(path, { method: "POST", body: JSON.stringify(body) });
const put = <T = unknown>(path: string, body: unknown) =>
  request<T>(path, { method: "PUT", body: JSON.stringify(body) });

const business = (id: string) => `/api/businesses/${id}`;
const employee = (b: string, e: string) => `${business(b)}/employees/${e}`;
const conversation = (b: string, key: ConversationKey) =>
  `${business(b)}/conversations/${encodeURIComponent(key)}`;

export const api = {
  enroll: (token: string) => post("/api/enroll", { token }),
  logout: () => post("/api/logout"),
  me: () => get<{ person: Person; businesses: Business[] }>("/api/me"),
  createBusiness: (input: { name: string; brief: string; team: StartingRole[] }) =>
    post<{ business: Business; operations: Employee; team: Employee[] }>("/api/businesses", input),
  updateBusiness: (id: string, change: { name?: string; brief?: string }) =>
    put<{ business: Business }>(business(id), change),
  business: (id: string) =>
    get<{
      business: Business;
      employees: Employee[];
      members: Person[];
      artifacts: Artifact[];
    }>(business(id)),
  roles: () => get<{ roles: RoleTemplate[] }>("/api/roles"),
  hire: (
    b: string,
    input: { template: string; name?: string; responsibilities?: string; model?: string },
  ) => post<Employee>(`${business(b)}/employees`, input),
  setProfile: (b: string, e: string, change: { name?: string; responsibilities?: string }) =>
    put<{ name?: string; role?: string }>(`${employee(b, e)}/profile`, change),
  retire: (b: string, e: string, reassignTo: string) =>
    post<{ retired: true; reassignedTo: string }>(`${employee(b, e)}/retire`, { reassignTo }),
  devices: () => get<{ devices: Device[] }>("/api/devices"),
  issueDeviceCode: () => post<{ code: string; expiresAt: string }>("/api/devices/codes"),
  revokeDevice: (id: string) => post(`/api/devices/${id}/revoke`),
  models: () => get<ModelCatalog>("/api/models"),
  setEmployeeModel: (b: string, e: string, model: string) =>
    put<{ model: string }>(`${employee(b, e)}/model`, { model }),
  status: (b: string, e: string) => get<{ state: RuntimeState }>(`${employee(b, e)}/status`),
  stop: (b: string, e: string) => post(`${employee(b, e)}/stop`),
  setPaused: (b: string, e: string, paused: boolean) =>
    post(`${employee(b, e)}/${paused ? "pause" : "resume"}`),
  react: (
    b: string,
    e: string,
    reaction: { targetId: string; targetText: string; emoji: string; on: boolean },
  ) => post(`${employee(b, e)}/reactions`, reaction),
  access: (b: string, e: string) => get<AccessList>(`${employee(b, e)}/access`),
  grant: (b: string, e: string, capability: string, mode: "auto" | "ask") =>
    post(`${employee(b, e)}/access`, { capability, mode }),
  revoke: (b: string, e: string, grantId: string) =>
    post(`${employee(b, e)}/access/${grantId}/revoke`),
  follow: (b: string, key: ConversationKey, on: boolean) =>
    post<{ following: boolean }>(`${business(b)}/conversations/${encodeURIComponent(key)}/follow`, {
      on,
    }),
  conversations: (b: string) =>
    get<{ conversations: ConversationSummary[] }>(`${business(b)}/conversations`),
  /** The newest 50 messages, oldest first, or the 50 before a message. */
  conversation: (b: string, key: ConversationKey, before?: string) =>
    get<{ messages: ShownMessage[]; respondent: string | null }>(
      `${conversation(b, key)}${before ? `?before=${encodeURIComponent(before)}` : ""}`,
    ),
  /** Posts in a conversation; `to` is who answers. A 409 says everyone who would is paused. */
  post: (b: string, key: ConversationKey, message: OutgoingMessage) =>
    post<{ message: Message; to: string[] }>(`${conversation(b, key)}/messages`, message),
  markRead: (b: string, key: ConversationKey, at: string) =>
    post(`${conversation(b, key)}/read`, { at }),
  memory: (b: string) => get<{ items: MemoryClaim[] }>(`${business(b)}/memory`),
  work: (b: string) => get<{ commitments: Commitment[] }>(`${business(b)}/work`),
  createCommitment: (b: string, task: NewTask) => post<Commitment>(`${business(b)}/work`, task),
  updateCommitment: (
    b: string,
    item: Commitment,
    change: {
      state?: CommitmentState;
      owner?: string;
      nextAction?: string;
      waitCondition?: string | null;
      dueAt?: string | null;
    },
  ) =>
    post<Commitment>(`${business(b)}/work/${item.id}`, {
      expectedRevision: item.revision,
      ...change,
    }),
  setTakeover: (b: string, id: string, takeOver: boolean) =>
    post(`${business(b)}/work/${id}/${takeOver ? "takeover" : "release"}`),
  codingSessions: (b: string, work: string) =>
    get<{ sessions: CodingSession[] }>(`${business(b)}/work/${work}/sessions`),
  sessionTranscript: (b: string, work: string, session: string) =>
    get<{ entries: TranscriptEntry[] }>(
      `${business(b)}/work/${work}/sessions/${session}/transcript`,
    ),
  sessionDiff: (b: string, work: string, session: string) =>
    get<WorkingDiff>(`${business(b)}/work/${work}/sessions/${session}/diff`),
  steerSession: (b: string, work: string, session: string, text: string) =>
    post<{ steered: boolean }>(`${business(b)}/work/${work}/sessions/${session}/send`, { text }),
  stopSession: (b: string, work: string, session: string) =>
    post(`${business(b)}/work/${work}/sessions/${session}/interrupt`),
  startCoding: (b: string, session: NewCodingSession) =>
    post<{ work: string; assignment: string }>(`${business(b)}/coding`, session),
  files: (b: string, path?: string) =>
    get<{ root: string; path: string; entries: FileEntry[] }>(
      `${business(b)}/files${path ? `?path=${encodeURIComponent(path)}` : ""}`,
    ),
  fileText: (b: string, path: string) =>
    get<FileText>(`${business(b)}/files/text?path=${encodeURIComponent(path)}`),
  /** Saves over the revision that was read; a newer file on the Mac comes back as `conflict`. */
  saveFile: async (b: string, path: string, content: string, expectedRevision: string | null) => {
    const response = await fetch(`${business(b)}/files/text`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ path, content, expectedRevision }),
    });
    if (response.status === 409)
      return {
        conflict: true as const,
        current: ((await response.json()) as { current: FileText | null }).current,
      };
    if (!response.ok)
      throw new ApiError(response.status, (await response.text()) || "The file couldn't be saved.");
    return {
      conflict: false as const,
      ...((await response.json()) as { path: string; revision: string }),
    };
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
   * revision at all it overwrites, which only derived copies such as a deck's .pptx do.
   */
  saveFileBytes: async (
    b: string,
    path: string,
    bytes: ArrayBuffer,
    expectedRevision?: string | null,
  ) => {
    const revision =
      expectedRevision === undefined ? "" : `&expectedRevision=${expectedRevision ?? "none"}`;
    const response = await fetch(
      `${business(b)}/files/raw?path=${encodeURIComponent(path)}${revision}`,
      { method: "PUT", body: bytes },
    );
    if (response.status === 409) return { conflict: true as const };
    if (!response.ok)
      throw new ApiError(response.status, (await response.text()) || "The file couldn't be saved.");
    return {
      conflict: false as const,
      ...((await response.json()) as { path: string; revision: string }),
    };
  },
  fileUrl: (b: string, path: string) => `${business(b)}/files/raw?path=${encodeURIComponent(path)}`,
  commentOnFile: (
    b: string,
    comment: {
      id: string;
      path: string;
      /** An employee's DM, or a work item's thread (addressed to its owner). */
      employee?: string;
      work?: string;
      comments: { anchor: FileAnchor; text: string }[];
    },
  ) => post(`${business(b)}/files/comments`, comment),
  terminals: (b: string) => get<{ terminals: TerminalSession[] }>(`${business(b)}/terminals`),
  openTerminal: (b: string, open: { work?: string; resume?: string; cols: number; rows: number }) =>
    post<TerminalSession>(`${business(b)}/terminals`, open),
  closeTerminal: (b: string, id: string) => post(`${business(b)}/terminals/${id}/close`),
  terminalSocket: (b: string, id: string, offset: number) =>
    `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}${business(b)}/terminals/${id}/socket?offset=${offset}`,
  decisions: (b: string) => get<{ decisions: Decision[] }>(`${business(b)}/decisions`),
  /** One work item's requests, answered ones included. */
  workDecisions: (b: string, commitment: string) =>
    get<{ decisions: Decision[] }>(
      `${business(b)}/decisions?commitment=${encodeURIComponent(commitment)}`,
    ),
  answer: (b: string, id: string, approve: boolean) =>
    post(`${business(b)}/decisions/${id}/${approve ? "approve" : "reject"}`),
  spaces: (b: string) => get<{ spaces: Space[] }>(`${business(b)}/spaces`),
  createSpace: (b: string, space: { name: string; purpose?: string; lead?: string }) =>
    post<Space>(`${business(b)}/spaces`, space),
  updateSpace: (
    b: string,
    id: string,
    change: { name?: string; purpose?: string; lead?: string },
  ) => put(`${business(b)}/spaces/${id}`, change),
  addToSpace: (b: string, space: string, kind: SpaceItem["kind"], ref: string) =>
    post(`${business(b)}/spaces/${space}/items`, { kind, ref }),
  removeFromSpace: (b: string, space: string, item: string) =>
    post(`${business(b)}/spaces/${space}/items/${item}/remove`),
  artifactText: async (b: string, id: string) => {
    const response = await fetch(`${business(b)}/artifacts/${id}`);
    if (!response.ok) throw new ApiError(response.status, "This file couldn't be opened.");
    return response.text();
  },
  artifactUrl: (b: string, id: string) => `${business(b)}/artifacts/${id}`,
  exportUrl: (b: string) => `${business(b)}/export`,
  setBusinessLook: (b: string, look: SettableLook) =>
    post<{ look: Look | null }>(`${business(b)}/look`, { look }),
  setEmployeeLook: (b: string, e: string, look: SettableLook) =>
    post<{ look: Look | null }>(`${employee(b, e)}/look`, { look }),
  /** Uploads a photo already downscaled by the browser; the server makes it the look. */
  uploadLookPhoto: (path: string, image: Blob) =>
    request<{ look: Look }>(`${path}/look/photo`, {
      method: "PUT",
      body: image,
      headers: { "content-type": image.type },
    }),
  businessPath: business,
  employeePath: employee,
  profilePhotoUrl: "/api/profile/photo",
  uploadProfilePhoto: (image: Blob) =>
    request(`/api/profile/photo`, {
      method: "PUT",
      body: image,
      headers: { "content-type": image.type },
    }),
  removeProfilePhoto: () => request(`/api/profile/photo`, { method: "DELETE" }),
};
