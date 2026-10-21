/** The role templates employees are hired from (the Team app's templates, in identity). */
export const roleTemplateIds = [
  "operations",
  "engineering",
  "growth",
  "business-operations",
  "custom",
] as const;

export type RoleTemplateId = (typeof roleTemplateIds)[number];
