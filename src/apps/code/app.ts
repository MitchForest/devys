import { defineApp } from "../../protocol/app.ts";

const coding = [
  "codingStart",
  "codingStatus",
  "codingSend",
  "codingStop",
  "codingAccept",
  "codingPublish",
  "deployPreview",
  "deployProduction",
] as const;

export const code = defineApp({
  id: "code",
  name: "Code",
  icon: "chevron.left.forwardslash.chevron.right",
  summary: "Repositories, coding sessions, pull requests and deploys.",
  kind: "business",
  records: [{ kind: "session", title: "Coding session" }],
  capabilities: coding,
  skills: [],
  // The owner's own GitHub login on the Mac until the broker holds a GitHub connection.
  connections: [{ provider: "github", scopes: [] }],
  appears: "records",
  defaultGrants: { operations: coding, engineering: coding },
});
