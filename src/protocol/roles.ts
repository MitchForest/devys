import { Schema } from "effect";

/** The role templates employees are hired from (the Team app's templates, in identity). */
export const roleTemplateIds = [
  "operations",
  "engineering",
  "growth",
  "business-operations",
  "custom",
] as const;

export const RoleTemplateId = Schema.Literals(roleTemplateIds);
export type RoleTemplateId = typeof RoleTemplateId.Type;

/** The templates people hire from: a business has exactly one Head of Operations. */
export const hireableRoleIds = roleTemplateIds.filter(
  (id): id is Exclude<RoleTemplateId, "operations"> => id !== "operations",
);
export const HireableRoleId = Schema.Literals(hireableRoleIds);
export type HireableRoleId = typeof HireableRoleId.Type;
