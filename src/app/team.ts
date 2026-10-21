import { Effect, Schema } from "effect";
import type { Env } from "./env.ts";
import { modelsConfig } from "../../config/models.ts";
import { appCatalog } from "./apps.ts";
import { grantAll } from "../authority/service.ts";
import { atomically, type Database } from "../data/database.ts";
import type { RoleTemplateId, Scope } from "../identity/contract.ts";
import { createEmployee } from "../identity/service.ts";
import {
  capability,
  CapabilityError,
  Invocation,
  type Capability,
} from "../protocol/capability.ts";
import { isConfiguredModel } from "./models.ts";

/**
 * Role templates. Hiring copies one into an ordinary employee that the owner can then
 * edit; a template is not a record and later edits never flow back into it.
 */
export interface RoleTemplate {
  id: RoleTemplateId;
  name: string;
  responsibilities: string;
  summary: string;
  /** Capabilities granted at hire, in `auto` mode; "all" grants every capability. */
  capabilities: readonly string[] | "all";
  /** Capabilities granted in `ask` mode, so each use is a decision the owner approves. */
  ask?: readonly string[];
}

// Every employee can track work, use memory and projects, and read its own history.
const collaboration = [
  "commitmentList",
  "commitmentCreate",
  "commitmentUpdate",
  "commitmentComplete",
  "conversationHistory",
  "remember",
  "recall",
  "forget",
  "projectList",
  "projectCreate",
  "projectUpdate",
  "projectAdd",
] as const;
const files = ["readSkill", "read", "write", "printPdf", "importAttachment"] as const;
const browser = [
  "browserOpen",
  "browserRead",
  "browserClick",
  "browserType",
  "browserPress",
] as const;
/** What the apps' manifests propose to a role at hire. */
const proposed = (role: RoleTemplateId) =>
  appCatalog.flatMap((app) => app.defaultGrants?.[role] ?? []);

export const roleTemplates: readonly RoleTemplate[] = [
  {
    id: "operations",
    name: "Head of Operations",
    summary: "Runs the business day to day and coordinates the team.",
    responsibilities:
      "Run the business day to day. Keep the owner's priorities moving, coordinate the team by handing work to the right employee as commitments, notice what is blocked or late, and bring the owner only real decisions. Propose new hires when the work needs a role nobody holds.",
    capabilities: "all",
    ask: ["hireEmployee", "deployProduction"],
  },
  {
    id: "engineering",
    name: "Engineering",
    summary: "Builds, fixes and ships the business's software.",
    responsibilities:
      "Build, fix and ship the business's software. Work in the repositories on the owner's computer, run tests before calling work done, keep changes small and reviewable, and report what changed with evidence.",
    capabilities: [
      ...collaboration,
      ...files,
      ...proposed("engineering"),
      ...browser,
      "run",
      "readPublicUrl",
    ],
    // Previews ship on Engineering's own authority; production is the owner's decision.
    ask: ["deployProduction"],
  },
  {
    id: "growth",
    name: "Growth",
    summary: "Finds customers: research, positioning, campaigns and outreach.",
    responsibilities:
      "Grow the business. Research the market and competitors, sharpen positioning, plan and measure campaigns, and prepare outreach for the owner's approval. Ground claims in sources.",
    capabilities: [...collaboration, ...files, ...proposed("growth"), ...browser, "readPublicUrl"],
  },
  {
    id: "business-operations",
    name: "Business Operations",
    summary: "Keeps records, documents, suppliers and admin in order.",
    responsibilities:
      "Keep the business's records, documents and administration in order: suppliers, accounts, schedules and paperwork. Track follow-ups as commitments so nothing is dropped.",
    capabilities: [
      ...collaboration,
      ...files,
      ...proposed("business-operations"),
      ...browser,
      "readPublicUrl",
    ],
  },
  {
    id: "custom",
    name: "",
    summary: "Start from a blank role and describe it yourself.",
    responsibilities: "",
    capabilities: [...collaboration],
  },
];

