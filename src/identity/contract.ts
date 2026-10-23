import { Schema } from "effect";
import { HireableRoleId, RoleTemplateId } from "../protocol/roles.ts";
import { Timestamp } from "../protocol/time.ts";

/** Public identity facts other components may rely on. Storage stays internal. */
export const Person = Schema.Struct({ id: Schema.String, display_name: Schema.String });
export type Person = typeof Person.Type;
/** `PUT /api/me`: the name the signed-in person goes by; not blank, at most 80 characters. */
export const NameChange = Schema.Struct({
  display_name: Schema.String.check(
    Schema.isMaxLength(80),
    Schema.makeFilter((value) => value.trim().length > 0 || "Expected a name"),
  ),
});

export const palettes = [
  "brown",
  "red",
  "orange",
  "amber",
  "green",
  "teal",
  "blue",
  "purple",
  "pink",
  "gray",
] as const;
export const shapes = [
  "circle",
  "blob",
  "roundedSquare",
  "capsule",
  "triangle",
  "hexagon",
  "cloud",
  "drop",
] as const;
export const tints = ["blue", "orange", "green", "purple", "pink"] as const;

const FaceLook = Schema.Struct({
  kind: Schema.Literal("face"),
  palette: Schema.Literals(palettes),
  shape: Schema.Literals(shapes),
  seed: Schema.Int,
});
const EmojiLook = Schema.Struct({
  kind: Schema.Literal("emoji"),
  emoji: Schema.String,
  tint: Schema.Literals(tints),
});
/**
 * How a business or employee appears, the same in every client: a Face, an emoji on a
 * tinted tile, or a photo. `version` changes with each upload so clients refetch it.
 */
export const Look = Schema.Union([
  FaceLook,
  EmojiLook,
  Schema.Struct({ kind: Schema.Literal("photo"), version: Schema.String }),
]);
export type Look = typeof Look.Type;
/** A look a client sets directly: a Face, an emoji, or null for the default. Photos upload. */
export type SettableLook = Exclude<Look, { kind: "photo" }> | null;

/** The tenant and security boundary. */
export const Business = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  /** Null shows the business's initial on its tile. */
  look: Schema.NullOr(Look),
  /** What the business does, its goals and constraints; every employee reads it. */
  brief: Schema.String,
});
export type Business = typeof Business.Type;

/** An agent principal. It belongs to exactly one business. */
export const Employee = Schema.Struct({
  id: Schema.String,
  business_id: Schema.String,
  name: Schema.String,
  /** What the employee is accountable for, up to 2000 characters. */
  responsibilities: Schema.String,
  /** A model id from config/models.ts, chosen when the employee is set up. */
  model: Schema.String,
  /** The role template the employee was hired from. */
  template: RoleTemplateId,
  /** Paused employees take no actions until the owner resumes them. */
  paused: Schema.Boolean,
  /** Null shows the employee's default Face. */
  look: Schema.NullOr(Look),
});
export type Employee = typeof Employee.Type;

/** A role to hire from: copied into an ordinary employee, with its starting access. */
export const RoleTemplate = Schema.Struct({
  id: HireableRoleId,
  name: Schema.String,
  summary: Schema.String,
  responsibilities: Schema.String,
  /** The capabilities its employees are granted at hire. */
  capabilities: Schema.Array(Schema.String),
});
export type RoleTemplate = typeof RoleTemplate.Type;

/** A signed-in browser or app of a person. */
export const Device = Schema.Struct({
  id: Schema.String,
  /** The name an app gave when it signed in; browsers have none. */
  label: Schema.NullOr(Schema.String),
  created_at: Timestamp,
  expires_at: Timestamp,
  /** The device this request came from. */
  current: Schema.Boolean,
});
/** `GET /api/devices`. */
export type Device = typeof Device.Type;
export const DeviceList = Schema.Struct({ devices: Schema.Array(Device) });
/**
 * `GET /api/hello`: what a device about to connect calls this Devys (the Mac's name), and the
 * address other devices reach it at (the QR code in Settings › Devices carries both).
 */
export const Hello = Schema.Struct({ name: Schema.String, url: Schema.String });

/**
 * A device asking to join: what it calls itself and the two emoji both screens show, so the
 * owner allows the device in their hand and not a stranger's asking at the same moment.
 */
export const JoinRequest = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  match: Schema.Tuple([Schema.String, Schema.String]),
  expires_at: Timestamp,
});
export type JoinRequest = typeof JoinRequest.Type;
/** `GET /api/joins`: requests waiting for an answer, for every signed-in device. */
export const JoinRequests = Schema.Struct({ joins: Schema.Array(JoinRequest) });
/** `GET /api/joins/:id`: the asking device's view of its request. */
export const JoinStatus = Schema.Struct({
  status: Schema.Literals(["pending", "allowed", "denied", "expired"]),
});

/** One employee of one business: names its agent runtime and its workspace. */
export interface Scope {
  businessId: string;
  employeeId: string;
}

export const scopeName = (scope: Scope) => JSON.stringify([scope.businessId, scope.employeeId]);

export const sessionCookie = "__Host-devys";
