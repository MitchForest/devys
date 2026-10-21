import { defineApp } from "../../protocol/app.ts";

const capabilities = [
  "workList",
  "workCreate",
  "workUpdate",
  "workComplete",
  "projectList",
  "projectCreate",
  "projectUpdate",
  "projectAdd",
] as const;

export const work = defineApp({
  id: "work",
  name: "Work",
  icon: "checklist",
  summary: "Work items the business owes and the projects they belong to.",
  kind: "system",
  status: "available",
  records: [
    { kind: "item", title: "Work item" },
    { kind: "project", title: "Project" },
  ],
  capabilities,
  skills: [],
  connections: [],
  appears: "never",
  // Every employee tracks its work and takes part in projects.
  defaultGrants: {
    operations: capabilities,
    engineering: capabilities,
    growth: capabilities,
    "business-operations": capabilities,
    custom: capabilities,
  },
});
