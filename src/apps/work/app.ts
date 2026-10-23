import { defineApp } from "../../protocol/app.ts";
import { bundledSkill } from "../../protocol/skill.ts";
import payingForThings from "./skills/paying-for-things/SKILL.md?raw";

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
  skills: [bundledSkill("paying-for-things", payingForThings)],
  connections: [],
  appears: "never",
  // Every employee tracks its work, takes part in projects, proposes routines and asks the owner
  // (askOwner). Every role holds routineActivate in `ask` mode (its template says so): activation
  // is the owner's decision.
  defaultGrants: {
    "chief-of-staff": capabilities,
    engineering: capabilities,
    growth: capabilities,
    admin: capabilities,
    finance: capabilities,
    custom: capabilities,
  },
});