export const roleTemplate = (id: unknown) => roleTemplates.find((template) => template.id === id);

/** The grants a template gives, against the capabilities this deployment has. */
export function templateGrants(template: RoleTemplate, catalog: readonly Capability[]) {
  const asks = new Set(template.ask ?? []);
  return catalog
    .filter(
      (contract) =>
        asks.has(contract.name) ||
        template.capabilities === "all" ||
        template.capabilities.includes(contract.name),
    )
    .map((contract) => ({
      capability: contract,
      mode: asks.has(contract.name) ? ("ask" as const) : ("auto" as const),
    }));
}

export interface Hire {
  template: RoleTemplateId;
  name: string;
  responsibilities: string;
  model: string;
}

/** Checks a hire, filling the template's name and responsibilities and the default model. */
export function hireInput(input: {
  template?: unknown;
  name?: unknown;
  responsibilities?: unknown;
  model?: unknown;
}): Hire | string {
  const template = roleTemplate(input.template ?? "custom");
  if (!template || template.id === "operations") return "Choose a role template";
  const text = (value: unknown, max: number) =>
    typeof value === "string" && value.trim() ? value.trim().slice(0, max) : undefined;
  const name = text(input.name, 80) ?? (template.name || undefined);
  const responsibilities =
    text(input.responsibilities, 2000) ?? (template.responsibilities || undefined);
  if (!name || !responsibilities) return "Send a name and responsibilities";
  const model = input.model ?? modelsConfig.defaults.employee;
  if (!isConfiguredModel(model)) return "Choose a configured model";
  return { template: template.id, name, responsibilities, model };
}

/** Creates the employee and gives it its template's grants. */
/** Creates the employee and its template's grants together: no employee without its grants. */
export function hire(
  db: Database,
  businessId: string,
  input: Hire,
  catalog: readonly Capability[],
) {
  return atomically(db, async (db) => {
    const employee = await Effect.runPromise(
      createEmployee(db, businessId, {
        name: input.name,
        role: input.responsibilities,
        model: input.model,
        template: input.template,
      }),
    );
    const scope: Scope = { businessId, employeeId: employee.id };
    await Effect.runPromise(
      grantAll(db, scope, templateGrants(roleTemplate(input.template)!, catalog)),
    );
    return employee;
  });
}

/**
 * Employees propose hires through this capability. Operations holds it in `ask` mode, so a
 * proposal becomes a decision; approving it lets the identical call through once.
 */
export function teamCapabilities(env: Env, catalog: () => readonly Capability[]) {
  return [
    capability({
      name: "hireEmployee",
      description:
        "Hire a new employee from a role template (engineering, growth, business-operations or custom) with a name, responsibilities and optionally a model id. The owner approves each hire.",
      effect: "change",
      // Each call hires someone new: after an interruption, list the team before trying again.
      replay: "reconcile",
      input: Schema.Struct({
        template: Schema.Literals(["engineering", "growth", "business-operations", "custom"]),
        name: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(80)),
        responsibilities: Schema.optional(Schema.String.check(Schema.isMaxLength(2000))),
        model: Schema.optional(Schema.String.check(Schema.isMaxLength(120))),
      }),
      output: Schema.Struct({ id: Schema.String, name: Schema.String }),
      execute: (input) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          const checked = hireInput(input);
          if (typeof checked === "string")
            return yield* Effect.fail(
              new CapabilityError({ code: "invalid_input", message: checked }),
            );
          const employee = yield* Effect.tryPromise({
            try: () => hire(env.HYPERDRIVE, businessId, checked, catalog()),
            catch: () =>
              new CapabilityError({ code: "unavailable", message: "Hiring failed; try again" }),
          });
          return { id: employee.id, name: employee.name };
        }),
    }),
  ];
}
