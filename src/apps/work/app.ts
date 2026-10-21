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
  "routineList",
  "routinePropose",
  "routineActivate",
  "routinePause",
] as const;

export const work = defineApp({
  id: "work",
  name: "Work",
  icon: "checklist",
  summary: "Work items the business owes, the projects they belong to and employees' routines.",
  kind: "system",
  status: "available",
  records: [
    { kind: "item", title: "Work item" },
    { kind: "project", title: "Project" },
    { kind: "routine", title: "Routine" },
  ],
  capabilities,
  skills: [],
  connections: [],
  appears: "never",
  // Every employee tracks its work, takes part in projects and proposes routines. Every role
  // holds routineActivate in `ask` mode (its template says so): activation is the owner's decision.
  defaultGrants: {
    operations: capabilities,
    engineering: capabilities,
    growth: capabilities,
    "business-operations": capabilities,
    custom: capabilities,
  },
});
