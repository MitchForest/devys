import { Effect } from "effect";
import { modelsConfig } from "../../config/models.ts";
import { appCatalog } from "./apps.ts";
import { grantAll } from "../authority/service.ts";
import type { Hiring } from "../identity/team.ts";
import { roleTemplate } from "../identity/team.ts";
import type { Capability } from "../protocol/capability.ts";
import type { RoleTemplateId } from "../protocol/roles.ts";
import { isConfiguredModel } from "./models.ts";

/**
 * The grants a role gets, against the capabilities this deployment has: what the apps'
 * manifests propose to it, in `ask` mode where its template says so.
 */
export function templateGrants(role: RoleTemplateId, catalog: readonly Capability[]) {
  const proposed = new Set(appCatalog.flatMap((app) => app.defaultGrants?.[role] ?? []));
  const asks = new Set(roleTemplate(role)?.ask ?? []);
  return catalog
    .filter((contract) => proposed.has(contract.name))
    .map((contract) => ({
      capability: contract,
      mode: asks.has(contract.name) ? ("ask" as const) : ("auto" as const),
    }));
}

/** What identity's hiring needs: the configured models and the role grants, from authority. */
export const hiring = (catalog: () => readonly Capability[]): Hiring => ({
  defaultModel: modelsConfig.defaults.employee,
  isModel: isConfiguredModel,
  grant: (db, scope, role) =>
    Effect.runPromise(grantAll(db, scope, templateGrants(role, catalog()))),
});
