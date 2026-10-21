import { Effect } from "effect";
import { atomically, type Database } from "../data/database.ts";
import type { RoleTemplateId } from "../protocol/roles.ts";
import type { Scope } from "./contract.ts";
import { activeEmployee, createEmployee } from "./service.ts";

/** Whether an employee directs others' work: the Head of Operations coordinates the team. */
export const coordinates = async (db: Database, scope: Scope) =>
  (await Effect.runPromise(activeEmployee(db, scope)))?.template === "operations";

/**
 * Role templates. Hiring copies one into an ordinary employee that the owner can then
 * edit; a template is not a record and later edits never flow back into it. What a role is
 * granted comes from the apps' manifests (`defaultGrants`); a template only says which of
 * those grants are held in `ask` mode.
 */
export interface RoleTemplate {
  id: RoleTemplateId;
  name: string;
  responsibilities: string;
  summary: string;
  /** Granted capabilities held in `ask` mode, so each use is a decision the owner approves. */
  ask?: readonly string[];
}

export const roleTemplates: readonly RoleTemplate[] = [
  {
    id: "operations",
    name: "Head of Operations",
    summary: "Runs the business day to day and coordinates the team.",
    responsibilities:
      "Run the business day to day. Keep the owner's priorities moving, coordinate the team by handing work to the right employee as work items, notice what is blocked or late, and bring the owner only real decisions. Propose new hires when the work needs a role nobody holds.",
    ask: ["hireEmployee", "deployProduction"],
  },
  {
    id: "engineering",
    name: "Engineering",
    summary: "Builds, fixes and ships the business's software.",
    responsibilities:
      "Build, fix and ship the business's software. Work in the repositories on the owner's computer, run tests before calling work done, keep changes small and reviewable, and report what changed with evidence.",
    // Previews ship on Engineering's own authority; production is the owner's decision.
    ask: ["deployProduction"],
  },
  {
    id: "growth",
    name: "Growth",
    summary: "Finds customers: research, positioning, campaigns and outreach.",
    responsibilities:
      "Grow the business. Research the market and competitors, sharpen positioning, plan and measure campaigns, and prepare outreach for the owner's approval. Ground claims in sources.",
  },
  {
    id: "business-operations",
    name: "Business Operations",
    summary: "Keeps records, documents, suppliers and admin in order.",
    responsibilities:
      "Keep the business's records, documents and administration in order: suppliers, accounts, schedules and paperwork. Track follow-ups as work items so nothing is dropped.",
  },
  {
    id: "custom",
    name: "",
    summary: "Start from a blank role and describe it yourself.",
    responsibilities: "",
  },
];

export const roleTemplate = (id: unknown) => roleTemplates.find((template) => template.id === id);

/** What hiring needs from outside identity, given by wiring. */
export interface Hiring {
  /** The model a new employee gets when none is chosen (config/models.ts). */
  defaultModel: string;
  /** Whether a model id is one this deployment configures. */
  isModel(id: unknown): id is string;
  /** Gives a new employee its role's grants, inside the transaction that created it. */
  grant(db: Database, scope: Scope, template: RoleTemplateId): Promise<void>;
}

export interface Hire {
  template: RoleTemplateId;
  name: string;
  responsibilities: string;
  model: string;
}

/** Checks a hire, filling the template's name and responsibilities and the default model. */
export function hireInput(
  input: { template?: unknown; name?: unknown; responsibilities?: unknown; model?: unknown },
  hiring: Pick<Hiring, "defaultModel" | "isModel">,
): Hire | string {
  const template = roleTemplate(input.template ?? "custom");
  if (!template || template.id === "operations") return "Choose a role template";
  const text = (value: unknown, max: number) =>
    typeof value === "string" && value.trim() ? value.trim().slice(0, max) : undefined;
  const name = text(input.name, 80) ?? (template.name || undefined);
  const responsibilities =
    text(input.responsibilities, 2000) ?? (template.responsibilities || undefined);
  if (!name || !responsibilities) return "Send a name and responsibilities";
  const model = input.model ?? hiring.defaultModel;
  if (!hiring.isModel(model)) return "Choose a configured model";
  return { template: template.id, name, responsibilities, model };
}

/** Creates the employee and its template's grants together: no employee without its grants. */
export function hire(db: Database, businessId: string, input: Hire, hiring: Pick<Hiring, "grant">) {
  return atomically(db, async (db) => {
    const employee = await Effect.runPromise(
      createEmployee(db, businessId, {
        name: input.name,
        role: input.responsibilities,
        model: input.model,
        template: input.template,
      }),
    );
    await hiring.grant(db, { businessId, employeeId: employee.id }, input.template);
    return employee;
  });
}
