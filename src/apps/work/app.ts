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
  "askOwner",
] as const;

export const work = defineApp({
  id: "work",
  name: "Work",
  icon: "checklist",
  summary:
    "Work items the business owes, the projects they belong to, employees' routines and what they ask the owner.",
  kind: "system",
  records: [
    { kind: "item", title: "Work item" },
    { kind: "project", title: "Project" },
    { kind: "routine", title: "Routine" },
  ],
  capabilities,
  skills: [],
  connections: [],
  appears: "never",
  // Every employee tracks its work, takes part in projects, proposes routines and asks the owner
  // (askOwner). Every role holds routineActivate in `ask` mode (its template says so): activation
  // is the owner's decision.
  defaultGrants: {
    operations: capabilities,
    engineering: capabilities,
    growth: capabilities,
    "business-operations": capabilities,
    custom: capabilities,
  },
});
