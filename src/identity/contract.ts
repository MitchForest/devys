/** Public identity facts other components may rely on. Storage stays internal. */
export interface Person {
  id: string;
  display_name: string;
}

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

/**
 * How a business or employee appears, the same in every client: a Face, an emoji on a
 * tinted tile, or a photo. `version` changes with each upload so clients refetch it.
 */
export type Look =
  | {
      kind: "face";
      palette: (typeof palettes)[number];
      shape: (typeof shapes)[number];
      seed: number;
    }
  | { kind: "emoji"; emoji: string; tint: (typeof tints)[number] }
  | { kind: "photo"; version: string };

/** The tenant and security boundary. */
export interface Business {
  id: string;
  name: string;
  /** Null shows the business's initial on its tile. */
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

/** An agent principal. It belongs to exactly one business. */
export interface Employee {
  id: string;
  business_id: string;
  name: string;
  role: string;
  /** A model id from config/models.ts, chosen when the employee is set up. */
  model: string;
  /** The role template the employee was hired from. */
  template: RoleTemplateId;
  /** Paused employees take no actions until the owner resumes them. */
  paused: boolean;
  /** Null shows the employee's default Face. */
  look: Look | null;
}

/** One employee of one business: names its agent runtime and its workspace. */
export interface Scope {
  businessId: string;
  employeeId: string;
}

export const scopeName = (scope: Scope) => JSON.stringify([scope.businessId, scope.employeeId]);

export const sessionCookie = "__Host-devys";
