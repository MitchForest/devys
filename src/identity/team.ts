import { Effect } from "effect";
import { atomically, type Database } from "../data/database.ts";
import { hireableRoleIds, type RoleTemplateId } from "../protocol/roles.ts";
import type { Scope } from "./contract.ts";
import { activeEmployee, createEmployee } from "./service.ts";

/** Whether an employee directs others' work: the Chief of Staff coordinates the team. */
export const coordinates = async (db: Database, scope: Scope) =>
  (await Effect.runPromise(activeEmployee(db, scope)))?.template === "chief-of-staff";

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
  /**
   * Granted capabilities held in `ask` mode, so each use is a decision the owner approves. Every
   * role asks for `routineActivate`: a routine runs only once the owner decided on its revision.
   */
  ask?: readonly string[];
}

export const roleTemplates: readonly RoleTemplate[] = [
  {
    id: "chief-of-staff",
    name: "Chief of Staff",
    summary: "Your front door: priorities, plans and who does what.",
    responsibilities:
      "Be the owner's front door. Turn what the owner asks for into work items with a clear plan, keep priorities moving, notice what is blocked or late, and bring the owner only real decisions, one at a time. Brief the owner on what changed. You start as the business's only employee: do the work yourself until a kind of work keeps coming that a specialist should own (payments and the books, accounts and admin, marketing, code), then propose hiring one (hireEmployee, from its template) and hand that work to them.",
    ask: ["hireEmployee", "deployProduction", "routineActivate"],
  },
  {
    id: "admin",
    name: "Admin",
    summary: "Accounts, domains, email, suppliers and documents.",
    responsibilities:
      "Keep the business's accounts and administration in order: sign-ups and accounts, domains and DNS, email setup, suppliers, documents and paperwork. Hand anything that costs money to Finance. Track follow-ups as work items so nothing is dropped.",
    ask: ["routineActivate"],
  },
  {
    id: "finance",
    name: "Finance",
    summary: "Paying for things, budgets and the books.",
    responsibilities:
      "Look after the business's money: pay for what the team needs with the business's card or spending account, ask the owner to approve each spend at its exact final total, keep subscriptions and renewals tracked, watch spending against budgets, and keep the books with receipts. Never pay without the owner's approval.",
    ask: ["routineActivate"],
  },
  {
    id: "growth",
    name: "Growth",
    summary: "Marketing, analytics and outreach.",
    responsibilities:
      "Grow the business. Research the market and competitors, sharpen positioning, set up and run marketing, social and analytics accounts, plan and measure campaigns, and prepare outreach for the owner's approval. Ground claims in sources.",
    ask: ["routineActivate"],
  },
  {
    id: "engineering",
    name: "Engineering",
    summary: "Builds, fixes and ships the business's software.",
    responsibilities:
      "Build, fix and ship the business's software. Work in the repositories on the owner's computer, run tests before calling work done, keep changes small and reviewable, and report what changed with evidence.",
    // Previews ship on Engineering's own authority; production is the owner's decision.
    ask: ["deployProduction", "routineActivate"],
  },
  {
    id: "custom",
    name: "",
    summary: "Start from a blank role and describe it yourself.",
    responsibilities: "",
    ask: ["routineActivate"],
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
  const id = hireableRoleIds.find((hireable) => hireable === (input.template ?? "custom"));
  const template = id && roleTemplate(id);
  if (!template) return "Choose a role template";
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
        responsibilities: input.responsibilities,
        model: input.model,
        template: input.template,
      }),
    );
    await hiring.grant(db, { businessId, employeeId: employee.id }, input.template);
    return employee;
  });
}
