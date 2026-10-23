import { Schema } from "effect";

/** The role templates employees are hired from (the Team app's templates, in identity). */
export const roleTemplateIds = [
  "chief-of-staff",
  "admin",
  "finance",
  "growth",
  "engineering",
  "custom",
] as const;

export const RoleTemplateId = Schema.Literals(roleTemplateIds);
export type RoleTemplateId = typeof RoleTemplateId.Type;

/** The templates people hire from: a business has exactly one Chief of Staff. */
export const hireableRoleIds = roleTemplateIds.filter(
  (id): id is Exclude<RoleTemplateId, "chief-of-staff"> => id !== "chief-of-staff",
);
export const HireableRoleId = Schema.Literals(hireableRoleIds);
export type HireableRoleId = typeof HireableRoleId.Type;
